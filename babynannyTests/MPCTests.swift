import MultipeerConnectivity
import XCTest
@testable import babynanny

final class MPCTests: XCTestCase {
    func testEnvelopeRoundTrip() throws {
        let payload = MPCHelloMessage(displayName: "Tester", supportsFileTransfer: true)
        let envelope = try MPCEnvelope(type: .hello, payload: payload)
        let data = try JSONEncoder().encode(envelope)
        let decoded = try JSONDecoder().decode(MPCEnvelope.self, from: data)
        let roundTrip = try decoded.decodePayload(as: MPCHelloMessage.self)
        XCTAssertEqual(roundTrip.displayName, payload.displayName)
        XCTAssertEqual(roundTrip.supportsFileTransfer, payload.supportsFileTransfer)
        XCTAssertEqual(decoded.type, .hello)
        XCTAssertEqual(decoded.version, MPCEnvelope.currentVersion)
    }

    func testEnvelopeVersionMismatchThrows() throws {
        let payload = MPCHelloMessage(displayName: "Future", supportsFileTransfer: true)
        var envelope = try MPCEnvelope(type: .hello, payload: payload)
        envelope = MPCEnvelope(version: MPCEnvelope.currentVersion + 1,
                               type: envelope.type,
                               payload: envelope.payload,
                               sentAt: envelope.sentAt)
        XCTAssertThrowsError(try envelope.decodePayload(as: MPCHelloMessage.self)) { error in
            guard case let MPCError.unsupportedEnvelopeVersion(_, received) = error as? MPCError else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(received, MPCEnvelope.currentVersion + 1)
        }
    }

    func testTransferProgressUpdateCalculatesEstimates() {
        let peer = MCPeerID(displayName: "Peer")
        let progress = MPCTransferProgress(peerID: peer,
                                           kind: .resource(name: "file.json"),
                                           progress: 0.5,
                                           bytesTransferred: 512,
                                           totalBytes: 1024,
                                           startedAt: Date().addingTimeInterval(-2),
                                           updatedAt: Date())
        let updated = progress.updating(progress: 0.75,
                                        bytesTransferred: 768,
                                        totalBytes: 1024,
                                        updatedAt: Date())
        XCTAssertGreaterThan(updated.bytesTransferred, progress.bytesTransferred)
        XCTAssertEqual(updated.totalBytes, progress.totalBytes)
        XCTAssertEqual(updated.kind, .resource(name: "file.json"))
        XCTAssertNotNil(updated.estimatedRemainingTime)
    }
}
