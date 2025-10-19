import Combine
import Foundation
import MultipeerConnectivity
import os.log
import UIKit

/// Orchestrates peer discovery, invitations, and session lifecycle.
@MainActor
final class MPCManager: NSObject, ObservableObject {
    struct Configuration {
        let serviceType: String
        let invitationTimeout: TimeInterval
        let discoveryInfoProvider: () -> [String: String]

        init(serviceType: String = "nanme-share",
             invitationTimeout: TimeInterval = 15,
             discoveryInfoProvider: @escaping () -> [String: String] = { [:] }) {
            self.serviceType = serviceType
            self.invitationTimeout = invitationTimeout
            self.discoveryInfoProvider = discoveryInfoProvider
        }
    }

    private enum DefaultsKey {
        static let peerDisplayName = "mpc.peer.displayName"
        static let peerShortName = "mpc.peer.shortName"
    }

    private struct Identity {
        let peerID: MCPeerID
        let shortName: String
    }

    enum SessionState: Equatable {
        case idle
        case browsing
        case advertising
        case inviting(MPCPeer)
        case connected(MPCPeer)
        case disconnecting
    }

    @Published private(set) var sessionState: SessionState = .idle
    @Published private(set) var nearbyPeers: [MPCPeer] = []
    @Published private(set) var connectedPeer: MPCPeer?
    @Published private(set) var pendingInvitation: MPCPeer?
    @Published private(set) var transferProgress: [MPCTransferProgress] = []
    @Published private(set) var lastError: MPCError?
    @Published private(set) var lastReceivedEnvelopeAt: Date?

    private let configuration: Configuration
    private let peerID: MCPeerID
    private var localShortName: String
    private let sessionFactory: MPCSessionFactory

    private var currentSession: MCSession!
    private var sessionController: MPCSessionController!
    private var transferController: MPCTransferController!
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var invitationHandler: ((Bool, MCSession?) -> Void)?
    private var invitationExpiryTask: Task<Void, Never>?

    private let log = Logger(subsystem: "com.prioritybit.babynanny", category: "mpc")

    init(configuration: Configuration? = nil,
         sessionFactory: MPCSessionFactory = DefaultMPCSessionFactory()) {
        let identity = MPCManager.makeIdentity()
        let resolvedConfiguration = configuration ?? Configuration(discoveryInfoProvider: {
            MPCManager.makeDefaultDiscoveryInfo()
        })
        self.configuration = resolvedConfiguration
        self.sessionFactory = sessionFactory
        self.peerID = identity.peerID
        self.localShortName = identity.shortName
        super.init()
        prepareSession()
    }


    func startBrowsing() {
        guard browser == nil else { return }
        browser = MCNearbyServiceBrowser(peer: peerID, serviceType: configuration.serviceType)
        browser?.delegate = self
        browser?.startBrowsingForPeers()
        log.debug("Started browsing")
        sessionState = .browsing
    }

    func stopBrowsing() {
        browser?.stopBrowsingForPeers()
        browser?.delegate = nil
        browser = nil
        if advertiser != nil {
            sessionState = .advertising
        } else if case .browsing = sessionState {
            sessionState = .idle
        }
    }

    func startAdvertising() {
        guard advertiser == nil else { return }
        refreshLocalShortNameIfNeeded()
        var discoveryInfo = configuration.discoveryInfoProvider()
        if discoveryInfo["shortName"].map({ $0.isEmpty }) != false {
            discoveryInfo["shortName"] = localShortName
        }
        if discoveryInfo["prettyName"].map({ $0.isEmpty }) != false,
           let encoded = MPCManager.encodePrettyName(from: UIDevice.current.name) {
            discoveryInfo["prettyName"] = encoded
        }
        advertiser = MCNearbyServiceAdvertiser(peer: peerID,
                                               discoveryInfo: discoveryInfo,
                                               serviceType: configuration.serviceType)
        advertiser?.delegate = self
        advertiser?.startAdvertisingPeer()
        log.debug("Started advertising")
        sessionState = .advertising
    }

    func stopAdvertising() {
        advertiser?.stopAdvertisingPeer()
        advertiser?.delegate = nil
        advertiser = nil
        if browser != nil {
            sessionState = .browsing
        } else if case .advertising = sessionState {
            sessionState = .idle
        }
    }

