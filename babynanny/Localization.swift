import Foundation

enum L10n {
    enum Tab {
        static let home = String(localized: "tab.home.title", defaultValue: "Home")
        static let stats = String(localized: "tab.stats.title", defaultValue: "Stats")
    }

    enum Common {
        static let stop = String(localized: "common.stop", defaultValue: "Stop")
        static let start = String(localized: "common.start", defaultValue: "Start")
        static let log = String(localized: "common.log", defaultValue: "Log")
        static let cancel = String(localized: "common.cancel", defaultValue: "Cancel")
        static let done = String(localized: "common.done", defaultValue: "Done")
    }

    enum Home {
        static let recentActivity = String(localized: "home.recentActivity", defaultValue: "Recent Activity")
        static let recentActivityShowAll = String(localized: "home.recentActivity.showAll", defaultValue: "Show All")
        static let headerTitle = String(localized: "home.header.title", defaultValue: "Last Action")
        static let placeholder = String(localized: "home.header.placeholder", defaultValue: "Start an action below to begin tracking your baby's day.")
        static let noEntries = String(localized: "home.noEntries", defaultValue: "No entries yet")
        static let editActionButton = String(localized: "home.header.edit", defaultValue: "Edit")
        static let sleepInfo = String(localized: "home.sleep.info", defaultValue: "Start tracking a sleep session. Stop it when your little one wakes up to capture the total rest time.")
        static let diaperTypeSectionTitle = String(localized: "home.diaper.sectionTitle", defaultValue: "Diaper type")
        static let diaperTypePickerLabel = String(localized: "home.diaper.pickerLabel", defaultValue: "Diaper type")
        static let feedingTypeSectionTitle = String(localized: "home.feeding.sectionTitle", defaultValue: "Feeding type")
        static let feedingTypePickerLabel = String(localized: "home.feeding.pickerLabel", defaultValue: "Feeding type")
        static let bottleVolumeSectionTitle = String(localized: "home.bottle.sectionTitle", defaultValue: "Bottle volume")
        static let bottleVolumePickerLabel = String(localized: "home.bottle.pickerLabel", defaultValue: "Bottle volume")
        static let customVolumeFieldPlaceholder = String(localized: "home.bottle.customFieldPlaceholder", defaultValue: "Custom volume (ml)")
        static let customBottleOption = String(localized: "home.bottle.customOption", defaultValue: "Custom")
        static let editActionTitle = String(localized: "home.sheet.editActionTitle", defaultValue: "Edit Action")
        static let editStartSectionTitle = String(localized: "home.edit.startSectionTitle", defaultValue: "Start time")
        static let editStartPickerLabel = String(localized: "home.edit.startPickerLabel", defaultValue: "Start")
        static let editCategoryLabel = String(localized: "home.edit.categoryLabel", defaultValue: "Category")
        static let editEndSectionTitle = String(localized: "home.edit.endSectionTitle", defaultValue: "End time")
        static let editEndPickerLabel = String(localized: "home.edit.endPickerLabel", defaultValue: "End")
        static let editEndNote = String(
            localized: "home.edit.endNote",
            defaultValue: "End time can be adjusted once the action has ended."
        )

        static func activeFor(_ duration: String) -> String {
            let format = String(localized: "home.header.activeFor", defaultValue: "Active for %@")
            return String(format: format, locale: Locale.current, duration)
        }

        static func lastFinished(_ value: String) -> String {
            let format = String(localized: "home.header.lastFinished", defaultValue: "Last finished %@")
            return String(format: format, locale: Locale.current, value)
        }

        static func startedAt(_ value: String) -> String {
            let format = String(localized: "home.card.startedAt", defaultValue: "Started at %@")
            return String(format: format, locale: Locale.current, value)
        }

        static func elapsed(_ value: String) -> String {
            let format = String(localized: "home.card.elapsed", defaultValue: "Elapsed: %@")
            return String(format: format, locale: Locale.current, value)
        }

        static func lastRun(_ value: String) -> String {
            let format = String(localized: "home.card.lastRun", defaultValue: "Last run %@")
            return String(format: format, locale: Locale.current, value)
        }

