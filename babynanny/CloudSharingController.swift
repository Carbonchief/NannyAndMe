import CloudKit
import UIKit

@available(iOS 17.0, *)
final class CloudSharingController: UICloudSharingController {
    init(share: CKShare, container: CKContainer) {
        super.init(preparationHandler: { _, completion in
            completion(share, container, nil)
        })
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
