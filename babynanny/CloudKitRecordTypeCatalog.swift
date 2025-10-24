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

    static func matchesProfile(_ recordType: String) -> Bool {
        matches(recordType, in: profileRecordTypes)
    }

    static func matchesBabyAction(_ recordType: String) -> Bool {
        matches(recordType, in: babyActionRecordTypes)
    }

    private static func matches(_ recordType: String, in candidates: [String]) -> Bool {
        candidates.contains { candidate in
            candidate.caseInsensitiveCompare(recordType) == .orderedSame
        }
    }
}