    func stopAll() {
        stopBrowsing()
        stopAdvertising()
        invitationExpiryTask?.cancel()
        invitationExpiryTask = nil
        invitationHandler = nil
        sessionController?.disconnect()
        prepareSession()
        nearbyPeers.removeAll()
        connectedPeer = nil
        pendingInvitation = nil
        transferProgress.removeAll()
        sessionState = .idle
    }

    func invite(_ peer: MPCPeer) {
        guard let browser else { return }
        if let connected = connectedPeer, connected.peerID != peer.peerID {
            lastError = .invalidState(expected: connected.displayName, actual: peer.displayName)
            return
        }
        sessionState = .inviting(peer)
        sessionController.updateLifecycleState(.connecting(peer: peer.peerID))
        browser.invitePeer(peer.peerID, to: currentSession, withContext: nil, timeout: configuration.invitationTimeout)
        invitationExpiryTask?.cancel()
        invitationExpiryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(configuration.invitationTimeout * 1_000_000_000))
            await self?.handleInvitationTimedOut(for: peer)
        }
    }

    func respondToInvitation(accept: Bool) {
        guard let handler = invitationHandler else { return }
        invitationHandler = nil
        invitationExpiryTask?.cancel()
        invitationExpiryTask = nil
        handler(accept, accept ? currentSession : nil)
        pendingInvitation = nil
    }

    func disconnect() {
        sessionState = .disconnecting
        sessionController.disconnect()
        connectedPeer = nil
        sessionState = .idle
    }

    func sendProfile(_ export: ProfileExportV1) throws {
        guard let connectedPeer else { throw MPCError.invalidState(expected: "connected", actual: "disconnected") }
        try transferController.sendMessage(payload: export, type: .profileSnapshot, to: [connectedPeer.peerID])
    }

    func sendChanges(_ delta: ActionsDeltaMessage) throws {
        guard let connectedPeer else { throw MPCError.invalidState(expected: "connected", actual: "disconnected") }
        try transferController.sendMessage(payload: delta, type: .actionsDelta, to: [connectedPeer.peerID])
    }

    func sendAcknowledgement(for identifier: UUID) throws {
        guard let connectedPeer else { throw MPCError.invalidState(expected: "connected", actual: "disconnected") }
        let ack = MPCAcknowledgement(identifier: identifier, receivedAt: Date())
        try transferController.sendMessage(payload: ack, type: .ack, to: [connectedPeer.peerID], mode: .reliable)
    }

    @discardableResult
    func sendFile(at url: URL, named name: String) throws -> UUID {
        guard let connectedPeer else { throw MPCError.invalidState(expected: "connected", actual: "disconnected") }
        return transferController.sendResource(at: url, named: name, to: connectedPeer.peerID)
    }

    func cancelTransfer(id: UUID) {
        transferController.cancelTransfer(id: id)
    }

    private func prepareSession() {
        sessionController?.onPeerStateChange = nil
        sessionController?.onSessionFailed = nil
        transferController?.onTransferProgress = nil
        transferController?.onHelloMessage = nil
        transferController?.onCapabilitiesMessage = nil
        transferController?.onProfileExport = nil
        transferController?.onActionsDelta = nil
        transferController?.onAcknowledgement = nil
        transferController?.onIncompatibleEnvelope = nil
        transferController?.onErrorMessage = nil
        transferController?.onResourceReceived = nil
        transferController = nil
        sessionController = nil
        if let currentSession {
            currentSession.delegate = nil
            currentSession.disconnect()
        }
        let session = sessionFactory.makeSession(for: peerID)
        currentSession = session
        let controller = MPCSessionController(session: session)
        controller.onPeerStateChange = { [weak self] peerID, state in
            guard let self else { return }
            self.handlePeerStateChange(peerID: peerID, state: state)
        }
        controller.onSessionFailed = { [weak self] error in
            guard let self else { return }
            self.lastError = error
            self.connectedPeer = nil
            self.sessionState = .idle
            self.invitationExpiryTask?.cancel()
            self.invitationExpiryTask = nil
            self.prepareSession()
        }

        let transfer = MPCTransferController(sessionController: controller)
        transfer.onTransferProgress = { [weak self] progress in
            guard let self else { return }
            self.transferProgress = progress.sorted { $0.startedAt < $1.startedAt }
        }
        transfer.onHelloMessage = { [weak self] message, peer in
            guard let self else { return }
            self.updateConnectedPeer(peerID: peer, displayName: message.displayName)
        }
        transfer.onProfileExport = { [weak self] _, _ in
            guard let self else { return }
            self.lastReceivedEnvelopeAt = Date()
        }
        transfer.onActionsDelta = { [weak self] _, _ in
            guard let self else { return }
            self.lastReceivedEnvelopeAt = Date()
        }
        transfer.onIncompatibleEnvelope = { [weak self] _, error, _ in
            guard let self else { return }
            self.lastError = error
        }
        transfer.onErrorMessage = { [weak self] message, _ in
            guard let self else { return }
            self.lastError = .sessionFailed
            self.log.error("Received MPC error: \(message.code, privacy: .public)")
        }
        transfer.onResourceReceived = { [weak self] _, _, _ in
            guard let self else { return }
            self.lastReceivedEnvelopeAt = Date()
        }

        self.sessionController = controller
        self.transferController = transfer
    }

    private func handlePeerStateChange(peerID: MCPeerID, state: MCSessionState) {
        switch state {
        case .connected:
            let metadata = nearbyPeers.first(where: { $0.peerID == peerID }) ?? MPCPeer(peerID: peerID, discoveryInfo: [:], lastSeen: Date())
            let peer = metadata.updating(lastSeen: Date())
            connectedPeer = peer
            sessionState = .connected(peer)
            invitationExpiryTask?.cancel()
            invitationExpiryTask = nil
            sendHello(to: peerID)
        case .notConnected:
            if case .inviting(let target) = sessionState, target.peerID == peerID {
                invitationExpiryTask?.cancel()
                invitationExpiryTask = nil
                sessionState = .idle
                lastError = .sessionFailed
            }
            if let current = connectedPeer, current.peerID == peerID {
                connectedPeer = nil
                sessionState = .idle
            }
            prepareSession()
        case .connecting:
            break
        @unknown default:
            break
        }
    }

    private func sendHello(to peerID: MCPeerID) {
        refreshLocalShortNameIfNeeded()
        let actualName = UIDevice.current.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let helloName = actualName.isEmpty ? localShortName : actualName
        let hello = MPCHelloMessage(displayName: helloName, supportsFileTransfer: true)
        do {
            try transferController.sendMessage(payload: hello, type: .hello, to: [peerID], mode: .reliable)
        } catch {
            lastError = .sessionFailed
        }
        let capabilities = MPCCapabilitiesMessage(supportedEnvelopeVersion: MPCEnvelope.currentVersion, maximumResourceSize: 5 * 1024 * 1024)
        try? transferController.sendMessage(payload: capabilities, type: .capabilities, to: [peerID], mode: .reliable)
    }

    private func handleInvitationTimedOut(for peer: MPCPeer) {
        guard case .inviting(let target) = sessionState, target.id == peer.id else { return }
        sessionState = .idle
        lastError = .timeout
    }

    private func updatePeerList(with peerID: MCPeerID, info: [String: String]?) {
        let metadata = MPCPeer(peerID: peerID,
                               discoveryInfo: info ?? [:],
                               lastSeen: Date())
        if let index = nearbyPeers.firstIndex(where: { $0.peerID == peerID }) {
            nearbyPeers[index] = metadata
        } else {
            nearbyPeers.append(metadata)
        }
        nearbyPeers.sort { $0.displayName < $1.displayName }
    }

    private func removePeer(_ peerID: MCPeerID) {
        nearbyPeers.removeAll { $0.peerID == peerID }
    }

    private func updateConnectedPeer(peerID: MCPeerID, displayName: String) {
        let sanitized = MPCManager.sanitizeDiscoveryName(displayName)
        let prettyEncoded = MPCManager.encodePrettyName(from: displayName)
        if let index = nearbyPeers.firstIndex(where: { $0.peerID == peerID }) {
            var info = nearbyPeers[index].discoveryInfo
            if sanitized.isEmpty == false {
                info["shortName"] = sanitized
            }
            if let prettyEncoded {
                info["prettyName"] = prettyEncoded
            }
            nearbyPeers[index] = MPCPeer(peerID: peerID, discoveryInfo: info, lastSeen: Date())
            nearbyPeers.sort { $0.displayName < $1.displayName }
        }

        if var current = connectedPeer, current.peerID == peerID {
            var info = current.discoveryInfo
            if sanitized.isEmpty == false {
                info["shortName"] = sanitized
            }
            if let prettyEncoded {
                info["prettyName"] = prettyEncoded
            }
            let updated = MPCPeer(peerID: peerID, discoveryInfo: info, lastSeen: Date())
            connectedPeer = updated
            sessionState = .connected(updated)
        }
    }

    private func refreshLocalShortNameIfNeeded() {
        let resolved = MPCManager.resolveShortName()
        if resolved != localShortName {
            localShortName = resolved
        }
    }

    private static func makeDefaultDiscoveryInfo(shortName: String? = nil) -> [String: String] {
        var info: [String: String] = [:]
        let resolvedShortName = shortName ?? resolveShortName()
        info["shortName"] = resolvedShortName
        if let pretty = encodePrettyName(from: UIDevice.current.name) {
            info["prettyName"] = pretty
        }
        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            info["appVersion"] = version
        }
        return info
    }

    private static func makeIdentity() -> Identity {
        let shortName = resolveShortName()
        let defaults = UserDefaults.standard
        if let storedDisplayName = defaults.string(forKey: DefaultsKey.peerDisplayName) {
            return Identity(peerID: MCPeerID(displayName: storedDisplayName), shortName: shortName)
        }

        let base = sanitizePeerDisplayNameComponent(shortName)
        let suffix = makeStableSuffix()
        let composed = [base, suffix].joined(separator: "-")
        defaults.set(composed, forKey: DefaultsKey.peerDisplayName)
        return Identity(peerID: MCPeerID(displayName: composed), shortName: shortName)
    }

    private static func resolveShortName() -> String {
        let defaults = UserDefaults.standard
        let rawName = UIDevice.current.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let sanitized = sanitizeDiscoveryName(rawName)
        let fallback = UIDevice.current.localizedModel
        let shortName = sanitized.isEmpty ? fallback : sanitized
        if defaults.string(forKey: DefaultsKey.peerShortName) != shortName {
            defaults.set(shortName, forKey: DefaultsKey.peerShortName)
        }
        return shortName
    }

    private static func sanitizeDiscoveryName(_ name: String) -> String {
        let filteredScalars = name.unicodeScalars.filter { scalar in
            scalar.isASCII && scalar.value >= 32
        }
        var ascii = String(String.UnicodeScalarView(filteredScalars))
        ascii = ascii.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        let trimmed = ascii.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return ""
        }
        return String(trimmed.prefix(60))
    }

    private static func sanitizePeerDisplayNameComponent(_ name: String) -> String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        let filteredScalars = name.unicodeScalars.filter { allowed.contains($0) }
        let sanitized = String(String.UnicodeScalarView(filteredScalars))
        let trimmed = sanitized.trimmingCharacters(in: CharacterSet(charactersIn: "-_"))
        if trimmed.isEmpty {
            return "NannyUser"
        }
        return String(trimmed.prefix(48))
    }

    private static func makeStableSuffix() -> String {
        let raw = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        let cleaned = raw.replacingOccurrences(of: "-", with: "").uppercased()
        let suffix = cleaned.suffix(4)
        return suffix.isEmpty ? "0000" : String(suffix)
    }

    private static func encodePrettyName(from name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }
        return Data(trimmed.utf8).base64EncodedString()
    }
}

