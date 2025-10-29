import CloudKit
@testable import babynanny
import XCTest

@MainActor
final class SwiftDataBridgeTests: XCTestCase {
    private var dataStack: AppDataStack!
    private var bridge: SwiftDataBridge!

    override func setUp() async throws {
        try await super.setUp()
        dataStack = AppDataStack(modelContainer: AppDataStack.makeModelContainer(inMemory: true))
        bridge = SwiftDataBridge(dataStack: dataStack)
    }

    override func tearDown() async throws {
        bridge = nil
        dataStack = nil
        try await super.tearDown()
    }

    func testMakeProfileRecordContainsFields() async throws {
        let profile = Profile(profileID: UUID(), name: "Taylor")
        dataStack.mainContext.insert(profile)
        profile.touch(Date(timeIntervalSince1970: 1_000))
        let zoneID = CloudKitSchema.zoneID(for: profile.resolvedProfileID)

        let record = await bridge.makeProfileRecord(from: profile, in: zoneID)

        XCTAssertEqual(record[CloudKitSchema.ProfileField.uuid] as? String, profile.resolvedProfileID.uuidString)
        XCTAssertEqual(record[CloudKitSchema.ProfileField.name] as? String, profile.name)
        XCTAssertEqual(record[CloudKitSchema.ProfileField.lastEditedAt] as? Date, profile.updatedAt)
    }

    func testMergeProfileAppliesNewerRecord() async throws {
        let profileID = UUID()
        let profile = Profile(profileID: profileID, name: "Original")
        profile.touch(Date(timeIntervalSince1970: 1_000))
        dataStack.mainContext.insert(profile)

        let zoneID = CloudKitSchema.zoneID(for: profileID)
        let recordID = CloudKitSchema.profileRecordID(for: profileID, zoneID: zoneID)
        let record = CKRecord(recordType: CloudKitSchema.RecordType.profile, recordID: recordID)
        record[CloudKitSchema.ProfileField.uuid] = profileID.uuidString as CKRecordValue
        record[CloudKitSchema.ProfileField.name] = "Updated" as CKRecordValue
        record[CloudKitSchema.ProfileField.lastEditedAt] = Date(timeIntervalSince1970: 2_000) as CKRecordValue

        bridge.apply(records: [record], scope: .private)

        XCTAssertEqual(profile.name, "Updated")
        XCTAssertEqual(profile.updatedAt, Date(timeIntervalSince1970: 2_000))
    }

    func testMergeActionSkipsOlderRecord() async throws {
        let profile = Profile(profileID: UUID(), name: "Casey")
        dataStack.mainContext.insert(profile)
        let action = BabyAction(id: UUID(), category: .sleep, startDate: Date(), updatedAt: Date(timeIntervalSince1970: 3_000), profile: profile)
        dataStack.mainContext.insert(action)

        let zoneID = CloudKitSchema.zoneID(for: profile.resolvedProfileID)
        let recordID = CloudKitSchema.actionRecordID(for: action.id, zoneID: zoneID)
        let record = CKRecord(recordType: CloudKitSchema.RecordType.babyAction, recordID: recordID)
        record[CloudKitSchema.BabyActionField.uuid] = action.id.uuidString as CKRecordValue
        record[CloudKitSchema.BabyActionField.type] = BabyActionCategory.diaper.rawValue as CKRecordValue
        record[CloudKitSchema.BabyActionField.timestamp] = Date() as CKRecordValue
        record[CloudKitSchema.BabyActionField.lastEditedAt] = Date(timeIntervalSince1970: 2_000) as CKRecordValue
        record[CloudKitSchema.BabyActionField.profileReference] = CKRecord.Reference(recordID: CloudKitSchema.profileRecordID(for: profile.resolvedProfileID, zoneID: zoneID), action: .none)

        bridge.apply(records: [record], scope: .private)

        XCTAssertEqual(action.category, .sleep)
        XCTAssertEqual(action.updatedAt, Date(timeIntervalSince1970: 3_000))
    }
}