        static func lastRunWithDuration(_ value: String, _ duration: String) -> String {
            let format = String(
                localized: "home.card.lastRunWithDuration",
                defaultValue: "Last run %@ • Duration %@"
            )
            return String(format: format, locale: Locale.current, value, duration)
        }

        static func newActionTitle(_ categoryTitle: String) -> String {
            let format = String(localized: "home.sheet.newActionTitle", defaultValue: "New %@ Action")
            return String(format: format, locale: Locale.current, categoryTitle)
        }

        static func bottlePresetLabel(_ value: Int) -> String {
            let format = String(localized: "home.bottle.presetLabel", defaultValue: "%lld ml")
            return String(format: format, locale: Locale.current, value)
        }

        static func historyStarted(_ value: String) -> String {
            let format = String(localized: "home.history.started", defaultValue: "Started %@")
            return String(format: format, locale: Locale.current, value)
        }

        static func historyEnded(_ end: String, _ duration: String) -> String {
            let format = String(localized: "home.history.ended", defaultValue: "Ended %@ • Duration %@")
            return String(format: format, locale: Locale.current, end, duration)
        }
    }

    enum Profiles {
        static let activeSection = String(localized: "profiles.activeSection", defaultValue: "Active Profiles")
        static let addProfile = String(localized: "profiles.add", defaultValue: "Add Profile")
        static let title = String(localized: "profiles.title", defaultValue: "Profiles")
        static let activeProfileSection = String(localized: "profiles.activeProfile.section", defaultValue: "Active Profile")
        static let childName = String(localized: "profiles.childName", defaultValue: "Child name")
        static let birthDate = String(localized: "profiles.birthDate", defaultValue: "Birth date")
        static let choosePhoto = String(localized: "profiles.choosePhoto", defaultValue: "Choose profile photo")
        static let removePhoto = String(localized: "profiles.removePhoto", defaultValue: "Remove profile photo")

        static func deleteConfirmationTitle(_ name: String) -> String {
            let format = String(localized: "profiles.delete.confirmationTitle", defaultValue: "Delete %@?")
            return String(format: format, locale: Locale.current, name)
        }

        static func deleteConfirmationMessage(_ name: String) -> String {
            let format = String(
                localized: "profiles.delete.confirmationMessage",
                defaultValue: "This will remove %@ and all associated activity logs."
            )
            return String(format: format, locale: Locale.current, name)
        }

        static let deleteAction = String(localized: "profiles.delete.action", defaultValue: "Delete Profile")

        static func ageDescription(_ age: String) -> String {
            let format = String(localized: "profiles.age.format", defaultValue: "%@ old")
            return String(format: format, locale: Locale.current, age)
        }

        static let ageNewborn = String(localized: "profiles.age.newborn", defaultValue: "Newborn")
    }

    enum Settings {
        static let notificationsSection = String(localized: "settings.notifications.section", defaultValue: "Notifications")
        static let enableReminders = String(localized: "settings.notifications.enable", defaultValue: "Enable reminders")
        static let aboutSection = String(localized: "settings.about.section", defaultValue: "About")
        static let appVersion = String(localized: "settings.about.appVersion", defaultValue: "App Version")
        static let title = String(localized: "settings.title", defaultValue: "Settings")
        static let nextReminderLabel = String(
            localized: "settings.notifications.nextReminder.label",
            defaultValue: "Next reminder"
        )
        static let nextReminderDisabled = String(
            localized: "settings.notifications.nextReminder.disabled",
            defaultValue: "Reminders are turned off."
        )
        static let nextReminderUnavailable = String(
            localized: "settings.notifications.nextReminder.unavailable",
            defaultValue: "No reminders scheduled yet."
        )
        static let nextReminderLoading = String(
            localized: "settings.notifications.nextReminder.loading",
            defaultValue: "Loading…"
        )
        static let notificationsPermissionTitle = String(
            localized: "settings.notifications.permissionDenied.title",
            defaultValue: "Enable notifications"
        )
        static let notificationsPermissionMessage = String(
            localized: "settings.notifications.permissionDenied.message",
            defaultValue: "Notifications are currently turned off for Nanny & Me. Enable notifications in Settings to receive reminders."
        )
        static let notificationsPermissionAction = String(
            localized: "settings.notifications.permissionDenied.action",
            defaultValue: "Open Settings"
        )
        static let notificationsPermissionCancel = String(
            localized: "settings.notifications.permissionDenied.cancel",
            defaultValue: "Not now"
        )

