import CloudKit
import Foundation

enum CloudKitProfileZone {
    static func zoneName(for profileID: UUID) -> String {
        "profile-\(profileID.uuidString.lowercased())"
    }

    static func zoneID(for profileID: UUID, ownerName: String? = CKCurrentUserDefaultName) -> CKRecordZone.ID {
        CKRecordZone.ID(zoneName: zoneName(for: profileID), ownerName: ownerName)
    }

    static func zone(for profileID: UUID) -> CKRecordZone {
        CKRecordZone(zoneID: zoneID(for: profileID))
    }

    static func profileID(from zoneID: CKRecordZone.ID) -> UUID? {
        let name = zoneID.zoneName
        guard name.hasPrefix("profile-") else { return nil }
        let uuidString = String(name.dropFirst("profile-".count))
        return UUID(uuidString: uuidString)
    }

    static func profileRecordID(for profileID: UUID, ownerName: String? = CKCurrentUserDefaultName) -> CKRecord.ID {
        CKRecord.ID(recordName: profileRecordName(for: profileID), zoneID: zoneID(for: profileID, ownerName: ownerName))
    }

    static func profileRecordName(for profileID: UUID) -> String {
        profileID.uuidString.lowercased()
    }

    static func babyActionRecordName(for actionID: UUID) -> String {
        actionID.uuidString.lowercased()
    }

    static func babyActionRecordID(for actionID: UUID, zoneID: CKRecordZone.ID) -> CKRecord.ID {
        CKRecord.ID(recordName: actionID.uuidString.lowercased(), zoneID: zoneID)
    }

    static func profileReference(for profileID: UUID, zoneID: CKRecordZone.ID) -> CKRecord.Reference {
        CKRecord.Reference(recordID: profileRecordID(for: profileID, ownerName: zoneID.ownerName), action: .none)
    }
}