extension MPCManager: MCNearbyServiceBrowserDelegate {
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        Task { @MainActor [weak self] in
            self?.updatePeerList(with: peerID, info: info)
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        Task { @MainActor [weak self] in
            self?.removePeer(peerID)
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        Task { @MainActor [weak self] in
            self?.lastError = .sessionFailed
        }
    }
}

extension MPCManager: MCNearbyServiceAdvertiserDelegate {
    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                                didReceiveInvitationFromPeer peerID: MCPeerID,
                                withContext context: Data?,
                                invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let connected = connectedPeer, connected.peerID != peerID {
                invitationHandler(false, nil)
                self.lastError = .invalidState(expected: connected.displayName, actual: peerID.displayName)
                return
            }

            let peer = MPCPeer(peerID: peerID, discoveryInfo: [:], lastSeen: Date())
            self.pendingInvitation = peer
            self.invitationHandler = invitationHandler
            self.invitationExpiryTask?.cancel()
            self.invitationExpiryTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64((self?.configuration.invitationTimeout ?? 15) * 1_000_000_000))
                await self?.expirePendingInvitation()
            }
        }
    }

    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        Task { @MainActor [weak self] in
            self?.lastError = .sessionFailed
        }
    }
}

private extension MPCManager {
    func expirePendingInvitation() {
        pendingInvitation = nil
        invitationHandler?(false, nil)
        invitationHandler = nil
        lastError = .timeout
    }
}