        static func nextReminderScheduled(_ date: String, _ detail: String) -> String {
            let format = String(
                localized: "settings.notifications.nextReminder.scheduled",
                defaultValue: "%@ — %@"
            )
            return String(format: format, locale: Locale.current, date, detail)
        }
    }

    enum Notifications {
        static let ageReminderTitle = String(localized: "notifications.ageReminder.title", defaultValue: "Monthly milestone")

        static func ageReminderMessage(_ name: String, _ months: Int) -> String {
            if months == 1 {
                let format = String(localized: "notifications.ageReminder.oneMonth", defaultValue: "%@ is 1 month old today.")
                return String(format: format, locale: Locale.current, name)
            }

            let format = String(
                localized: "notifications.ageReminder.months",
                defaultValue: "%@ is %lld months old today."
            )
            return String(format: format, locale: Locale.current, name, months)
        }
    }

    enum Menu {
        static let title = String(localized: "menu.title", defaultValue: "Nanny & Me")
        static let subtitle = String(localized: "menu.subtitle", defaultValue: "Quick actions")
        static let allLogs = String(localized: "menu.allLogs", defaultValue: "All Logs")
        static let settings = String(localized: "menu.settings", defaultValue: "Settings")
    }

    enum Logs {
        static let title = String(localized: "logs.title", defaultValue: "All Logs")
        static let emptyTitle = String(localized: "logs.empty.title", defaultValue: "No logs yet")
        static let emptySubtitle = String(localized: "logs.empty.subtitle", defaultValue: "Actions you record will appear here, organized by day.")
        static let active = String(localized: "logs.active", defaultValue: "Active")
        static let filterSectionTitle = String(localized: "logs.filter.sectionTitle", defaultValue: "Date Range")
        static let filterToggle = String(localized: "logs.filter.toggle", defaultValue: "Filter by date range")
        static let filterStart = String(localized: "logs.filter.start", defaultValue: "Start date")
        static let filterEnd = String(localized: "logs.filter.end", defaultValue: "End date")
        static let filterClear = String(localized: "logs.filter.clear", defaultValue: "Clear filter")
        static let filterEmptyTitle = String(localized: "logs.filter.emptyTitle", defaultValue: "No logs for the selected dates")
        static let filterEmptySubtitle = String(
            localized: "logs.filter.emptySubtitle",
            defaultValue: "Try adjusting your date range to see more history."
        )

        static func entryTitle(_ startTime: String, _ duration: String, _ summary: String) -> String {
            let format = String(localized: "logs.entry.title", defaultValue: "%@, %@ %@")
            return String(format: format, locale: Locale.current, startTime, duration, summary)
        }

        static func summarySleep() -> String {
            String(localized: "logs.summary.sleep", defaultValue: "sleep")
        }

        static func summaryDiaper(withType type: String) -> String {
            let format = String(localized: "logs.summary.diaperWithType", defaultValue: "diaper - %@")
            return String(format: format, locale: Locale.current, type)
        }

        static func summaryDiaper() -> String {
            String(localized: "logs.summary.diaper", defaultValue: "diaper")
        }

        static func summaryFeedingBottle(volume: Int) -> String {
            let format = String(localized: "logs.summary.feedingBottle", defaultValue: "feeding - bottle (%lld ml)")
            return String(format: format, locale: Locale.current, volume)
        }

        static func summaryFeeding(withType type: String) -> String {
            let format = String(localized: "logs.summary.feedingWithType", defaultValue: "feeding - %@")
            return String(format: format, locale: Locale.current, type)
        }

        static func summaryFeeding() -> String {
            String(localized: "logs.summary.feeding", defaultValue: "feeding")
        }
    }

