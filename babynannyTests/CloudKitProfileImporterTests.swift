import CloudKit
import Foundation
import Testing
@testable import babynanny

@Suite("CloudKit Profile Importer")
struct CloudKitProfileImporterTests {
    @Test
    func recoverableUnknownItemErrorReturnsTrue() {
        let error = CKError(.unknownItem)
        #expect(CloudKitProfileImporter.isRecoverable(error))
    }

    @Test
    func partialFailureWithOnlyRecoverableErrorsReturnsTrue() {
        let childError = CKError(.unknownItem)
        let recordID = CKRecord.ID(recordName: UUID().uuidString)
        let partialError = CKError(.partialFailure, userInfo: [
            CKPartialErrorsByItemIDKey: [recordID: childError]
        ])

        #expect(CloudKitProfileImporter.isRecoverable(partialError))
    }

    @Test
    func nonRecoverableErrorReturnsFalse() {
        let error = CKError(.networkFailure)
        #expect(CloudKitProfileImporter.isRecoverable(error) == false)
    }

    @Test
    func decodesSwiftDataProfileRecord() {
        let record = CKRecord(recordType: "Profile")
        let identifier = UUID()
        let birthDate = Date(timeIntervalSince1970: 1_694_000_000)
        let imageData = Data([0xCA, 0xFE, 0xBA, 0xBE])

        record["CD_profileID"] = identifier.uuidString as CKRecordValue
        record["CD_name"] = "Luna" as CKRecordValue
        record["CD_birthDate"] = birthDate as CKRecordValue
        record["CD_imageData"] = imageData as CKRecordValue

        let profile = CloudKitProfileImporter.decodeSwiftDataProfile(from: record)

        #expect(profile?.id == identifier)
        #expect(profile?.name == "Luna")
        #expect(profile?.birthDate == birthDate)
        #expect(profile?.imageData == imageData)
    }

    @Test
    func decodeSwiftDataProfileRequiresBirthDate() {
        let record = CKRecord(recordType: "Profile")
        record["CD_profileID"] = UUID().uuidString as CKRecordValue
        record["CD_name"] = "Rowan" as CKRecordValue

        let profile = CloudKitProfileImporter.decodeSwiftDataProfile(from: record)

        #expect(profile == nil)
    }

    @Test
    func defaultImporterTargetsCDProfileRecords() {
        let importer = CloudKitProfileImporter()
        let mirror = Mirror(reflecting: importer)

        let recordType = mirror.descendant("recordType") as? String
        let fallbackRecordTypes = mirror.descendant("fallbackRecordTypes") as? [String]

        #expect(recordType == "CD_Profile")
        #expect(fallbackRecordTypes?.contains(where: { $0.caseInsensitiveCompare("Profile") == .orderedSame }) == true)
    }
}
