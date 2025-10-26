import CloudKit
import UIKit

@available(iOS 17.0, *)
final class CloudSharingController: UICloudSharingController {
    override init(share: CKShare, container: CKContainer) {
        super.init(share: share, container: container)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
