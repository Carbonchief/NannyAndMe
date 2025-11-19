import SwiftUI
import UIKit
import AVFoundation

/// Non-isolated helper that wraps AVCaptureDevice.requestAccess in async/await.
/// Safe to be called from any actor / thread.
nonisolated
func requestCameraAccessTCCBridge() async -> Bool {
    await withCheckedContinuation { continuation in
        AVCaptureDevice.requestAccess(for: .video) { granted in
            // This runs on TCC's queue; the continuation is non-isolated,
            // so it's safe to resume directly here.
            continuation.resume(returning: granted)
        }
    }
}

struct ShareDataQRScannerView: View {
    let onScan: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var hasRequestedAccess = false
    @State private var cameraUnavailable = QRCodeScannerController.isCameraAvailable == false
    @State private var scannerError: String?

    var body: some View {
        NavigationStack {
            ZStack {
                scannerContent
                if authorizationStatus == .authorized && scannerError == nil && !cameraUnavailable {
                    instructionsOverlay
                        .padding()
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                }
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle(L10n.ShareData.QRScanner.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L10n.Common.cancel) { dismiss() }
                }
            }
        }
        .task {
            await requestCameraAccessIfNeeded()
        }
    }

    @ViewBuilder
    private var scannerContent: some View {
        if cameraUnavailable {
            unavailableView(text: L10n.ShareData.QRScanner.unavailable)
        } else if let scannerError {
            unavailableView(text: scannerError)
        } else {
            switch authorizationStatus {
            case .authorized:
                QRCodeScannerRepresentable(onResult: handleScan, onError: handleScannerError)
                    .ignoresSafeArea()
            case .notDetermined:
                ProgressView(L10n.ShareData.QRScanner.loading)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .denied, .restricted:
                deniedView
            default:
                deniedView
            }
        }
    }

    private var instructionsOverlay: some View {
        Text(L10n.ShareData.QRScanner.instructions)
            .font(.footnote)
            .foregroundColor(.white)
            .padding(12)
            .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
            .multilineTextAlignment(.center)
    }

    private var deniedView: some View {
        VStack(spacing: 16) {
            Text(L10n.ShareData.QRScanner.denied)
                .font(.body)
                .multilineTextAlignment(.center)

            Button(L10n.ShareData.QRScanner.openSettings) {
                openSettings()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .background(Color(.systemGroupedBackground))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func unavailableView(text: String) -> some View {
        VStack(spacing: 12) {
            Text(text)
                .font(.body)
                .multilineTextAlignment(.center)
        }
        .padding()
        .background(Color(.systemGroupedBackground))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func handleScan(_ value: String) {
        dismiss()
        onScan(value)
    }

    private func handleScannerError(_ error: Error) {
        scannerError = L10n.ShareData.QRScanner.error
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func requestCameraAccessIfNeeded() async {
        guard authorizationStatus == .notDetermined, hasRequestedAccess == false else { return }
        hasRequestedAccess = true

        // Await the nonisolated helper. When this returns, we're back in whatever
        // context .task used (SwiftUI will run this on the main actor).
        let granted = await requestCameraAccessTCCBridge()
        authorizationStatus = granted ? .authorized : .denied
    }
}

struct QRCodeScannerRepresentable: UIViewControllerRepresentable {
    let onResult: (String) -> Void
    let onError: (Error) -> Void

    func makeUIViewController(context: Context) -> QRCodeScannerController {
        let controller = QRCodeScannerController()
        controller.onResult = onResult
        controller.onError = onError
        return controller
    }

    func updateUIViewController(_ uiViewController: QRCodeScannerController, context: Context) { }

    static func dismantleUIViewController(_ uiViewController: QRCodeScannerController, coordinator: ()) {
        uiViewController.stopScanning()
    }
}

final class QRCodeScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    enum ScannerError: LocalizedError {
        case cameraUnavailable
        case configurationFailed
    }

    static var isCameraAvailable: Bool {
        AVCaptureDevice.default(for: .video) != nil
    }

    var onResult: ((String) -> Void)?
    var onError: ((Error) -> Void)?

    private let sessionBox = CaptureSessionBox()
    private let sessionQueue = DispatchQueue(label: "sharedata.qr.session", qos: .userInitiated)
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var hasReportedResult = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureSession()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    private func configureSession() {
        guard let videoDevice = AVCaptureDevice.default(for: .video) else {
            onError?(ScannerError.cameraUnavailable)
            return
        }

        do {
            let input = try AVCaptureDeviceInput(device: videoDevice)
            guard session.canAddInput(input) else {
                onError?(ScannerError.configurationFailed)
                return
            }
            session.addInput(input)
        } catch {
            onError?(error)
            return
        }

        let metadataOutput = AVCaptureMetadataOutput()
        guard session.canAddOutput(metadataOutput) else {
            onError?(ScannerError.configurationFailed)
            return
        }
        session.addOutput(metadataOutput)
        metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
        metadataOutput.metadataObjectTypes = [.qr]

        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
        self.previewLayer = previewLayer

        sessionQueue.async { [sessionBox] in
            sessionBox.session.startRunning()
        }
    }

    nonisolated func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard let object = metadataObjects.compactMap({ $0 as? AVMetadataMachineReadableCodeObject }).first,
              let value = object.stringValue else { return }

        Task { @MainActor [weak self] in
            guard let self, self.hasReportedResult == false else { return }
            self.hasReportedResult = true
            self.session.stopRunning()
            self.onResult?(value)
        }
    }

    func stopScanning() {
        sessionQueue.async { [sessionBox] in
            sessionBox.session.stopRunning()
        }
        hasReportedResult = false
    }

    private var session: AVCaptureSession {
        sessionBox.session
    }
}

final class CaptureSessionBox: @unchecked Sendable {
    let session = AVCaptureSession()
}
