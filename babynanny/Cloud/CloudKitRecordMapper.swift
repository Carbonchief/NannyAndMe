import CloudKit
import Foundation
import SwiftData

enum CloudKitRecordMapper {
    static let profileRecordType = "CD_Profile"
    static let babyActionRecordType = "CD_BabyAction"

    static func makeProfileRecord(from model: ProfileActionStateModel,
                                  zoneID: CKRecordZone.ID,
                                  existing: CKRecord? = nil) -> CKRecord {
        let record = existing ?? CKRecord(recordType: profileRecordType,
                                          recordID: CloudKitProfileZone.profileRecordID(for: model.profileID,
                                                                                        ownerName: zoneID.ownerName))
        record["id"] = model.profileID.uuidString as CKRecordValue
        record["displayName"] = model.name as CKRecordValue?
        record["createdAt"] = model.createdAt as CKRecordValue
        record["modifiedAt"] = model.updatedAt as CKRecordValue
        if let birthDate = model.birthDate {
            record["birthDate"] = birthDate as CKRecordValue
        } else {
            record["birthDate"] = nil
        }
        if let imageData = model.imageData {
            record["imageData"] = imageData as CKRecordValue
        } else {
            record["imageData"] = nil
        }
        return record
    }

    static func makeBabyActionRecord(from model: BabyActionModel,
                                     profileID: UUID,
                                     zoneID: CKRecordZone.ID,
                                     existing: CKRecord? = nil) -> CKRecord {
        let record = existing ?? CKRecord(recordType: babyActionRecordType,
                                          recordID: CloudKitProfileZone.babyActionRecordID(for: model.id, zoneID: zoneID))
        record["id"] = model.id.uuidString as CKRecordValue
        record["profileID"] = profileID.uuidString as CKRecordValue
        record["type"] = model.category.rawValue as CKRecordValue
        record["timestamp"] = model.startDate as CKRecordValue
        record["modifiedAt"] = model.updatedAt as CKRecordValue
        if let endDate = model.endDate {
            record["endDate"] = endDate as CKRecordValue
        } else {
            record["endDate"] = nil
        }
        if let diaper = model.diaperType?.rawValue {
            record["diaperType"] = diaper as CKRecordValue
        } else {
            record["diaperType"] = nil
        }
        if let feeding = model.feedingType?.rawValue {
            record["feedingType"] = feeding as CKRecordValue
        } else {
            record["feedingType"] = nil
        }
        if let bottle = model.bottleType?.rawValue {
            record["bottleType"] = bottle as CKRecordValue
        } else {
            record["bottleType"] = nil
        }
        if let bottleVolume = model.bottleVolume {
            record["bottleVolume"] = NSNumber(value: bottleVolume)
        } else {
            record["bottleVolume"] = nil
        }
        if let latitude = model.latitude {
            record["latitude"] = NSNumber(value: latitude)
        } else {
            record["latitude"] = nil
        }
        if let longitude = model.longitude {
            record["longitude"] = NSNumber(value: longitude)
        } else {
            record["longitude"] = nil
        }
        if let placename = model.placename {
            record["notes"] = placename as CKRecordValue
        } else {
            record["notes"] = nil
        }
        record["profileRef"] = CloudKitProfileZone.profileReference(for: profileID, zoneID: zoneID)
        return record
    }
}
