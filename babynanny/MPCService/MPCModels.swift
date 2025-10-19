import Foundation
import MultipeerConnectivity

/// Versioned message envelope used for all peer-to-peer payloads.
struct MPCEnvelope: Codable, Equatable {
    static let currentVersion = 1

    let version: Int
    let type: MPCMessageType
    let payload: Data
    let sentAt: Date

    init(version: Int = MPCEnvelope.currentVersion,
         type: MPCMessageType,
         payload: Data,
         sentAt: Date = Date()) {
        self.version = version
        self.type = type
        self.payload = payload
        self.sentAt = sentAt
    }

    init<Payload: Encodable>(type: MPCMessageType, payload: Payload, encoder: JSONEncoder = MPCEnvelope.makeEncoder()) throws {
        do {
            let encoded = try encoder.encode(payload)
            self.init(version: MPCEnvelope.currentVersion, type: type, payload: encoded)
        } catch {
            throw MPCError.encodingFailed
        }
    }

    func decodePayload<Payload: Decodable>(as type: Payload.Type, decoder: JSONDecoder = MPCEnvelope.makeDecoder()) throws -> Payload {
        guard version <= MPCEnvelope.currentVersion else {
            throw MPCError.unsupportedEnvelopeVersion(current: MPCEnvelope.currentVersion, received: version)
        }

        do {
            return try decoder.decode(Payload.self, from: payload)
        } catch {
            throw MPCError.decodingFailed
        }
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

/// Supported message types for the MPC channel.
enum MPCMessageType: String, Codable {
    case hello
    case capabilities
    case profileSnapshot
    case actionsDelta
    case ack
    case error
}

/// Lightweight metadata describing a discovered peer.
struct MPCPeer: Identifiable, Hashable {
    let peerID: MCPeerID
    let discoveryInfo: [String: String]
    let lastSeen: Date

    var id: String { peerID.displayName }

    var displayName: String {
        if let encoded = discoveryInfo["prettyName"],
           let data = Data(base64Encoded: encoded),
           let decoded = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           decoded.isEmpty == false {
            return decoded
        }
        return discoveryInfo["shortName"] ?? peerID.displayName
    }

    var appVersion: String? { discoveryInfo["appVersion"] }

    func updating(lastSeen: Date) -> MPCPeer {
        MPCPeer(peerID: peerID, discoveryInfo: discoveryInfo, lastSeen: lastSeen)
    }
}

/// Message exchanged during the handshake.
struct MPCHelloMessage: Codable, Equatable {
    let displayName: String
    let supportsFileTransfer: Bool
}

/// Message describing the sender's capabilities.
struct MPCCapabilitiesMessage: Codable, Equatable {
    let supportedEnvelopeVersion: Int
    let maximumResourceSize: Int
}

/// Message carrying a snapshot of a profile and its actions.
struct ProfileExportV1: Codable {
    let exportedAt: Date
    let profile: ChildProfile
    let actions: ProfileActionState

    init(exportedAt: Date = Date(), profile: ChildProfile, actions: ProfileActionState) {
        self.exportedAt = exportedAt
        self.profile = profile
        self.actions = actions
    }
}

/// Message carrying incremental changes.
struct ActionsDeltaMessage: Codable, Equatable {
    let profileID: UUID
    let updatedActions: [BabyActionSnapshot]
    let removedActionIDs: [UUID]
}

/// Message acknowledging receipt of a payload.
struct MPCAcknowledgement: Codable, Equatable {
    let identifier: UUID
    let receivedAt: Date
}

/// Message representing a recoverable error.
struct MPCErrorMessage: Codable, Equatable {
    let code: String
    let message: String
}

/// Identifies a transfer currently in flight.
struct MPCTransferProgress: Identifiable, Equatable {
    enum Kind: Equatable {
        case message(type: MPCMessageType)
        case resource(name: String)
    }

    let id: UUID
    let peerID: MCPeerID
    let kind: Kind
    let progress: Double
    let bytesTransferred: Int64
    let totalBytes: Int64
    let startedAt: Date
    let updatedAt: Date
    let estimatedRemainingTime: TimeInterval?

    init(id: UUID = UUID(),
         peerID: MCPeerID,
         kind: Kind,
         progress: Double,
         bytesTransferred: Int64,
         totalBytes: Int64,
         startedAt: Date = Date(),
         updatedAt: Date = Date(),
         estimatedRemainingTime: TimeInterval? = nil) {
        self.id = id
        self.peerID = peerID
        self.kind = kind
        self.progress = progress
        self.bytesTransferred = bytesTransferred
        self.totalBytes = totalBytes
        self.startedAt = startedAt
        self.updatedAt = updatedAt
        self.estimatedRemainingTime = estimatedRemainingTime
    }

    func updating(progress: Double, bytesTransferred: Int64, totalBytes: Int64, updatedAt: Date) -> MPCTransferProgress {
        let remainingBytes = Double(totalBytes - bytesTransferred)
        let elapsed = updatedAt.timeIntervalSince(startedAt)
        var estimatedTime: TimeInterval?
        if elapsed > 0 {
            let throughput = Double(bytesTransferred) / elapsed
            if throughput > 0 {
                estimatedTime = remainingBytes / throughput
            }
        }

        return MPCTransferProgress(id: id,
                                   peerID: peerID,
                                   kind: kind,
                                   progress: progress,
                                   bytesTransferred: bytesTransferred,
                                   totalBytes: totalBytes,
                                   startedAt: startedAt,
                                   updatedAt: updatedAt,
                                   estimatedRemainingTime: estimatedTime)
    }
}
