import Foundation
import MultipeerConnectivity

/// A protocol abstraction over ``MCSession`` to support dependency injection and testing.
protocol MPCSessioning: AnyObject {
    var delegate: MCSessionDelegate? { get set }
    var connectedPeers: [MCPeerID] { get }
    var myPeerID: MCPeerID { get }

    func send(_ data: Data, toPeers peers: [MCPeerID], with mode: MCSessionSendDataMode) throws
    func sendResource(at resourceURL: URL,
                      withName name: String,
                      toPeer peerID: MCPeerID,
                      withCompletionHandler completionHandler: ((Error?) -> Void)?) -> Progress?
    func startStream(withName streamName: String, toPeer peerID: MCPeerID) throws -> OutputStream
    func disconnect()
}

extension MCSession: MPCSessioning {}

/// Abstraction for ``MCNearbyServiceBrowser`` interactions.
protocol MPCBrowsing: AnyObject {
    var delegate: MCNearbyServiceBrowserDelegate? { get set }

    func startBrowsingForPeers()
    func stopBrowsingForPeers()
    func invitePeer(_ peerID: MCPeerID, to session: MCSession, withContext context: Data?, timeout: TimeInterval)
}

extension MCNearbyServiceBrowser: MPCBrowsing {}

/// Abstraction for ``MCNearbyServiceAdvertiser`` interactions.
protocol MPCAdvertising: AnyObject {
    var delegate: MCNearbyServiceAdvertiserDelegate? { get set }

    func startAdvertisingPeer()
    func stopAdvertisingPeer()
}

extension MCNearbyServiceAdvertiser: MPCAdvertising {}

/// Factory capable of producing new session instances.
protocol MPCSessionFactory {
    func makeSession(for peerID: MCPeerID) -> MCSession
}

struct DefaultMPCSessionFactory: MPCSessionFactory {
    func makeSession(for peerID: MCPeerID) -> MCSession {
        MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
    }
}
