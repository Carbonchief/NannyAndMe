import CloudKit
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
}
