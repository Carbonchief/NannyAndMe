import UIKit

extension UIImage {
    /// Returns the primary application icon rendered for the current interface style.
    static var appIcon: UIImage? {
        guard
            let iconsDictionary = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
            let primaryIcon = iconsDictionary["CFBundlePrimaryIcon"] as? [String: Any],
            let iconFiles = primaryIcon["CFBundleIconFiles"] as? [String],
            let lastIconName = iconFiles.last
        else {
            return nil
        }

        return UIImage(named: lastIconName)
    }
}
