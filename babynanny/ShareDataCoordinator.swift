import CloudKit
import Foundation
import os
import SwiftData
import SwiftUI

@MainActor
final class ShareDataCoordinator: ObservableObject {
    struct ExternalImportRequest: Identifiable, Equatable {
        let id = UUID()
        let url: URL

        static func == (lhs: ExternalImportRequest, rhs: ExternalImportRequest) -> Bool {
            lhs.id == rhs.id
        }
    }

    struct ShareParticipant: Identifiable, Equatable {
        let id: String
        let name: String
        let detail: String?
        let role: CKShare.ParticipantRole
        let acceptanceStatus: CKShare.ParticipantAcceptanceStatus
        let isCurrentUser: Bool
    }

    enum ShareStatus: Equatable {
        case pending
        case accepted
        case stopped

        init(participantStatus: CKShare.ParticipantAcceptanceStatus?) {
            guard let participantStatus else {
                self = .pending
                return
            }

            switch participantStatus {
            case .accepted:
                self = .accepted
            case .removed, .revoked, .declined:
                self = .stopped
            case .pending, .unknown:
                fallthrough
            @unknown default:
                self = .pending
            }
        }
    }

    struct ShareState {
        var profileID: UUID
        var share: CKShare
        var participants: [ShareParticipant]
        var status: ShareStatus
        var isCurrentUserOwner: Bool
    }

    struct SharePresentation: Identifiable {
        let id = UUID()
        let share: CKShare
        let container: CKContainer
        let profileID: UUID
        let title: String?
    }

    private let modelContext: ModelContext
    private let container: CKContainer
    private let logger = Logger(subsystem: "com.prioritybit.babynanny", category: "share-data")

    @Published var isShowingShareData = false
    @Published private(set) var externalImportRequest: ExternalImportRequest?
    @Published private(set) var shareState: ShareState?
    @Published var activeSharePresentation: SharePresentation?
    @Published private(set) var isPerformingShareMutation = false

    init(modelContext: ModelContext,
         containerIdentifier: String? = nil) {
        self.modelContext = modelContext
        let resolvedIdentifier = containerIdentifier ?? AppDataStack.cloudKitContainerIdentifier
        self.container = CKContainer(identifier: resolvedIdentifier)
    }

    func presentShareData() {
        isShowingShareData = true
    }

    func handleIncomingFile(url: URL) {
        externalImportRequest = ExternalImportRequest(url: url)
        isShowingShareData = true
    }

    func clearExternalImportRequest(_ request: ExternalImportRequest) {
        guard externalImportRequest?.id == request.id else { return }
        externalImportRequest = nil
    }

    func dismissShareData() {
        isShowingShareData = false
    }

    func loadShareState(for profileID: UUID) {
        do {
            guard let model = try profileModel(withID: profileID) else {
                shareState = nil
                return
            }

            guard let share = try modelContext.fetchShare(for: model) else {
                shareState = nil
                return
            }

            shareState = makeShareState(from: share, profileID: profileID)
        } catch {
            logger.error("Failed to load share state: \(error.localizedDescription, privacy: .public)")
            shareState = nil
        }
    }

    func refreshActiveShareState() {
        guard let profileID = shareState?.profileID else { return }
        loadShareState(for: profileID)
    }

