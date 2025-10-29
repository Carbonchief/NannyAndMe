import CloudKit
import UIKit

extension AppDelegate {
    func application(_ application: UIApplication, userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        Task { @MainActor [weak self] in
            guard let self = self,
                  let cloudKitManager = self.cloudKitManager else { return }
            do {
                try await cloudKitManager.acceptShare(metadata: metadata)
                self.sharingCoordinator?.registerAcceptedShare(metadata: metadata)
                let zoneName = metadata.share.recordID.zoneID.zoneName
                self.logger.debug("Accepted CloudKit share for zone \(zoneName)")
            } catch {
                self.logger.error("Failed to accept CloudKit share: \(error.localizedDescription)")
            }
        }
    }
}
