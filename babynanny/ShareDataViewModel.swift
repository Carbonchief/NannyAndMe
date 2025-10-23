import Combine
import Foundation
import SwiftUI

@MainActor
final class ShareDataViewModel: ObservableObject {
    @Published private(set) var nearbyPeers: [MPCPeer] = []
    @Published private(set) var connectedPeer: MPCPeer?
    @Published private(set) var sessionState: MPCManager.SessionState = .idle
    @Published private(set) var transferProgress: [MPCTransferProgress] = []
    @Published private(set) var pendingInvitation: MPCPeer?
    @Published private(set) var toastMessage: String?
    @Published private(set) var lastError: MPCError?
    @Published private(set) var lastReceivedAt: Date?

    private let manager: MPCManager
    private var profileProvider: (() -> ChildProfile)?
    private var actionStateProvider: ((UUID) -> ProfileActionState)?
    private var snapshotMergeHandler: ((ProfileExportV1) throws -> ImportResult)?
    private var cancellables: Set<AnyCancellable> = []
    private var lastDeltaSentAt: Date?
    private var browsingRequested = true
    private var advertisingRequested = true

    struct ImportResult: Equatable {
        let added: Int
        let updated: Int
        let didUpdateProfile: Bool

        static let empty = ImportResult(added: 0, updated: 0, didUpdateProfile: false)
    }

    init(manager: MPCManager,
         profileProvider: @escaping () -> ChildProfile,
         actionStateProvider: @escaping (UUID) -> ProfileActionState) {
        self.manager = manager
        self.profileProvider = profileProvider
        self.actionStateProvider = actionStateProvider
        bindManager()
    }

    convenience init(manager: MPCManager) {
        self.init(manager: manager, profileProvider: { fatalError("Profile provider not configured") }, actionStateProvider: { _ in fatalError("Action provider not configured") })
        profileProvider = nil
        actionStateProvider = nil
    }

    func configure(profileProvider: @escaping () -> ChildProfile,
                   actionStateProvider: @escaping (UUID) -> ProfileActionState,
                   snapshotMergeHandler: @escaping (ProfileExportV1) throws -> ImportResult) {
        self.profileProvider = profileProvider
        self.actionStateProvider = actionStateProvider
        self.snapshotMergeHandler = snapshotMergeHandler
    }

    func startBrowsing() {
        browsingRequested = true
        manager.startBrowsing()
    }

    func stopBrowsing() {
        browsingRequested = false
        manager.stopBrowsing()
    }

    func advertise(on isEnabled: Bool) {
        if isEnabled {
            advertisingRequested = true
            manager.startAdvertising()
        } else {
            advertisingRequested = false
            manager.stopAdvertising()
        }
    }

    func stopAll() {
        browsingRequested = false
        advertisingRequested = false
        manager.stopAll()
    }

    func invite(_ peer: MPCPeer) {
        manager.invite(peer)
    }

    func disconnect() {
        manager.disconnect()
    }

    func acceptInvitation() {
        manager.respondToInvitation(accept: true)
    }

    func declineInvitation() {
        manager.respondToInvitation(accept: false)
    }

    func sendProfileSnapshot() {
        do {
            guard let profileProvider, let actionStateProvider else { return }
            let profile = profileProvider()
            let state = actionStateProvider(profile.id)
            let payload = ProfileExportV1(profile: profile, actions: state)
            try manager.sendProfile(payload)
            lastDeltaSentAt = Date()
            emitToast(L10n.ShareData.Nearby.sentSnapshot(profile.displayName))
        } catch {
            handle(error: error)
        }
    }

    func sendLatestChanges() {
        do {
            guard let profileProvider, let actionStateProvider else { return }
            let profile = profileProvider()
            let state = actionStateProvider(profile.id)
            let cutoff = lastDeltaSentAt ?? Date(timeIntervalSinceNow: -3600)
            let updated = state.allActions.filter { $0.updatedAt >= cutoff }
            guard updated.isEmpty == false else {
                emitToast(L10n.ShareData.Nearby.noRecentChanges)
                return
            }
            let delta = ActionsDeltaMessage(profileID: profile.id,
                                            updatedActions: updated,
                                            removedActionIDs: [])
            try manager.sendChanges(delta)
            lastDeltaSentAt = Date()
            emitToast(L10n.ShareData.Nearby.sentDelta)
        } catch {
            handle(error: error)
        }
    }

