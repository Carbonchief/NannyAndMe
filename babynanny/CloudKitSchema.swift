import CloudKit
import Foundation

/// Namespace describing the CloudKit schema for Nanny and Me sharing records.
enum CloudKitSchema {
    enum RecordType {
        static let profile = "Profile"
        static let babyAction = "BabyAction"
    }

    enum ProfileField {
        static let uuid = "uuid"
        static let name = "name"
        static let lastEditedAt = "lastEditedAt"
    }

    enum BabyActionField {
        static let uuid = "uuid"
        static let type = "type"
        static let timestamp = "timestamp"
        static let profileReference = "profileRef"
        static let lastEditedAt = "lastEditedAt"
    }

    private enum RecordPrefix {
        static let profile = "P_"
        static let babyAction = "A_"
        static let zone = "Z_"
    }

    static func zoneID(for profileID: UUID, ownerName: String = CKCurrentUserDefaultName) -> CKRecordZone.ID {
        let zoneName = RecordPrefix.zone + profileID.uuidString
        return CKRecordZone.ID(zoneName: zoneName, ownerName: ownerName)
    }

    static func profileRecordID(for profileID: UUID, zoneID: CKRecordZone.ID) -> CKRecord.ID {
        CKRecord.ID(recordName: RecordPrefix.profile + profileID.uuidString, zoneID: zoneID)
    }

    static func actionRecordID(for actionID: UUID, zoneID: CKRecordZone.ID) -> CKRecord.ID {
        CKRecord.ID(recordName: RecordPrefix.babyAction + actionID.uuidString, zoneID: zoneID)
    }

    static func profileID(from zoneID: CKRecordZone.ID) -> UUID? {
        guard zoneID.zoneName.hasPrefix(RecordPrefix.zone) else { return nil }
        let identifier = zoneID.zoneName.dropFirst(RecordPrefix.zone.count)
        return UUID(uuidString: String(identifier))
    }

    static func profileID(from recordID: CKRecord.ID) -> UUID? {
        guard recordID.recordName.hasPrefix(RecordPrefix.profile) else { return nil }
        let identifier = recordID.recordName.dropFirst(RecordPrefix.profile.count)
        return UUID(uuidString: String(identifier))
    }

    static func actionID(from recordID: CKRecord.ID) -> UUID? {
        guard recordID.recordName.hasPrefix(RecordPrefix.babyAction) else { return nil }
        let identifier = recordID.recordName.dropFirst(RecordPrefix.babyAction.count)
        return UUID(uuidString: String(identifier))
    }

    static func isProfileZone(_ zoneID: CKRecordZone.ID) -> Bool {
        zoneID.zoneName.hasPrefix(RecordPrefix.zone)
    }
}
