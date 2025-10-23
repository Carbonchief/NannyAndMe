import SwiftUI
import XCTest
@testable import babynanny

@MainActor
final class SideMenuTests: XCTestCase {
    func testShareButtonHiddenWhenCloudUnavailable() {
        let view = SideMenu(isCloudSharingAvailable: false,
                            onSelectAllLogs: {},
                            onSelectShareProfile: {},
                            onSelectSettings: {},
                            onSelectShareData: {})
        let hosting = UIHostingController(rootView: view)
        hosting.view.frame = CGRect(x: 0, y: 0, width: 320, height: 640)
        hosting.view.layoutIfNeeded()
        let labels = hosting.view.allLabelTexts()
        XCTAssertFalse(labels.contains(L10n.Menu.shareProfile))
    }

    func testShareButtonVisibleWhenCloudAvailable() {
        let view = SideMenu(isCloudSharingAvailable: true,
                            onSelectAllLogs: {},
                            onSelectShareProfile: {},
                            onSelectSettings: {},
                            onSelectShareData: {})
        let hosting = UIHostingController(rootView: view)
        hosting.view.frame = CGRect(x: 0, y: 0, width: 320, height: 640)
        hosting.view.layoutIfNeeded()
        let labels = hosting.view.allLabelTexts()
        XCTAssertTrue(labels.contains(L10n.Menu.shareProfile))
    }
}

private extension UIView {
    func allLabelTexts() -> [String] {
        var results: [String] = []
        if let label = self as? UILabel, let text = label.text {
            results.append(text)
        }
        for subview in subviews {
            results.append(contentsOf: subview.allLabelTexts())
        }
        return results
    }
}