    func sendExportFile(at url: URL) {
        do {
            let filename = url.lastPathComponent
            _ = try manager.sendFile(at: url, named: filename)
            emitToast(L10n.ShareData.Nearby.sendingFile(filename))
        } catch {
            handle(error: error)
        }
    }

    func cancelTransfer(_ progress: MPCTransferProgress) {
        guard isTransferCancellable(progress) else { return }
        manager.cancelTransfer(id: progress.id)
        emitToast(L10n.ShareData.Nearby.transferCancelled)
    }

    func isTransferCancellable(_ progress: MPCTransferProgress) -> Bool {
        switch progress.kind {
        case .message:
            return false
        case .resource:
            return progress.progress < 1
        }
    }

    func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .background, .inactive:
            manager.stopBrowsing()
        case .active:
            if browsingRequested {
                manager.startBrowsing()
            }
            if advertisingRequested {
                manager.startAdvertising()
            }
        @unknown default:
            break
        }
    }

    private func bindManager() {
        manager.$nearbyPeers
            .receive(on: DispatchQueue.main)
            .sink { [weak self] peers in
                self?.nearbyPeers = peers
            }
            .store(in: &cancellables)

        manager.$connectedPeer
            .receive(on: DispatchQueue.main)
            .sink { [weak self] peer in
                self?.connectedPeer = peer
            }
            .store(in: &cancellables)

        manager.$sessionState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.sessionState = state
            }
            .store(in: &cancellables)

        manager.$transferProgress
            .receive(on: DispatchQueue.main)
            .sink { [weak self] progress in
                self?.transferProgress = progress
            }
            .store(in: &cancellables)

        manager.$pendingInvitation
            .receive(on: DispatchQueue.main)
            .sink { [weak self] peer in
                self?.pendingInvitation = peer
            }
            .store(in: &cancellables)

        manager.$lastError
            .receive(on: DispatchQueue.main)
            .sink { [weak self] error in
                guard let self else { return }
                self.lastError = error
                if let error {
                    self.emitToast(self.errorMessage(for: error))
                }
            }
            .store(in: &cancellables)

        manager.$lastReceivedEnvelopeAt
            .receive(on: DispatchQueue.main)
            .sink { [weak self] date in
                self?.lastReceivedAt = date
            }
            .store(in: &cancellables)

        manager.onProfileExport = { [weak self] payload, _ in
            self?.handleIncomingSnapshot(payload)
        }
    }

    private func emitToast(_ message: String) {
        toastMessage = message
    }

    func clearToast() {
        toastMessage = nil
    }

    private func handle(error: Error) {
        if let mpcError = error as? MPCError {
            lastError = mpcError
            emitToast(errorMessage(for: mpcError))
        } else if let localized = error as? LocalizedError, let description = localized.errorDescription {
            emitToast(description)
        } else {
            emitToast(L10n.ShareData.Nearby.unknownError)
        }
    }

    private func errorMessage(for error: MPCError) -> String {
        switch error {
        case .timeout:
            return L10n.ShareData.Nearby.timeout
        case .invitationRejected:
            return L10n.ShareData.Nearby.rejected
        case let .invalidState(expected, actual):
            return L10n.ShareData.Nearby.invalidState(expected, actual)
        case .sessionFailed:
            return L10n.ShareData.Nearby.sessionFailed
        case .encodingFailed, .decodingFailed:
            return L10n.ShareData.Nearby.codecError
        case .unsupportedEnvelopeVersion:
            return L10n.ShareData.Nearby.incompatibleVersion
        case .transferCancelled:
            return L10n.ShareData.Nearby.transferCancelled
        case .resourceNotFound:
            return L10n.ShareData.Nearby.resourceMissing
        }
    }

    private func handleIncomingSnapshot(_ payload: ProfileExportV1) {
        do {
            if let handler = snapshotMergeHandler {
                let result = try handler(payload)
                if result.added > 0 || result.updated > 0 || result.didUpdateProfile {
                    emitToast(L10n.ShareData.Nearby.receivedSnapshot(payload.profile.displayName,
                                                                     result.added,
                                                                     result.updated))
                } else {
                    emitToast(L10n.ShareData.Nearby.receivedSnapshotNoChanges(payload.profile.displayName))
                }
            } else {
                emitToast(L10n.ShareData.Nearby.receivedSnapshotNoChanges(payload.profile.displayName))
            }
        } catch {
            handle(error: error)
        }
    }
}

private extension ProfileActionState {
    var allActions: [BabyActionSnapshot] {
        let active = activeActions.values
        return Array(active) + history
    }
}
