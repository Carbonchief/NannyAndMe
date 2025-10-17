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
    private let fallbackRecordTypes: [String]
    private let dataField: String

    init(container: CKContainer = CKContainer(identifier: "iCloud.com.prioritybit.babynanny"),
         recordType: String = "CD_ProfileActionStateModel",
         fallbackRecordTypes: [String] = ["ProfileActionStateModel", "ProfileState"],
         dataField: String = "payload") {
        self.container = container
        self.recordType = recordType
        self.fallbackRecordTypes = fallbackRecordTypes
        self.dataField = dataField
    }

    func fetchProfileSnapshot() async throws -> CloudProfileSnapshot? {
        let database = container.privateCloudDatabase
        let recordTypes = candidateRecordTypes()

        for recordType in recordTypes {
            do {
                if let snapshot = try await fetchSnapshot(in: database, recordType: recordType) {
                    return snapshot
                }
            } catch let error as CloudProfileImportError {
                throw error
            } catch {
                if Self.isMissingRecordType(error) {
                    continue
                }
                if Self.isRecoverable(error) {
                    throw CloudProfileImportError.recoverable(error)
                }
                throw error
            }
        }

        return nil
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

    private func fetchSnapshot(in database: CKDatabase, recordType: String) async throws -> CloudProfileSnapshot? {
        let predicate = NSPredicate(value: true)
        let query = CKQuery(recordType: recordType, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "modificationDate", ascending: false)]

        let (matchResults, _) = try await database.records(
            matching: query,
            desiredKeys: desiredRecordKeys(),
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
    }

    private func cloudPayload(from record: CKRecord) -> Data? {
        for key in dataFieldCandidates() {
            if let data = record[key] as? Data {
                return data
            }

            if let asset = record[key] as? CKAsset,
               let fileURL = asset.fileURL,
               let data = try? Data(contentsOf: fileURL) {
                return data
            }

            if let stringValue = record[key] as? String,
               let data = stringValue.data(using: .utf8) {
                return data
            }
        }

        return nil
    }

    private func desiredRecordKeys() -> [String]? {
        let keys = dataFieldCandidates()
        return keys.isEmpty ? nil : keys
    }

    private func dataFieldCandidates() -> [String] {
        var candidates: [String] = []
        let preferred = dataField.trimmingCharacters(in: .whitespacesAndNewlines)
        if preferred.isEmpty == false {
            candidates.append(preferred)
        }

        let fallbacks = ["payload", "data", "stateData", "profileState", "modelData"]
        for fallback in fallbacks where fallback.caseInsensitiveCompare(preferred) != .orderedSame {
            if candidates.contains(where: { $0.caseInsensitiveCompare(fallback) == .orderedSame }) == false {
                candidates.append(fallback)
            }
        }

        return candidates
    }

    private func candidateRecordTypes() -> [String] {
        var types: [String] = []
        let preferred = recordType.trimmingCharacters(in: .whitespacesAndNewlines)
        if preferred.isEmpty == false {
            types.append(preferred)
        }

        for fallback in fallbackRecordTypes {
            let sanitized = fallback.trimmingCharacters(in: .whitespacesAndNewlines)
            guard sanitized.isEmpty == false else { continue }
            guard types.contains(where: { $0.caseInsensitiveCompare(sanitized) == .orderedSame }) == false else { continue }
            types.append(sanitized)
        }

        return types
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
