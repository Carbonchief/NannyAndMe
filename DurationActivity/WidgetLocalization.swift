import Foundation

enum WidgetL10n {
    enum Actions {
        static let sleep = String(localized: "actions.sleep", defaultValue: "Sleep")
        static let feeding = String(localized: "actions.feeding", defaultValue: "Feeding")

        static func feedingBottle(_ volume: Int) -> String {
            let format = String(localized: "actions.feeding.bottle", defaultValue: "Bottle (%lld ml)")
            return String(format: format, locale: Locale.current, volume)
        }

        static func feedingWithType(_ type: String) -> String {
            let format = String(localized: "actions.feeding.withType", defaultValue: "%@")
            return String(format: format, locale: Locale.current, type)
        }
    }

    enum FeedingType {
        static let bottle = String(localized: "feeding.bottle", defaultValue: "Bottle")
        static let leftBreast = String(localized: "feeding.leftBreast", defaultValue: "Left Breast")
        static let rightBreast = String(localized: "feeding.rightBreast", defaultValue: "Right Breast")
        static let meal = String(localized: "feeding.meal", defaultValue: "Meal")
    }

    enum Profile {
        static let newProfile = String(localized: "profile.new", defaultValue: "New Profile")
    }

    enum Formatter {
        static let justNow = String(localized: "formatter.justNow", defaultValue: "Just now")
    }

    enum Duration {
        static let noActiveTimers = String(localized: "widget.duration.noActive", defaultValue: "No active timers")
    }

    enum Common {
        static let stop = String(localized: "common.stop", defaultValue: "Stop")
    }
}
