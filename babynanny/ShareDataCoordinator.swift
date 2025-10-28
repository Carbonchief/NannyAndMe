import Foundation
import SwiftUI

@MainActor
final class ShareDataCoordinator: ObservableObject {
    struct ExternalImportRequest: Identifiable, Equatable, Sendable {
        let id = UUID()
        let url: URL

        static func == (lhs: ExternalImportRequest, rhs: ExternalImportRequest) -> Bool {
            lhs.id == rhs.id
        }
    }

    @Published var isShowingShareData = false
    @Published private(set) var externalImportRequest: ExternalImportRequest?

    func presentShareData() {
        isShowingShareData = true
    }

    func handleIncomingFile(url: URL) {
        externalImportRequest = ExternalImportRequest(url: url)
        isShowingShareData = true
    }

    func clearExternalImportRequest(_ request: ExternalImportRequest) {
        guard externalImportRequest?.id == request.id else { return }
        externalImportRequest = nil
    }

    func dismissShareData() {
        isShowingShareData = false
    }
}
