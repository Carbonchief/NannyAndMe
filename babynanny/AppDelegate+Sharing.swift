import CloudKit
import UIKit

extension AppDelegate {
    func application(_ application: UIApplication, userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        Task { @MainActor [weak self] in
            guard let self, let cloudKitManager else { return }
            do {
                try await cloudKitManager.acceptShare(metadata: metadata)
                sharingCoordinator?.registerAcceptedShare(metadata: metadata)
                logger.debug("Accepted CloudKit share for zone \(metadata.rootRecordID.zoneID.zoneName, privacy: .public)")
            } catch {
                logger.error("Failed to accept CloudKit share: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
