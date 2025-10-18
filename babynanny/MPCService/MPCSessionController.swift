import Foundation
import MultipeerConnectivity

/// Coordinates lifecycle updates from ``MCSession`` and emits strongly-typed callbacks.
@MainActor
final class MPCSessionController: NSObject {
    enum LifecycleState: Equatable {
        case idle
        case connecting(peer: MCPeerID)
        case connected(peer: MCPeerID)
        case disconnecting
    }

    private let session: MPCSessioning
    private(set) var lifecycleState: LifecycleState = .idle

    var onPeerStateChange: ((MCPeerID, MCSessionState) -> Void)?
    var onEnvelopeReceived: ((MPCEnvelope, MCPeerID) -> Void)?
    var onStartReceivingResource: ((String, MCPeerID, Progress) -> Void)?
    var onFinishReceivingResource: ((String, MCPeerID, URL?, Error?) -> Void)?
    var onSessionFailed: ((MPCError) -> Void)?

    init(session: MPCSessioning) {
        self.session = session
        super.init()
        session.delegate = self
    }

    func updateLifecycleState(_ state: LifecycleState) {
        lifecycleState = state
    }

    func disconnect() {
        lifecycleState = .disconnecting
        session.disconnect()
        lifecycleState = .idle
    }

    func send(_ data: Data, to peers: [MCPeerID], mode: MCSessionSendDataMode) throws {
        try session.send(data, toPeers: peers, with: mode)
    }

    @discardableResult
    func sendResource(at url: URL,
                      name: String,
                      to peer: MCPeerID,
                      completion: ((Error?) -> Void)?) -> Progress? {
        return session.sendResource(at: url, withName: name, toPeer: peer, withCompletionHandler: completion)
    }
}

extension MPCSessionController: MCSessionDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            switch state {
            case .connected:
                self.lifecycleState = .connected(peer: peerID)
            case .connecting:
                self.lifecycleState = .connecting(peer: peerID)
            case .notConnected:
                if case .disconnecting = self.lifecycleState {
                    self.lifecycleState = .idle
                } else {
                    self.lifecycleState = .idle
                    self.onSessionFailed?(.sessionFailed)
                }
            @unknown default:
                break
            }
            self.onPeerStateChange?(peerID, state)
        }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            do {
                let envelope = try decoder.decode(MPCEnvelope.self, from: data)
                self.onEnvelopeReceived?(envelope, peerID)
            } catch {
                self.onSessionFailed?(.decodingFailed)
            }
        }
    }

    nonisolated func session(_ session: MCSession,
                             didStartReceivingResourceWithName resourceName: String,
                             fromPeer peerID: MCPeerID,
                             with progress: Progress) {
        Task { @MainActor [weak self] in
            self?.onStartReceivingResource?(resourceName, peerID, progress)
        }
    }

    nonisolated func session(_ session: MCSession,
                             didFinishReceivingResourceWithName resourceName: String,
                             fromPeer peerID: MCPeerID,
                             at localURL: URL?,
                             withError error: Error?) {
        Task { @MainActor [weak self] in
            self?.onFinishReceivingResource?(resourceName, peerID, localURL, error)
        }
    }

    nonisolated func session(_ session: MCSession,
                             didReceive stream: InputStream,
                             withName streamName: String,
                             fromPeer peerID: MCPeerID) {
        stream.close()
    }
}
