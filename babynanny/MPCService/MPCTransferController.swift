import Foundation
import MultipeerConnectivity

/// Handles encoding, decoding, and progress tracking for MPC transfers.
@MainActor
final class MPCTransferController {
    private struct ResourceKey: Hashable {
        let peerDisplayName: String
        let resourceName: String
    }

    private let sessionController: MPCSessionController
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private var progressByID: [UUID: MPCTransferProgress] = [:]
    private var observers: [UUID: NSKeyValueObservation] = [:]
    private var progressKeyMap: [ResourceKey: UUID] = [:]
    private var progressHandles: [UUID: Progress] = [:]

    var onHelloMessage: ((MPCHelloMessage, MCPeerID) -> Void)?
    var onCapabilitiesMessage: ((MPCCapabilitiesMessage, MCPeerID) -> Void)?
    var onProfileExport: ((ProfileExportV1, MCPeerID) -> Void)?
    var onActionsDelta: ((ActionsDeltaMessage, MCPeerID) -> Void)?
    var onAcknowledgement: ((MPCAcknowledgement, MCPeerID) -> Void)?
    var onErrorMessage: ((MPCErrorMessage, MCPeerID) -> Void)?
    var onIncompatibleEnvelope: ((MPCEnvelope, MPCError, MCPeerID) -> Void)?
    var onTransferProgress: (([MPCTransferProgress]) -> Void)?
    var onResourceReceived: ((URL, String, MCPeerID) -> Void)?

    init(sessionController: MPCSessionController) {
        self.sessionController = sessionController
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder

        sessionController.onEnvelopeReceived = { [weak self] envelope, peer in
            guard let self else { return }
            self.handle(envelope: envelope, from: peer)
        }

        sessionController.onStartReceivingResource = { [weak self] name, peer, progress in
            guard let self else { return }
            self.trackIncomingResource(progress: progress, name: name, peer: peer)
        }

        sessionController.onFinishReceivingResource = { [weak self] name, peer, url, error in
            guard let self else { return }
            self.finishIncomingResource(name: name, peer: peer, url: url, error: error)
        }
    }

    func sendMessage<Payload: Encodable>(payload: Payload,
                                         type: MPCMessageType,
                                         to peers: [MCPeerID],
                                         mode: MCSessionSendDataMode = .reliable) throws {
        let envelope = try MPCEnvelope(type: type, payload: payload, encoder: encoder)
        let data = try encoder.encode(envelope)
        do {
            try sessionController.send(data, to: peers, mode: mode)
            registerInstantProgress(for: type, peers: peers)
        } catch {
            throw MPCError.sessionFailed
        }
    }

    @discardableResult
    func sendResource(at url: URL,
                      named name: String,
                      to peer: MCPeerID,
                      completion: ((Error?) -> Void)? = nil) -> UUID {
        let progressID = UUID()
        let startDate = Date()
        let progress = sessionController.sendResource(at: url, name: name, to: peer) { [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                if let existing = self.progressByID[progressID], error == nil {
                    self.progressByID[progressID] = existing.updating(progress: 1,
                                                                       bytesTransferred: existing.totalBytes,
                                                                       totalBytes: existing.totalBytes,
                                                                       updatedAt: Date())
                }
                self.cleanupProgress(id: progressID)
                completion?(error)
            }
        }

        if let progress {
            let key = ResourceKey(peerDisplayName: peer.displayName, resourceName: name)
            progressKeyMap[key] = progressID
            progressHandles[progressID] = progress
            progress.cancellationHandler = { [weak self] in
                Task { @MainActor in
                    self?.cleanupProgress(id: progressID)
                }
            }
            observers[progressID] = progress.observe(\.fractionCompleted, options: [.initial, .new]) { [weak self] progress, _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.updateProgressEntry(id: progressID,
                                             peer: peer,
                                             name: name,
                                             progress: progress,
                                             startedAt: startDate)
                }
            }
        } else {
            completion?(MPCError.resourceNotFound)
        }