    func presentShareInterface(for profileID: UUID) throws {
        do {
            guard let model = try profileModel(withID: profileID) else {
                throw ShareCoordinatorError.missingProfile
            }

            let existingShare = try modelContext.fetchShare(for: model)
            let (share, shareContainer) = try modelContext.share(model, to: existingShare)
            var shareTitle: String?
            if let metadata = share[model] {
                metadata.title = resolvedShareTitle(for: model)
                shareTitle = metadata.title
            }
            share.publicPermission = .none
            shareState = makeShareState(from: share, profileID: profileID)
            activeSharePresentation = SharePresentation(share: share,
                                                        container: shareContainer,
                                                        profileID: profileID,
                                                        title: shareTitle)
        } catch {
            logger.error("Failed to present share interface: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    func handleShareSaved(_ share: CKShare, profileID: UUID) {
        shareState = makeShareState(from: share, profileID: profileID)
        activeSharePresentation = nil
    }

    func handleShareFailure(_ error: Error) {
        logger.error("Cloud sharing failed: \(error.localizedDescription, privacy: .public)")
        activeSharePresentation = nil
    }

    func handleShareStopped(for profileID: UUID) {
        if shareState?.profileID == profileID {
            shareState = nil
        }
        activeSharePresentation = nil
    }

    func stopSharingActiveShare() async throws {
        guard let state = shareState else { return }
        guard state.isCurrentUserOwner else { throw ShareCoordinatorError.requiresOwner }
        try await performShareMutation(state: state, using: container.privateCloudDatabase)
    }

    func leaveActiveShare() async throws {
        guard let state = shareState else { return }
        guard state.isCurrentUserOwner == false else { throw ShareCoordinatorError.requiresParticipant }
        try await performShareMutation(state: state, using: container.sharedCloudDatabase)
    }
}

enum ShareCoordinatorError: LocalizedError {
    case missingProfile
    case requiresOwner
    case requiresParticipant

    var errorDescription: String? {
        switch self {
        case .missingProfile:
            return L10n.ShareData.Error.missingProfile
        case .requiresOwner:
            return L10n.ShareData.Error.requiresOwner
        case .requiresParticipant:
            return L10n.ShareData.Error.requiresParticipant
        }
    }
}

private extension ShareDataCoordinator {
    func profileModel(withID id: UUID) throws -> ProfileActionStateModel? {
        let predicate = #Predicate<ProfileActionStateModel> { model in
            model.profileID == id
        }
        var descriptor = FetchDescriptor<ProfileActionStateModel>(predicate: predicate)
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    func makeShareState(from share: CKShare, profileID: UUID) -> ShareState {
        let currentParticipant = share.currentUserParticipant
        let participants = share.participants.map { participant in
            ShareParticipant(
                id: makeParticipantIdentifier(from: participant),
                name: participant.userIdentity.displayName,
                detail: participant.userIdentity.contactDetail,
                role: participant.role,
                acceptanceStatus: participant.acceptanceStatus,
                isCurrentUser: participant == currentParticipant
            )
        }

        let status = ShareStatus(participantStatus: currentParticipant?.acceptanceStatus)
        let isOwner = currentParticipant?.role == .owner
        return ShareState(profileID: profileID,
                          share: share,
                          participants: participants,
                          status: status,
                          isCurrentUserOwner: isOwner)
    }

    func resolvedShareTitle(for model: ProfileActionStateModel) -> String {
        let trimmed = (model.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return L10n.ShareData.defaultShareTitle
        }
        return String(format: L10n.ShareData.defaultShareTitleFormat, trimmed)
    }

    func makeParticipantIdentifier(from participant: CKShare.Participant) -> String {
        if let recordID = participant.userIdentity.userRecordID?.recordName {
            return recordID
        }
        if let email = participant.userIdentity.lookupInfo?.emailAddress {
            return "email:\(email)"
        }
        if let phone = participant.userIdentity.lookupInfo?.phoneNumber {
            return "phone:\(phone)"
        }
        return UUID().uuidString
    }

    func performShareMutation(state: ShareState, using database: CKDatabase) async throws {
        guard isPerformingShareMutation == false else { return }
        isPerformingShareMutation = true
        defer { isPerformingShareMutation = false }

        do {
            _ = try await database.deleteRecord(withID: state.share.recordID)
            shareState = nil
        } catch {
            logger.error("Failed to mutate share: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }
}

private extension CKUserIdentity {
    var displayName: String {
        if let nameComponents,
           let formatted = PersonNameComponentsFormatter().string(from: nameComponents),
           formatted.isEmpty == false {
            return formatted
        }

        if let email = lookupInfo?.emailAddress {
            return email
        }

        if let phone = lookupInfo?.phoneNumber {
            return phone
        }

        return L10n.ShareData.unknownParticipant
    }

    var contactDetail: String? {
        if let email = lookupInfo?.emailAddress {
            return email
        }
        if let phone = lookupInfo?.phoneNumber {
            return phone
        }
        return nil
    }
}
