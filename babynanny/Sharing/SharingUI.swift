import CloudKit
import Foundation
import SwiftUI
import os

/// SwiftUI wrapper around `UICloudSharingController` that exposes callbacks for
/// successful saves and stop-sharing events while wiring a `CKSystemSharingUIObserver`.
struct SharingUI: UIViewControllerRepresentable {
    typealias UIViewControllerType = UICloudSharingController

    var share: CKShare
    var container: CKContainer
    var itemTitle: String?
    var thumbnailData: Data?
    var onDidSaveShare: (() -> Void)?
    var onDidStopSharing: (() -> Void)?
    var showsItemPreview: Bool = true

    func makeCoordinator() -> Coordinator {
        Coordinator(share: share,
                    container: container,
                    itemTitle: itemTitle,
                    thumbnailData: thumbnailData,
                    showsItemPreview: showsItemPreview,
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
        private let logger = Logger(subsystem: "com.prioritybit.nannyandme", category: "share")
        private var observer: SystemSharingObserver?
        private let share: CKShare
        private let itemTitle: String?
        private let thumbnailData: Data?
        private var onDidSaveShare: (() -> Void)?
        private var onDidStopSharing: (() -> Void)?
        private let showsItemPreview: Bool

        init(share: CKShare,
             container: CKContainer,
             itemTitle: String?,
             thumbnailData: Data?,
             showsItemPreview: Bool,
             onDidSaveShare: (() -> Void)?,
             onDidStopSharing: (() -> Void)?) {
            self.share = share
            self.itemTitle = itemTitle
            self.thumbnailData = thumbnailData
            self.showsItemPreview = showsItemPreview
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
            guard showsItemPreview else { return nil }
            if let itemTitle, itemTitle.isEmpty == false {
                return itemTitle
            }
            if let title = share[CKShare.SystemFieldKey.title] as? String,
               title.isEmpty == false {
                return title
            }
            return nil
        }

        func itemThumbnailData(for csc: UICloudSharingController) -> Data? {
            guard showsItemPreview else { return nil }
            if let thumbnailData, thumbnailData.isEmpty == false {
                return thumbnailData
            }
            if let shareThumbnail = share[CKShare.SystemFieldKey.thumbnailImageData] as? Data,
               shareThumbnail.isEmpty == false {
                return shareThumbnail
            }
            return nil
        }

        func itemThumbnailDataIsPlaceholder(for csc: UICloudSharingController) -> Bool {
            guard showsItemPreview else { return true }
            return itemThumbnailData(for: csc) == nil
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
        configureObserver(with: container)
    }

    func start() {
        guard let observer else { return }
        if observer.responds(to: NSSelectorFromString("startObserving")) {
            _ = observer.perform(NSSelectorFromString("startObserving"))
        }
    }

    private func configureObserver(with container: CKContainer) {
        let observer = CKSystemSharingUIObserver(container: container)
        if observer.responds(to: NSSelectorFromString("setDelegate:")) {
            _ = observer.perform(NSSelectorFromString("setDelegate:"), with: self)
        }
        self.observer = observer
    }
}

private extension SystemSharingObserver {
    @objc func systemSharingUIObserver(_ observer: AnyObject, didSave share: CKShare) {
        onDidSaveShare()
    }

    @objc func systemSharingUIObserver(_ observer: AnyObject, didStopSharing share: CKShare) {
        onDidStopSharing()
    }

    @objc func systemSharingUIObserver(_ observer: AnyObject,
                                       failedToSaveShareWithError error: Error) {}
}
