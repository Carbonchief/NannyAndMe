import CloudKit
import Foundation
import os
import SwiftData

/// Maps CloudKit records to SwiftData models and vice versa.
@MainActor
final class SwiftDataBridge {
    private let dataStack: AppDataStack
    private let logger = Logger(subsystem: "com.prioritybit.nannyandme", category: "swiftdata-bridge")

    init(dataStack: AppDataStack) {
        self.dataStack = dataStack
    }

    private var context: ModelContext { dataStack.mainContext }

    func makeProfileRecord(from profile: Profile, in zoneID: CKRecordZone.ID) -> CKRecord {
        let recordID = CloudKitSchema.profileRecordID(for: profile.resolvedProfileID, zoneID: zoneID)
        let record = CKRecord(recordType: CloudKitSchema.RecordType.profile, recordID: recordID)
        record[CloudKitSchema.ProfileField.uuid] = profile.resolvedProfileID.uuidString as CKRecordValue
        record[CloudKitSchema.ProfileField.name] = profile.name as CKRecordValue?
        record[CloudKitSchema.ProfileField.lastEditedAt] = profile.updatedAt as CKRecordValue
        return record
    }

    func makeActionRecord(from action: BabyAction,
                          zoneID: CKRecordZone.ID,
                          profileRecordID: CKRecord.ID) -> CKRecord {
        let recordID = CloudKitSchema.actionRecordID(for: action.id, zoneID: zoneID)
        let record = CKRecord(recordType: CloudKitSchema.RecordType.babyAction, recordID: recordID)
        record[CloudKitSchema.BabyActionField.uuid] = action.id.uuidString as CKRecordValue
        record[CloudKitSchema.BabyActionField.type] = action.category.rawValue as CKRecordValue
        record[CloudKitSchema.BabyActionField.timestamp] = action.startDate as CKRecordValue
        record[CloudKitSchema.BabyActionField.lastEditedAt] = action.updatedAt as CKRecordValue
        record[CloudKitSchema.BabyActionField.profileReference] = CKRecord.Reference(recordID: profileRecordID, action: .none)
        return record
    }

    func apply(records: [CKRecord], scope: CKDatabase.Scope) {
        guard records.isEmpty == false else { return }
        var didMutate = false

        for record in records {
            do {
                if try apply(record: record, scope: scope) {
                    didMutate = true
                }
            } catch {
                logger.error("Failed to apply record \(record.recordID.recordName, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }

        if didMutate {
            dataStack.saveIfNeeded(on: context, reason: "cloudkit-merge-records")
        }
    }

    func delete(recordIDs: [CKRecord.ID]) {
        guard recordIDs.isEmpty == false else { return }
        var didMutate = false

        for recordID in recordIDs {
            if delete(recordID: recordID) {
                didMutate = true
            }
        }

        if didMutate {
            dataStack.saveIfNeeded(on: context, reason: "cloudkit-delete-records")
        }
    }

    func deleteProfile(withID profileID: UUID) {
        guard let model = fetchProfile(profileID: profileID) else { return }
        context.delete(model)
        dataStack.saveIfNeeded(on: context, reason: "cloudkit-delete-profile")
    }

    private func apply(record: CKRecord, scope: CKDatabase.Scope) throws -> Bool {
        switch record.recordType {
        case CloudKitSchema.RecordType.profile:
            return try mergeProfile(record: record)
        case CloudKitSchema.RecordType.babyAction:
            return try mergeAction(record: record)
        default:
            logger.debug("Ignoring unsupported record type \(record.recordType, privacy: .public)")
            return false
        }
    }

    private func mergeProfile(record: CKRecord) throws -> Bool {
        guard let uuidString = record[CloudKitSchema.ProfileField.uuid] as? String,
              let profileID = UUID(uuidString: uuidString) else {
            throw CKError(.partialFailure, userInfo: [NSLocalizedDescriptionKey: "Profile record missing UUID"])
        }

        let profile = fetchProfile(profileID: profileID) ?? Profile(profileID: profileID)
        if profile.modelContext == nil {
            context.insert(profile)
        }

        let recordEditedAt = (record[CloudKitSchema.ProfileField.lastEditedAt] as? Date) ?? record.modificationDate ?? Date()
        guard recordEditedAt >= profile.updatedAt else {
            logger.debug("Skipping profile \(profileID.uuidString, privacy: .public) merge; local newer")
            return false
        }

        let currentName = record[CloudKitSchema.ProfileField.name] as? String
        if profile.name != currentName {
            profile.name = currentName
        }
        profile.touch(recordEditedAt)
        return true
    }

    private func mergeAction(record: CKRecord) throws -> Bool {
        guard let uuidString = record[CloudKitSchema.BabyActionField.uuid] as? String,
              let actionID = UUID(uuidString: uuidString) else {
            throw CKError(.partialFailure, userInfo: [NSLocalizedDescriptionKey: "Action record missing UUID"])
        }

        guard let profileReference = record[CloudKitSchema.BabyActionField.profileReference] as? CKRecord.Reference,
              let profileID = CloudKitSchema.profileID(from: profileReference.recordID) ?? CloudKitSchema.profileID(from: profileReference.recordID.zoneID) else {
            throw CKError(.partialFailure, userInfo: [NSLocalizedDescriptionKey: "Action record missing profile reference"])
        }

        let profile = fetchProfile(profileID: profileID) ?? Profile(profileID: profileID)
        if profile.modelContext == nil {
            context.insert(profile)
        }

        let existingAction = fetchAction(actionID: actionID) ?? BabyAction(id: actionID, profile: profile)
        if existingAction.modelContext == nil {
            existingAction.profile = profile
            context.insert(existingAction)
        }

        let recordEditedAt = (record[CloudKitSchema.BabyActionField.lastEditedAt] as? Date) ?? record.modificationDate ?? Date()
        guard recordEditedAt >= existingAction.updatedAt else {
            logger.debug("Skipping action \(actionID.uuidString, privacy: .public) merge; local newer")
            return false
        }

        if let rawType = record[CloudKitSchema.BabyActionField.type] as? String,
           let category = BabyActionCategory(rawValue: rawType) {
            existingAction.category = category
        }

        if let timestamp = record[CloudKitSchema.BabyActionField.timestamp] as? Date {
            existingAction.startDate = timestamp
        }

        existingAction.updatedAt = recordEditedAt
        existingAction.profile = profile
        return true
    }

    @discardableResult
    private func delete(recordID: CKRecord.ID) -> Bool {
        if let actionID = CloudKitSchema.actionID(from: recordID), let action = fetchAction(actionID: actionID) {
            context.delete(action)
            return true
        }

        if let profileID = CloudKitSchema.profileID(from: recordID), let profile = fetchProfile(profileID: profileID) {
            context.delete(profile)
            return true
        }

        return false
    }

    private func fetchProfile(profileID: UUID) -> Profile? {
        let predicate = #Predicate<Profile> { model in
            model.profileID == profileID
        }
        var descriptor = FetchDescriptor<Profile>(predicate: predicate)
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func fetchAction(actionID: UUID) -> BabyAction? {
        let predicate = #Predicate<BabyAction> { model in
            model.id == actionID
        }
        var descriptor = FetchDescriptor<BabyAction>(predicate: predicate)
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
}
