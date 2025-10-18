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
        let resolvedConfiguration = configuration ?? Configuration(discoveryInfoProvider: { MPCManager.makeDefaultDiscoveryInfo() })
        self.configuration = resolvedConfiguration
        self.sessionFactory = sessionFactory
        self.peerID = MPCManager.makePersistentPeerID()
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
        advertiser = MCNearbyServiceAdvertiser(peer: peerID,
                                               discoveryInfo: configuration.discoveryInfoProvider(),
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
        }

        let transfer = MPCTransferController(sessionController: controller)
        transfer.onTransferProgress = { [weak self] progress in
            guard let self else { return }
            self.transferProgress = progress.sorted { $0.startedAt < $1.startedAt }
        }
        transfer.onHelloMessage = { [weak self] message, peer in
            guard let self else { return }
            self.updateConnectedPeer(peerID: peer, shortName: message.displayName)
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
            if let current = connectedPeer, current.peerID == peerID {
                connectedPeer = nil
                sessionState = .idle
            }
        case .connecting:
            break
        @unknown default:
            break
        }
    }

    private func sendHello(to peerID: MCPeerID) {
        let hello = MPCHelloMessage(displayName: self.peerID.displayName, supportsFileTransfer: true)
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

    private func updateConnectedPeer(peerID: MCPeerID, shortName: String) {
        if let index = nearbyPeers.firstIndex(where: { $0.peerID == peerID }) {
            var info = nearbyPeers[index].discoveryInfo
            info["shortName"] = shortName
            nearbyPeers[index] = MPCPeer(peerID: peerID, discoveryInfo: info, lastSeen: Date())
            nearbyPeers.sort { $0.displayName < $1.displayName }
        }

        if var current = connectedPeer, current.peerID == peerID {
            var info = current.discoveryInfo
            info["shortName"] = shortName
            let updated = MPCPeer(peerID: peerID, discoveryInfo: info, lastSeen: Date())
            connectedPeer = updated
            sessionState = .connected(updated)
        }
    }

    private static func makeDefaultDiscoveryInfo() -> [String: String] {
        var info: [String: String] = [:]
        let defaults = UserDefaults.standard
        if let shortName = defaults.string(forKey: "mpc.peer.displayName") {
            info["shortName"] = shortName
        }
        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            info["appVersion"] = version
        }
        return info
    }

    private static func makePersistentPeerID() -> MCPeerID {
        let defaults = UserDefaults.standard
        let key = "mpc.peer.displayName"
        if let stored = defaults.string(forKey: key) {
            return MCPeerID(displayName: stored)
        }

        let base = UIDevice.current.name
        let allowed = base.replacingOccurrences(of: "[^A-Za-z0-9-_]", with: "", options: .regularExpression)
        let sanitized = allowed.isEmpty ? "NannyUser" : allowed
        let displayName = String(sanitized.prefix(24))
        defaults.set(displayName, forKey: key)
        return MCPeerID(displayName: displayName)
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
