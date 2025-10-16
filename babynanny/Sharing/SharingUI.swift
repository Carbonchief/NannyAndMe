import CloudKit
import SwiftUI
import os

/// SwiftUI wrapper around `UICloudSharingController` that exposes callbacks for
/// successful saves and stop-sharing events while wiring a `CKSystemSharingUIObserver`.
struct SharingUI: UIViewControllerRepresentable {
    typealias UIViewControllerType = UICloudSharingController

    var share: CKShare
    var container: CKContainer
    var onDidSaveShare: (() -> Void)?
    var onDidStopSharing: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(share: share,
                    container: container,
                    onDidSaveShare: onDidSaveShare,
                    onDidStopSharing: onDidStopSharing)
    }

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: share, container: container)
        controller.modalPresentationStyle = .formSheet
        controller.delegate = context.coordinator
        context.coordinator.attach(controller: controller)
        return controller
    }

    func updateUIViewController(_ controller: UICloudSharingController, context: Context) {
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        private let logger = Logger(subsystem: "com.prioritybit.babynanny", category: "share")
        private var observer: SystemSharingObserver?
        private let share: CKShare
        private var onDidSaveShare: (() -> Void)?
        private var onDidStopSharing: (() -> Void)?

        init(share: CKShare,
             container: CKContainer,
             onDidSaveShare: (() -> Void)?,
             onDidStopSharing: (() -> Void)?) {
            self.share = share
            self.onDidSaveShare = onDidSaveShare
            self.onDidStopSharing = onDidStopSharing
            super.init()
            observer = SystemSharingObserver(container: container,
                                             onDidSaveShare: { [weak self] in self?.handleSaveCallback() },
                                             onDidStopSharing: { [weak self] in self?.handleStopCallback() })
        }

        func attach(controller: UICloudSharingController) {
            observer?.start()
        }

        // MARK: UICloudSharingControllerDelegate

        func itemTitle(for csc: UICloudSharingController) -> String? {
            share[CKShare.SystemFieldKey.title] as? String
        }

        func itemThumbnailData(for csc: UICloudSharingController) -> Data? {
            nil
        }

        func itemThumbnailDataIsPlaceholder(for csc: UICloudSharingController) -> Bool {
            true
        }

        func cloudSharingController(_ csc: UICloudSharingController,
                                    failedToSaveShareWithError error: Error) {
            logger.error("Failed to save share from UI: \(error.localizedDescription, privacy: .public)")
        }

        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
            handleSaveCallback()
        }

        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
            handleStopCallback()
        }

        func cloudSharingControllerDidCancel(_ csc: UICloudSharingController) {}

        private func handleSaveCallback() {
            onDidSaveShare?()
        }

        private func handleStopCallback() {
            onDidStopSharing?()
        }
    }
}

// MARK: - System observer

@MainActor
private final class SystemSharingObserver: NSObject {
    private var observer: CKSystemSharingUIObserver?
    private let onDidSaveShare: () -> Void
    private let onDidStopSharing: () -> Void

    init(container: CKContainer,
         onDidSaveShare: @escaping () -> Void,
         onDidStopSharing: @escaping () -> Void) {
        self.onDidSaveShare = onDidSaveShare
        self.onDidStopSharing = onDidStopSharing
        super.init()
        observer = CKSystemSharingUIObserver(container: container, delegate: self)
    }

    func start() {
        observer?.startObserving()
    }
}

extension SystemSharingObserver: CKSystemSharingUIObserverDelegate {
    func systemSharingUIObserver(_ observer: CKSystemSharingUIObserver, didSave share: CKShare) {
        onDidSaveShare()
    }

    func systemSharingUIObserver(_ observer: CKSystemSharingUIObserver, didStopSharing share: CKShare) {
        onDidStopSharing()
    }

    func systemSharingUIObserver(_ observer: CKSystemSharingUIObserver,
                                 failedToSaveShareWithError error: Error) {}
}
