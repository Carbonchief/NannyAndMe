import CloudKit
import Foundation

struct CloudProfileSnapshot: Equatable {
    var profiles: [ChildProfile]
    var activeProfileID: UUID?
    var showRecentActivityOnHome: Bool
}

protocol ProfileCloudImporting {
    func fetchProfileSnapshot() async throws -> CloudProfileSnapshot?
}

enum CloudProfileImportError: Error {
    case recoverable(Error)
}

struct CloudKitProfileImporter: ProfileCloudImporting {
    private let container: CKContainer
    private let recordType: String
    private let dataField: String

    init(container: CKContainer = CKContainer(identifier: "iCloud.com.prioritybit.babynanny"),
         recordType: String = "ProfileState",
         dataField: String = "payload") {
        self.container = container
        self.recordType = recordType
        self.dataField = dataField
    }

    func fetchProfileSnapshot() async throws -> CloudProfileSnapshot? {
        let database = container.privateCloudDatabase
        let predicate = NSPredicate(value: true)
        let query = CKQuery(recordType: recordType, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "modificationDate", ascending: false)]

        do {
            let (matchResults, _) = try await database.records(
                matching: query,
                desiredKeys: [dataField],
                resultsLimit: 1
            )

            guard let (_, result) = matchResults.first else {
                return nil
            }

            switch result {
            case let .success(record):
                guard let data = cloudPayload(from: record) else {
                    return nil
                }
                return try decodeSnapshot(from: data)
            case let .failure(error):
                if Self.isRecoverable(error) {
                    throw CloudProfileImportError.recoverable(error)
                }
                throw error
            }
        } catch {
            if Self.isMissingRecordType(error) {
                return nil
            }
            if Self.isRecoverable(error) {
                throw CloudProfileImportError.recoverable(error)
            }
            throw error
        }
    }

    static func isRecoverable(_ error: Error) -> Bool {
        guard let ckError = error as? CKError else { return false }

        if recoverableErrorCodes.contains(ckError.code) {
            return true
        }

        if ckError.code == .partialFailure {
            let partialErrors = ckError.partialErrorsByItemID ?? [:]
            return partialErrors.values.allSatisfy { isRecoverable($0) }
        }

        return false
    }

    private static func isMissingRecordType(_ error: Error) -> Bool {
        guard let ckError = error as? CKError else { return false }

        if ckError.code == .unknownItem {
            return ckError.containsMissingRecordTypeMessage
        }

        if ckError.code == .partialFailure {
            let partialErrors = ckError.partialErrorsByItemID ?? [:]
            return partialErrors.values.contains { isMissingRecordType($0) }
        }

        return false
    }

    private static let recoverableErrorCodes: Set<CKError.Code> = [
        .unknownItem,
        .zoneNotFound,
        .userDeletedZone
    ]

    private func cloudPayload(from record: CKRecord) -> Data? {
        if let data = record[dataField] as? Data {
            return data
        }

        if let stringValue = record[dataField] as? String {
            return stringValue.data(using: .utf8)
        }

        return nil
    }

    private func decodeSnapshot(from data: Data) throws -> CloudProfileSnapshot? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(ProfileStatePayload.self, from: data)

        guard payload.profiles.isEmpty == false else {
            return nil
        }

        return CloudProfileSnapshot(
            profiles: payload.profiles,
            activeProfileID: payload.activeProfileID,
            showRecentActivityOnHome: payload.showRecentActivityOnHome ?? true
        )
    }
}

private struct ProfileStatePayload: Decodable {
    var profiles: [ChildProfile]
    var activeProfileID: UUID?
    var showRecentActivityOnHome: Bool?
}

private extension CKError {
    var containsMissingRecordTypeMessage: Bool {
        if localizedDescription.localizedCaseInsensitiveContains("did not find record type") {
            return true
        }

        if let failureReason = userInfo[NSLocalizedFailureReasonErrorKey] as? String,
           failureReason.localizedCaseInsensitiveContains("record type") {
            return true
        }

        if let debugDescription = userInfo[NSDebugDescriptionErrorKey] as? String,
           debugDescription.localizedCaseInsensitiveContains("record type") {
            return true
        }

        return false
    }
}
