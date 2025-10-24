import CloudKit
import Foundation

enum CloudKitRecordTypeCatalog {
    static let profileRecordTypes: [String] = [
        "CD_Profile",
        "Profile",
        "CD_ProfileActionStateModel"
    ]

    static let babyActionRecordTypes: [String] = [
        "CD_BabyAction",
        "BabyAction",
        "CD_BabyActionModel"
    ]

    static let profileIdentifierFields: [String] = [
        "profileID",
        "CD_profileID"
    ]

    static func matchesProfile(_ recordType: String) -> Bool {
        matches(recordType, in: profileRecordTypes)
    }

    static func matchesBabyAction(_ recordType: String) -> Bool {
        matches(recordType, in: babyActionRecordTypes)
    }

    static func profileIdentifierValue(from record: CKRecord) -> String? {
        for field in profileIdentifierFields {
            if let value = record[field] as? String, value.isEmpty == false {
                return value
            }
        }
        return nil
    }

    static func profileIdentifier(from record: CKRecord) -> UUID? {
        if let stringValue = profileIdentifierValue(from: record),
           let uuid = UUID(uuidString: stringValue) {
            return uuid
        }
        for field in profileIdentifierFields {
            if let uuid = record[field] as? UUID {
                return uuid
            }
        }
        return nil
    }

    private static func matches(_ recordType: String, in candidates: [String]) -> Bool {
        candidates.contains { candidate in
            candidate.caseInsensitiveCompare(recordType) == .orderedSame
        }
    }
}
