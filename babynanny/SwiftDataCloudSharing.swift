import CloudKit
import Foundation
import SwiftData

enum SwiftDataCloudSharing {
    enum ShareError: LocalizedError {
        case unavailable

        var errorDescription: String? {
            L10n.ShareData.CloudKit.unsupportedAlertMessage
        }

        var failureReason: String? {
            L10n.ShareData.CloudKit.unsupportedAlertTitle
        }
    }

    @MainActor
    static func fetchShare<T: PersistentModel>(for model: T,
                                               in context: ModelContext) throws -> CKShare? {
#if _hasSymbol(ModelContext.fetchShare(for:))
        return try context.fetchShare(for: model)
#else
        throw ShareError.unavailable
#endif
    }

    @MainActor
    static func stopSharing<T: PersistentModel>(_ model: T,
                                                in context: ModelContext) throws {
#if _hasSymbol(ModelContext.stopSharing(_:))
        try context.stopSharing(model)
#else
        throw ShareError.unavailable
#endif
    }

    @MainActor
    @discardableResult
    static func share<T: PersistentModel>(_ model: T,
                                          in context: ModelContext,
                                          to participants: [CKShare.Participant]) throws -> CKShare {
#if _hasSymbol(ModelContext.share(_:to:))
        return try context.share(model, to: participants)
#else
        throw ShareError.unavailable
#endif
    }
}