    enum Stats {
        static let title = String(localized: "stats.title", defaultValue: "Stats")
        static let dailySnapshotTitle = String(localized: "stats.dailySnapshot.title", defaultValue: "Daily Snapshot")

        static func trackingActivities(_ count: Int, _ name: String) -> String {
            let format = String(localized: "stats.dailySnapshot.description", defaultValue: "Tracking %lld activities for %@.")
            return String(format: format, locale: Locale.current, count, name)
        }

        static let activeActionsTitle = String(localized: "stats.card.activeActions.title", defaultValue: "Active Actions")
        static let activeActionsSubtitle = String(localized: "stats.card.activeActions.subtitle", defaultValue: "Running right now")
        static let todaysLogsTitle = String(localized: "stats.card.todaysLogs.title", defaultValue: "Today's Logs")
        static let todaysLogsSubtitle = String(localized: "stats.card.todaysLogs.subtitle", defaultValue: "Completed entries")
        static let bottleFeedTitle = String(localized: "stats.card.bottleFeed.title", defaultValue: "Bottle Feed (ml)")
        static let bottleFeedSubtitle = String(localized: "stats.card.bottleFeed.subtitle", defaultValue: "Total today")
        static let sleepSessionsTitle = String(localized: "stats.card.sleepSessions.title", defaultValue: "Sleep Sessions")
        static let sleepSessionsSubtitle = String(localized: "stats.card.sleepSessions.subtitle", defaultValue: "Today")
        static let diapersYAxis = String(localized: "stats.chart.yAxis.diapers", defaultValue: "Diapers")
        static let minutesYAxis = String(localized: "stats.chart.yAxis.minutes", defaultValue: "Minutes")
        static let lastSevenDays = String(localized: "stats.chart.lastSevenDays", defaultValue: "Last 7 Days")
        static let actionPickerLabel = String(localized: "stats.chart.actionPicker.label", defaultValue: "Activity")
        static let activityTrendsTitle = String(localized: "stats.chart.activityTrends.title", defaultValue: "Activity Trends")
        static let activityTrendsSubtitle = String(localized: "stats.chart.activityTrends.subtitle", defaultValue: "Once you start logging activities you'll see a weekly breakdown here.")
        static let dayAxisLabel = String(localized: "stats.chart.xAxis.day", defaultValue: "Day")

        static func emptyStateTitle(_ focus: String) -> String {
            let format = String(localized: "stats.chart.empty.title", defaultValue: "No %@ logged in the last week.")
            return String(format: format, locale: Locale.current, focus)
        }

        static func emptyStateSubtitle(_ focus: String) -> String {
            let format = String(localized: "stats.chart.empty.subtitle", defaultValue: "Track %@ to see trends over time.")
            return String(format: format, locale: Locale.current, focus)
        }
    }

    enum Actions {
        static let sleep = String(localized: "actions.sleep", defaultValue: "Sleep")
        static let diaper = String(localized: "actions.diaper", defaultValue: "Diaper")
        static let feeding = String(localized: "actions.feeding", defaultValue: "Feeding")
        static let diaperChange = String(localized: "actions.diaper.change", defaultValue: "Diaper change")

        static func diaperWithType(_ type: String) -> String {
            let format = String(localized: "actions.diaper.withType", defaultValue: "Diaper: %@")
            return String(format: format, locale: Locale.current, type)
        }

        static func feedingBottle(_ volume: Int) -> String {
            let format = String(localized: "actions.feeding.bottle", defaultValue: "Feeding: Bottle (%lld ml)")
            return String(format: format, locale: Locale.current, volume)
        }

        static func feedingWithType(_ type: String) -> String {
            let format = String(localized: "actions.feeding.withType", defaultValue: "Feeding: %@")
            return String(format: format, locale: Locale.current, type)
        }
    }

    enum DiaperType {
        static let pee = String(localized: "diaper.pee", defaultValue: "Pee")
        static let poo = String(localized: "diaper.poo", defaultValue: "Poo")
        static let both = String(localized: "diaper.both", defaultValue: "Pee & Poo")
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
}
