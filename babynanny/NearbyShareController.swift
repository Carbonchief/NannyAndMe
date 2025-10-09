import Combine
import MultipeerConnectivity
import SwiftUI
import UIKit

@MainActor
final class NearbyShareController: NSObject, ObservableObject {
    enum Phase: Equatable {
        case idle
        case preparing
        case presenting
        case sending(peer: String)
    }

    struct ShareResult: Identifiable {
        enum Outcome {
            case success(peer: String, filename: String)
            case failure(message: String)
            case cancelled
        }

        let id = UUID()
        let outcome: Outcome
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var latestResult: ShareResult?

    var isBusy: Bool {
        switch phase {
        case .idle:
            return false
        case .preparing, .presenting, .sending:
            return true
        }
    }

    var resultPublisher: AnyPublisher<ShareResult, Never> {
        $latestResult
            .compactMap { $0 }
            .eraseToAnyPublisher()
    }

    private let serviceType = "nannyshare"
    private let peerID: MCPeerID
    private var session: MCSession
    private var advertiser: MCNearbyServiceAdvertiser?
    private var pendingData: Data?
    private var pendingFilename: String = ""

    override init() {
        peerID = MCPeerID(displayName: UIDevice.current.name)
        session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        super.init()
        session.delegate = self
    }

    func prepareShare(data: Data, filename: String) {
        pendingData = data
        pendingFilename = filename
        phase = .preparing
    }

    func makeBrowserViewController() -> MCBrowserViewController {
        startAdvertising()
        phase = .presenting
        let browser = MCBrowserViewController(serviceType: serviceType, session: session)
        browser.delegate = self
        return browser
    }

    func cancelSharing() {
        if pendingData != nil {
            latestResult = ShareResult(outcome: .cancelled)
        }
        cleanup()
    }

    func clearLatestResult() {
        latestResult = nil
    }

    private func startAdvertising() {
        stopAdvertising()
        advertiser = MCNearbyServiceAdvertiser(peer: peerID, discoveryInfo: nil, serviceType: serviceType)
        advertiser?.delegate = self
        advertiser?.startAdvertisingPeer()
    }

    private func stopAdvertising() {
        advertiser?.stopAdvertisingPeer()
        advertiser?.delegate = nil
        advertiser = nil
    }

    private func sendPendingData(to peers: [MCPeerID]) {
        guard let data = pendingData else { return }
        guard let firstPeer = peers.first else {
            latestResult = ShareResult(
                outcome: .failure(message: L10n.ShareData.Alert.nearbyFailureMessage(""))
            )
            cleanup()
            return
        }

        phase = .sending(peer: firstPeer.displayName)
        stopAdvertising()

        do {
            try session.send(data, toPeers: peers, with: .reliable)
            latestResult = ShareResult(
                outcome: .success(peer: firstPeer.displayName, filename: pendingFilename)
            )
        } catch {
            latestResult = ShareResult(outcome: .failure(message: L10n.ShareData.Alert.nearbyFailureMessage(error.localizedDescription)))
        }

        cleanup()
    }

    private func cleanup() {
        pendingData = nil
        pendingFilename = ""
        stopAdvertising()
        session.disconnect()
        session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
        phase = .idle
    }
}

extension NearbyShareController: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        switch state {
        case .connected:
            sendPendingData(to: session.connectedPeers)
        case .notConnected:
            if pendingData != nil {
                latestResult = ShareResult(
                    outcome: .failure(
                        message: L10n.ShareData.Alert.nearbyFailureMessage(L10n.ShareData.Nearby.errorPeerDisconnected)
                    )
                )
                cleanup()
            }
        case .connecting:
            break
        @unknown default:
            break
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) { }

    func session(
        _ session: MCSession,
        didReceive stream: InputStream,
        withName streamName: String,
        fromPeer peerID: MCPeerID
    ) { }

    func session(
        _ session: MCSession,
        didStartReceivingResourceWithName resourceName: String,
        fromPeer peerID: MCPeerID,
        with progress: Progress
    ) { }

    func session(
        _ session: MCSession,
        didFinishReceivingResourceWithName resourceName: String,
        fromPeer peerID: MCPeerID,
        at localURL: URL?,
        withError error: Error?
    ) { }
}

extension NearbyShareController: MCNearbyServiceAdvertiserDelegate {
    func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didReceiveInvitationFromPeer peerID: MCPeerID,
        withContext context: Data?,
        invitationHandler: @escaping (Bool, MCSession?) -> Void
    ) {
        invitationHandler(true, session)
    }
}

extension NearbyShareController: MCBrowserViewControllerDelegate {
    func browserViewControllerDidFinish(_ browserViewController: MCBrowserViewController) {
        if pendingData != nil {
            latestResult = ShareResult(outcome: .cancelled)
        }
        cleanup()
    }

    func browserViewControllerWasCancelled(_ browserViewController: MCBrowserViewController) {
        if pendingData != nil {
            latestResult = ShareResult(outcome: .cancelled)
        }
        cleanup()
    }
}

struct NearbyShareBrowserView: UIViewControllerRepresentable {
    let controller: NearbyShareController

    func makeUIViewController(context: Context) -> MCBrowserViewController {
        controller.makeBrowserViewController()
    }

    func updateUIViewController(_ uiViewController: MCBrowserViewController, context: Context) { }
}
