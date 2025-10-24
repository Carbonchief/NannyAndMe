import CloudKit
import Foundation

enum CKConfig {
    static let containerID = "iCloud.com.prioritybit.nannyandme"

    static func container() -> CKContainer {
        CKContainer(identifier: containerID)
    }

    static func privateDatabase() -> CKDatabase {
        container().privateCloudDatabase
    }

    static func sharedDatabase() -> CKDatabase {
        container().sharedCloudDatabase
    }
}