        return progressID
    }

    func cancelTransfer(id: UUID) {
        if let progress = progressHandles[id], progress.isCancelled == false {
            progress.cancel()
        } else {
            cleanupProgress(id: id)
        }
    }

    private func handle(envelope: MPCEnvelope, from peer: MCPeerID) {
        do {
            switch envelope.type {
            case .hello:
                let payload = try envelope.decodePayload(as: MPCHelloMessage.self, decoder: decoder)
                onHelloMessage?(payload, peer)
            case .capabilities:
                let payload = try envelope.decodePayload(as: MPCCapabilitiesMessage.self, decoder: decoder)
                onCapabilitiesMessage?(payload, peer)
            case .profileSnapshot:
                let payload = try envelope.decodePayload(as: ProfileExportV1.self, decoder: decoder)
                onProfileExport?(payload, peer)
            case .actionsDelta:
                let payload = try envelope.decodePayload(as: ActionsDeltaMessage.self, decoder: decoder)
                onActionsDelta?(payload, peer)
            case .ack:
                let payload = try envelope.decodePayload(as: MPCAcknowledgement.self, decoder: decoder)
                onAcknowledgement?(payload, peer)
            case .error:
                let payload = try envelope.decodePayload(as: MPCErrorMessage.self, decoder: decoder)
                onErrorMessage?(payload, peer)
            }
        } catch let error as MPCError {
            onIncompatibleEnvelope?(envelope, error, peer)
        } catch {
            onIncompatibleEnvelope?(envelope, .decodingFailed, peer)
        }
    }

    private func trackIncomingResource(progress: Progress, name: String, peer: MCPeerID) {
        let progressID = UUID()
        let key = ResourceKey(peerDisplayName: peer.displayName, resourceName: name)
        progressKeyMap[key] = progressID
        let startDate = Date()
        progressHandles[progressID] = progress
        progress.cancellationHandler = { [weak self] in
            Task { @MainActor in
                self?.cleanupProgress(id: progressID)
            }
        }
        observers[progressID] = progress.observe(\.fractionCompleted, options: [.initial, .new]) { [weak self] progress, _ in
            Task { @MainActor in
                guard let self else { return }
                self.updateProgressEntry(id: progressID,
                                         peer: peer,
                                         name: name,
                                         progress: progress,
                                         startedAt: startDate)
            }
        }
    }

    private func finishIncomingResource(name: String, peer: MCPeerID, url: URL?, error: Error?) {
        let key = ResourceKey(peerDisplayName: peer.displayName, resourceName: name)
        guard let progressID = progressKeyMap[key] else { return }
        progressKeyMap[key] = nil
        if let url, error == nil {
            onResourceReceived?(url, name, peer)
        }
        cleanupProgress(id: progressID)
    }

    private func cleanupProgress(id: UUID) {
        observers[id]?.invalidate()
        observers[id] = nil
        progressByID[id] = nil
        if let entry = progressKeyMap.first(where: { $0.value == id })?.key {
            progressKeyMap[entry] = nil
        }
        progressHandles[id] = nil
        notifyProgressChange()
    }

    private func registerInstantProgress(for type: MPCMessageType, peers: [MCPeerID]) {
        guard peers.isEmpty == false else { return }
        let timestamp = Date()
        let snapshots = peers.map { peer in
            MPCTransferProgress(id: UUID(),
                                peerID: peer,
                                kind: .message(type: type),
                                progress: 1,
                                bytesTransferred: 0,
                                totalBytes: 0,
                                startedAt: timestamp,
                                updatedAt: timestamp,
                                estimatedRemainingTime: 0)
        }
        onTransferProgress?(snapshots)
    }

    private func notifyProgressChange() {
        onTransferProgress?(Array(progressByID.values))
    }

    private func updateProgressEntry(id: UUID,
                                     peer: MCPeerID,
                                     name: String,
                                     progress: Progress,
                                     startedAt: Date) {
        let totalUnits = max(max(progress.totalUnitCount, progress.completedUnitCount), 1)
        let existing = progressByID[id] ?? MPCTransferProgress(id: id,
                                                               peerID: peer,
                                                               kind: .resource(name: name),
                                                               progress: 0,
                                                               bytesTransferred: 0,
                                                               totalBytes: totalUnits,
                                                               startedAt: startedAt,
                                                               updatedAt: startedAt)
        let updated = existing.updating(progress: progress.fractionCompleted,
                                        bytesTransferred: progress.completedUnitCount,
                                        totalBytes: totalUnits,
                                        updatedAt: Date())
        progressByID[id] = updated
        notifyProgressChange()
    }
}
