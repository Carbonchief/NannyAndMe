import CloudKit
import Foundation

struct CloudProfileSnapshot: Equatable {
    var profiles: [ChildProfile]
    var activeProfileID: UUID?
    var showRecentActivityOnHome: Bool
    var profilesWithExplicitReminderStates: Set<UUID>

    init(profiles: [ChildProfile],
         activeProfileID: UUID?,
         showRecentActivityOnHome: Bool,
         profilesWithExplicitReminderStates: Set<UUID> = []) {
        self.profiles = profiles
        self.activeProfileID = activeProfileID
        self.showRecentActivityOnHome = showRecentActivityOnHome
        self.profilesWithExplicitReminderStates = profilesWithExplicitReminderStates
    }
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
         recordType: String = "CD_Profile",
         fallbackRecordTypes: [String] = ["Profile", "ProfileActionStateModel", "ProfileState", "CD_ProfileActionStateModel"],
         dataField: String = "payload") {
        self.container = container
        self.recordType = recordType
        self.fallbackRecordTypes = fallbackRecordTypes
        self.dataField = dataField
    }

    func fetchProfileSnapshot() async throws -> CloudProfileSnapshot? {
        let database = container.privateCloudDatabase
        let recordTypes = candidateRecordTypes()
        let zones: [CKRecordZone]

        do {
            zones = try await fetchCandidateZones(in: database)
        } catch {
            if Self.isRecoverable(error) {
                throw CloudProfileImportError.recoverable(error)
            }
            throw error
        }

        for recordType in recordTypes {
            do {
                if isSwiftDataRecordType(recordType) {
                    if let snapshot = try await fetchSwiftDataSnapshot(in: database,
                                                                       recordType: recordType,
                                                                       zones: zones) {
                        return snapshot
                    }
                    continue
                }

                if let snapshot = try await fetchLegacySnapshot(in: database,
                                                                recordType: recordType,
                                                                zones: zones) {
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

    private func fetchLegacySnapshot(in database: CKDatabase,
                                     recordType: String,
                                     zones: [CKRecordZone]) async throws -> CloudProfileSnapshot? {
        var newestRecord: CKRecord?

        for zone in zones {
            do {
                let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
                let (matchResults, _) = try await database.records(
                    matching: query,
                    inZoneWith: zone.zoneID,
                    desiredKeys: desiredRecordKeys(),
                    resultsLimit: CKQueryOperation.maximumResults
                )

                for (_, result) in matchResults {
                    switch result {
                    case let .success(record):
                        guard let candidateDate = record.modificationDate ?? record.creationDate else { continue }

                        if let currentRecord = newestRecord,
                           let currentDate = currentRecord.modificationDate ?? currentRecord.creationDate,
                           currentDate >= candidateDate {
                            continue
                        }

                        newestRecord = record
                    case let .failure(error):
                        if Self.isRecoverable(error) {
                            throw CloudProfileImportError.recoverable(error)
                        }
                        throw error
                    }
                }
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

        guard let record = newestRecord,
              let data = cloudPayload(from: record) else {
            return nil
        }

        return try decodeSnapshot(from: data)
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

    private func fetchSwiftDataSnapshot(in database: CKDatabase,
                                        recordType: String,
                                        zones: [CKRecordZone]) async throws -> CloudProfileSnapshot? {
        var records: [CKRecord] = []

        for zone in zones {
            do {
                let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
                let (matchResults, _) = try await database.records(
                    matching: query,
                    inZoneWith: zone.zoneID,
                    desiredKeys: swiftDataDesiredKeys(),
                    resultsLimit: CKQueryOperation.maximumResults
                )

                for (_, result) in matchResults {
                    switch result {
                    case let .success(record):
                        records.append(record)
                    case let .failure(error):
                        if Self.isRecoverable(error) {
                            throw CloudProfileImportError.recoverable(error)
                        }
                        throw error
                    }
                }
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

        guard records.isEmpty == false else { return nil }

        let sortedRecords = records.sorted { lhs, rhs in
            let lhsDate = lhs.modificationDate ?? lhs.creationDate ?? .distantPast
            let rhsDate = rhs.modificationDate ?? rhs.creationDate ?? .distantPast
            return lhsDate > rhsDate
        }

        var profiles: [ChildProfile] = []
        var seenIdentifiers = Set<UUID>()

        for record in sortedRecords {
            guard let profile = Self.decodeSwiftDataProfile(from: record) else { continue }
            guard seenIdentifiers.insert(profile.id).inserted else { continue }
            profiles.append(profile)
        }

        guard profiles.isEmpty == false else { return nil }

        return CloudProfileSnapshot(
            profiles: profiles,
            activeProfileID: profiles.first?.id,
            showRecentActivityOnHome: true,
            profilesWithExplicitReminderStates: Set<UUID>()
        )
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

    private func swiftDataDesiredKeys() -> [String]? {
        let keys = swiftDataFieldCandidates()
        return keys.isEmpty ? nil : keys
    }

    private func swiftDataFieldCandidates() -> [String] {
        [
            "CD_profileID",
            "CD_name",
            "CD_birthDate",
            "CD_imageData",
            "CD_entityName",
            "profileID",
            "name",
            "birthDate",
            "imageData"
        ]
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

        let profiles = payload.profiles.map { $0.profile }
        let explicitReminderIDs = Set(payload.profiles.compactMap { payload in
            payload.didDecodeRemindersEnabled ? payload.profile.id : nil
        })

        return CloudProfileSnapshot(
            profiles: profiles,
            activeProfileID: payload.activeProfileID,
            showRecentActivityOnHome: payload.showRecentActivityOnHome ?? true,
            profilesWithExplicitReminderStates: explicitReminderIDs
        )
    }

    private func isSwiftDataRecordType(_ recordType: String) -> Bool {
        let sanitized = recordType.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidates = ["CD_Profile", "Profile", "CD_ProfileActionStateModel"]
        return candidates.contains { candidate in
            sanitized.caseInsensitiveCompare(candidate) == .orderedSame
        }
    }

    private func fetchCandidateZones(in database: CKDatabase) async throws -> [CKRecordZone] {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[CKRecordZone], Error>) in
            database.fetchAllRecordZones { zones, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                var records = zones ?? []
                let defaultZone = CKRecordZone.default()
                if records.contains(where: { $0.zoneID == defaultZone.zoneID }) == false {
                    records.append(defaultZone)
                }
                continuation.resume(returning: records)
            }
        }
    }

    static func decodeSwiftDataProfile(from record: CKRecord) -> ChildProfile? {
        guard let identifier = swiftDataIdentifier(from: record) else { return nil }
        guard let birthDate = swiftDataBirthDate(from: record) else { return nil }

        let name = swiftDataName(from: record)
        let imageData = swiftDataImageData(from: record)

        return ChildProfile(id: identifier, name: name, birthDate: birthDate, imageData: imageData)
    }

    private static func swiftDataIdentifier(from record: CKRecord) -> UUID? {
        for key in ["CD_profileID", "profileID", "id", "identifier"] {
            if let uuidValue = record[key] as? UUID {
                return uuidValue
            }

            if let stringValue = record[key] as? String {
                let trimmed = stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if let uuid = UUID(uuidString: trimmed) {
                    return uuid
                }
            }
        }

        if let uuid = UUID(uuidString: record.recordID.recordName) {
            return uuid
        }

        return nil
    }

    private static func swiftDataBirthDate(from record: CKRecord) -> Date? {
        for key in ["CD_birthDate", "birthDate"] {
            if let date = record[key] as? Date {
                return date
            }

            if let stringValue = record[key] as? String {
                let trimmed = stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty == false {
                    let iso8601 = ISO8601DateFormatter()
                    if let parsed = iso8601.date(from: trimmed) {
                        return parsed
                    }
                }
            }
        }

        return nil
    }

    private static func swiftDataName(from record: CKRecord) -> String {
        for key in ["CD_name", "name"] {
            if let stringValue = record[key] as? String {
                let trimmed = stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty == false {
                    return trimmed
                }
            }
        }

        return ""
    }

    private static func swiftDataImageData(from record: CKRecord) -> Data? {
        for key in ["CD_imageData", "imageData"] {
            if let data = record[key] as? Data {
                return data
            }

            if let asset = record[key] as? CKAsset,
               let url = asset.fileURL,
               let data = try? Data(contentsOf: url) {
                return data
            }

            if let stringValue = record[key] as? String,
               let data = Data(base64Encoded: stringValue) ?? stringValue.data(using: .utf8) {
                return data
            }
        }

        return nil
    }
}

private struct ProfileStatePayload: Decodable {
    var profiles: [ChildProfilePayload]
    var activeProfileID: UUID?
    var showRecentActivityOnHome: Bool?
}

private struct ChildProfilePayload: Decodable {
    var profile: ChildProfile
    var didDecodeRemindersEnabled: Bool

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        didDecodeRemindersEnabled = container.contains(.remindersEnabled)
        profile = try ChildProfile(from: decoder)
    }

    private enum CodingKeys: String, CodingKey {
        case remindersEnabled
    }
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
