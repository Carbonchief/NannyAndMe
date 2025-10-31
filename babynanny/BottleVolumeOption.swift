import Foundation

enum BottleVolumeOption: Hashable, Identifiable {
    case preset(Int)
    case custom

    static let presets: [BottleVolumeOption] = [.preset(60), .preset(90), .preset(120), .preset(150)]
    static let allOptions: [BottleVolumeOption] = presets + [.custom]

    var id: String {
        switch self {
        case .preset(let value):
            return "preset_\(value)"
        case .custom:
            return "custom"
        }
    }

    var label: String {
        switch self {
        case .preset(let value):
            return L10n.Home.bottlePresetLabel(value)
        case .custom:
            return L10n.Home.customBottleOption
        }
    }
}
