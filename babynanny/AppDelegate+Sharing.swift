import CloudKit
import UIKit

extension AppDelegate {
    func application(_ application: UIApplication, userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        Task { @MainActor [weak self] in
            guard let self, let cloudKitManager else { return }
            do {
                try await cloudKitManager.acceptShare(metadata: metadata)
                sharingCoordinator?.registerAcceptedShare(metadata: metadata)
                let zoneName = metadata.share.recordID.zoneID.zoneName
                logger.debug("Accepted CloudKit share for zone \(zoneName)")
            } catch {
                logger.error("Failed to accept CloudKit share: \(error.localizedDescription)")
            }
        }
    }
}
