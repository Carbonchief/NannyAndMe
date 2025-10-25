import Foundation

enum L10n {
    enum Tab {
        static let home = String(localized: "tab.home.title", defaultValue: "Home")
        static let map = String(localized: "tab.map.title", defaultValue: "Map")
        static let reports = String(localized: "tab.reports.title", defaultValue: "Reports")
    }

    enum Common {
        static let stop = String(localized: "common.stop", defaultValue: "Stop")
        static let start = String(localized: "common.start", defaultValue: "Start")
        static let log = String(localized: "common.log", defaultValue: "Log")
        static let cancel = String(localized: "common.cancel", defaultValue: "Cancel")
        static let done = String(localized: "common.done", defaultValue: "Done")
        static let unspecified = String(localized: "common.unspecified", defaultValue: "Unspecified")
        static let close = String(localized: "common.close", defaultValue: "Close")
    }

    enum Splash {
        static let loading = String(localized: "splash.loading", defaultValue: "Loading")
    }

    enum Onboarding {
        static let profilePromptTitle = String(
            localized: "onboarding.profilePrompt.title",
            defaultValue: "Welcome to Nanny & Me"
        )
        static let profilePromptSubtitle = String(
            localized: "onboarding.profilePrompt.subtitle",
            defaultValue: "Let's start by naming your first profile."
        )
        static let profilePromptNameLabel = String(
            localized: "onboarding.profilePrompt.nameLabel",
            defaultValue: "Profile name"
        )
        static let profilePromptNamePlaceholder = String(
            localized: "onboarding.profilePrompt.namePlaceholder",
            defaultValue: "Enter a name"
        )
        static let profilePromptContinue = String(
            localized: "onboarding.profilePrompt.continue",
            defaultValue: "Continue"
        )
    }

    enum Home {
        static let recentActivity = String(localized: "home.recentActivity", defaultValue: "Recent Activity")
        static let recentActivityShowAll = String(localized: "home.recentActivity.showAll", defaultValue: "Show All")
        static let placeholder = String(localized: "home.header.placeholder", defaultValue: "Start an action below to begin tracking your baby's day.")
        static let noEntries = String(localized: "home.noEntries", defaultValue: "No entries yet")
        static let customReminderTitle = String(localized: "home.customReminder.title", defaultValue: "Schedule reminder")

        static func customReminderMessage(for name: String, category: BabyActionCategory) -> String {
            switch category {
            case .sleep:
                return customReminderSleepMessage(for: name)
            case .feeding:
                return customReminderFeedingMessage(for: name)
            case .diaper:
                return customReminderDiaperMessage(for: name)
            }
        }

        private static func customReminderSleepMessage(for name: String) -> String {
            let format = String(
                localized: "home.customReminder.message.sleep",
                defaultValue: "How long should we wait before reminding you that %1$@ needs to sleep?"
            )
            return String(format: format, locale: Locale.current, name)
        }

        private static func customReminderFeedingMessage(for name: String) -> String {
            let format = String(
                localized: "home.customReminder.message.feeding",
                defaultValue: "How long should we wait before reminding you that %1$@ needs to eat?"
            )
            return String(format: format, locale: Locale.current, name)
        }

        private static func customReminderDiaperMessage(for name: String) -> String {
            let format = String(
                localized: "home.customReminder.message.diaper",
                defaultValue: "How long should we wait before reminding you to change %1$@'s diaper?"
            )
            return String(format: format, locale: Locale.current, name)
        }

        static let customReminderDelayLabel = String(
            localized: "home.customReminder.delayLabel",
            defaultValue: "Reminder delay"
        )
        static let customReminderSchedule = String(
            localized: "home.customReminder.schedule",
            defaultValue: "Schedule"
        )
        static let customReminderNotificationsDeniedTitle = String(
            localized: "home.customReminder.notificationsDenied.title",
            defaultValue: "Enable notifications"
        )
        static let customReminderNotificationsDeniedMessage = String(
            localized: "home.customReminder.notificationsDenied.message",
            defaultValue: "Notifications are currently turned off for Nanny & Me. Enable notifications in Settings to receive reminders."
        )
        static let customReminderNotificationsDeniedSettings = String(
            localized: "home.customReminder.notificationsDenied.settings",
            defaultValue: "Open Settings"
        )
        static let customReminderNotificationsDeniedCancel = String(
            localized: "home.customReminder.notificationsDenied.cancel",
            defaultValue: "Not now"
        )
        static let editActionButton = String(localized: "home.header.edit", defaultValue: "Edit")
        static let sleepInfo = String(localized: "home.sleep.info", defaultValue: "Start tracking a sleep session. Stop it when your little one wakes up to capture the total rest time.")
        static let diaperTypeSectionTitle = String(localized: "home.diaper.sectionTitle", defaultValue: "Diaper type")
        static let diaperTypePickerLabel = String(localized: "home.diaper.pickerLabel", defaultValue: "Diaper type")
        static let feedingTypeSectionTitle = String(localized: "home.feeding.sectionTitle", defaultValue: "Feeding type")
        static let feedingTypePickerLabel = String(localized: "home.feeding.pickerLabel", defaultValue: "Feeding type")
        static let bottleTypeSectionTitle = String(localized: "home.bottleType.sectionTitle", defaultValue: "Bottle type")
        static let bottleTypePickerLabel = String(localized: "home.bottleType.pickerLabel", defaultValue: "Bottle type")
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
            let format = String(localized: "home.card.startedAt", defaultValue: "Started: %@")
            return String(format: format, locale: Locale.current, value)
        }

        static let startedLabel = String(
            localized: "home.card.startedLabel",
            defaultValue: "Started:"
        )

        static func elapsed(_ value: String) -> String {
            let format = String(localized: "home.card.elapsed", defaultValue: "Elapsed: %@")
            return String(format: format, locale: Locale.current, value)
        }

        static func lastRun(_ value: String) -> String {
            let format = String(localized: "home.card.lastRun", defaultValue: "Last run %@")
            return String(format: format, locale: Locale.current, value)
        }

        static func loggedAt(_ value: String) -> String {
            let format = String(localized: "home.card.loggedAt", defaultValue: "%@")
            return String(format: format, locale: Locale.current, value)
        }

        static func lastRunWithDuration(_ value: String, _ duration: String) -> String {
            let format = String(
                localized: "home.card.lastRunWithDuration",
                defaultValue: "Last run %@ • %@"
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
            let format = String(localized: "home.history.started", defaultValue: "Started: %@")
            return String(format: format, locale: Locale.current, value)
        }

        static func historyStopped(_ value: String) -> String {
            let format = String(localized: "home.history.stopped", defaultValue: "Stopped: %@")
            return String(format: format, locale: Locale.current, value)
        }

        static let historyStartedLabel = String(
            localized: "home.history.startedLabel",
            defaultValue: "Started"
        )

        static let historyStoppedLabel = String(
            localized: "home.history.stoppedLabel",
            defaultValue: "Stopped"
        )

        static func historyDuration(_ value: String) -> String {
            let format = String(localized: "home.history.duration", defaultValue: "For: %@")
            return String(format: format, locale: Locale.current, value)
        }

        static let historyDurationLabel = String(
            localized: "home.history.durationLabel",
            defaultValue: "Duration"
        )

        static let interruptionAlertTitle = String(
            localized: "home.interruptionAlert.title",
            defaultValue: "Stop current action?"
        )

        static func interruptionAlertMessage(_ newAction: String, _ runningActions: String) -> String {
            let format = String(
                localized: "home.interruptionAlert.message",
                defaultValue: "Starting a new %@ action will stop %@ that's currently running."
            )
            return String(format: format, locale: Locale.current, newAction, runningActions)
        }

        static let interruptionAlertConfirm = String(
            localized: "home.interruptionAlert.confirm",
            defaultValue: "Continue"
        )
    }

    enum Profiles {
        static let activeSection = String(localized: "profiles.activeSection", defaultValue: "Active Profiles")
        static let addProfile = String(localized: "profiles.add", defaultValue: "Add Profile")
        static let addPromptTitle = String(
            localized: "profiles.addPrompt.title",
            defaultValue: "Add a New Profile"
        )
        static let addPromptSubtitle = String(
            localized: "profiles.addPrompt.subtitle",
            defaultValue: "Enter a name to create a profile."
        )
        static let addPromptNameLabel = String(
            localized: "profiles.addPrompt.nameLabel",
            defaultValue: "Profile name"
        )
        static let addPromptNamePlaceholder = String(
            localized: "profiles.addPrompt.namePlaceholder",
            defaultValue: "Enter a name"
        )
        static let addPromptCreate = String(
            localized: "profiles.addPrompt.create",
            defaultValue: "Create Profile"
        )
        static let title = String(localized: "profiles.title", defaultValue: "Profiles")
        static let activeProfileSection = String(localized: "profiles.activeProfile.section", defaultValue: "Active Profile")
        static let childName = String(localized: "profiles.childName", defaultValue: "Child name")
        static let birthDate = String(localized: "profiles.birthDate", defaultValue: "Birth date")
        static let choosePhoto = String(localized: "profiles.choosePhoto", defaultValue: "Choose profile photo")
        static let removePhoto = String(localized: "profiles.removePhoto", defaultValue: "Remove profile photo")
        static let cropPhotoTitle = String(localized: "profiles.crop.title", defaultValue: "Crop Photo")
        static let cropPhotoInstruction = String(
            localized: "profiles.crop.instruction",
            defaultValue: "Move and scale to adjust."
        )
        static let photoProcessing = String(
            localized: "profiles.photo.processing",
            defaultValue: "Preparing photo…"
        )

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
        static let homeSection = String(localized: "settings.home.section", defaultValue: "Home")
        static let showRecentActivity = String(
            localized: "settings.home.showRecentActivity",
            defaultValue: "Show recent activity"
        )
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

        static func actionReminderTitle(_ category: String) -> String {
            let format = String(
                localized: "settings.notifications.actionReminder.title",
                defaultValue: "%@ reminders"
            )
            return String(format: format, locale: Locale.current, category)
        }

        static func actionReminderFrequencyDescription(_ hours: Int) -> String {
            if hours == 1 {
                return String(
                    localized: "settings.notifications.actionReminder.frequency.one",
                    defaultValue: "Every hour"
                )
            }

            let format = String(
                localized: "settings.notifications.actionReminder.frequency.other",
                defaultValue: "Every %lld hours"
            )
            return String(format: format, locale: Locale.current, hours)
        }

        static let actionReminderDisabled = String(
            localized: "settings.notifications.actionReminder.disabled",
            defaultValue: "Reminders are turned off for this action."
        )

        enum Privacy {
            static let sectionTitle = String(localized: "settings.privacy.section", defaultValue: "Privacy")
            static let trackActionLocations = String(
                localized: "settings.privacy.trackLocations",
                defaultValue: "Track Action Locations"
            )
            static let trackActionLocationsDescription = String(
                localized: "settings.privacy.trackLocations.description",
                defaultValue: "When enabled, the app saves your precise location (within about 50 meters) with each logged action. You can turn this off anytime."
            )
            static let permissionDenied = String(
                localized: "settings.privacy.trackLocations.denied",
                defaultValue: "Location access denied — tap to open Settings."
            )
            static let openSettings = String(localized: "settings.privacy.openSettings", defaultValue: "Open Settings")
        }

    }

    enum Map {
        static let title = String(localized: "map.title", defaultValue: "Action Map")
        static let actionTypeFilter = String(localized: "map.filter.actionType", defaultValue: "Action type")
        static let dateRangeFilter = String(localized: "map.filter.dateRange", defaultValue: "Date range")
        static let dateRangeFilterButton = String(localized: "map.filter.dateRange.button", defaultValue: "Date filters")
        static let dateRangeFilterTitle = String(localized: "map.filter.dateRange.title", defaultValue: "Filter by date")
        static let startDate = String(localized: "map.filter.startDate", defaultValue: "Start date")
        static let endDate = String(localized: "map.filter.endDate", defaultValue: "End date")
        static let allDates = String(localized: "map.filter.allDates", defaultValue: "All dates")
        static let dateRangeToday = String(localized: "map.filter.dateRange.today", defaultValue: "Today")
        static let dateRangeSevenDays = String(
            localized: "map.filter.dateRange.sevenDays",
            defaultValue: "Last 7 days"
        )
        static let dateRangeThirtyDays = String(
            localized: "map.filter.dateRange.thirtyDays",
            defaultValue: "Last 30 days"
        )
        static let dateRangeFilterToggle = String(
            localized: "map.filter.dateRange.toggle",
            defaultValue: "Filter by date range"
        )
        static let allActions = String(localized: "map.filter.allActions", defaultValue: "All actions")
        static let emptyState = String(localized: "map.emptyState", defaultValue: "No actions match your filters.")
        static let unknownLocation = String(
            localized: "map.unknownLocation",
            defaultValue: "Unknown location"
        )

        static let annotationTypeLabel = String(localized: "map.annotation.type", defaultValue: "Type")
        static let annotationSubtypeLabel = String(localized: "map.annotation.subtype", defaultValue: "Subtype")

        static func annotationLoggedAt(_ value: String) -> String {
            let format = String(localized: "map.annotation.loggedAt", defaultValue: "Logged on %@")
            return String(format: format, locale: Locale.current, value)
        }

        static func annotationAccessibility(_ category: String, _ location: String, _ date: String) -> String {
            let format = String(
                localized: "map.annotation.accessibility",
                defaultValue: "%@ logged at %@ on %@"
            )
            return String(format: format, locale: Locale.current, category, location, date)
        }

        static func clusterDetailTitle(_ count: Int) -> String {
            let format = String(
                localized: "map.cluster.detailTitle",
                defaultValue: "%lld nearby actions"
            )
            return String(format: format, locale: Locale.current, count)
        }

        static func clusterAccessibility(_ count: Int, _ location: String) -> String {
            let format = String(
                localized: "map.cluster.accessibility",
                defaultValue: "%lld actions near %@"
            )
            return String(format: format, locale: Locale.current, count, location)
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

        static func actionReminderTitle(_ category: String) -> String {
            let format = String(localized: "notifications.actionReminder.title", defaultValue: "Log %@")
            return String(format: format, locale: Locale.current, category)
        }

        static func actionReminderMessage(for category: BabyActionCategory, name: String) -> String {
            switch category {
            case .diaper:
                let format = String(
                    localized: "notifications.actionReminder.message.diaper",
                    defaultValue: "It's time to change %@'s diaper."
                )
                return String(format: format, locale: Locale.current, name)
            case .feeding:
                let format = String(
                    localized: "notifications.actionReminder.message.feeding",
                    defaultValue: "It's time to feed %@."
                )
                return String(format: format, locale: Locale.current, name)
            case .sleep:
                let format = String(
                    localized: "notifications.actionReminder.message.sleep",
                    defaultValue: "It's time for %@ to sleep."
                )
                return String(format: format, locale: Locale.current, name)
            }
        }

        static func actionReminderInterval(_ hours: Int) -> String {
            if hours == 1 {
                return String(
                    localized: "notifications.actionReminder.interval.one",
                    defaultValue: "1 hour"
                )
            }

            let format = String(
                localized: "notifications.actionReminder.interval.other",
                defaultValue: "%lld hours"
            )
            return String(format: format, locale: Locale.current, hours)
        }

        static func actionReminderOverviewTitle(_ category: String) -> String {
            let format = String(
                localized: "notifications.actionReminder.overviewTitle",
                defaultValue: "%@ reminder"
            )
            return String(format: format, locale: Locale.current, category)
        }
    }

    enum Menu {
        static let title = String(localized: "menu.title", defaultValue: "Nanny & Me")
        static let subtitle = String(localized: "menu.subtitle", defaultValue: "Quick actions")
        static let allLogs = String(localized: "menu.allLogs", defaultValue: "All Logs")
        static let settings = String(localized: "menu.settings", defaultValue: "Settings")
        static let shareData = String(localized: "menu.shareData", defaultValue: "Share Data")
    }

    enum ShareData {
        static let title = String(localized: "shareData.title", defaultValue: "Share Data")
        static let profileSectionTitle = String(localized: "shareData.profileSection.title", defaultValue: "Active Profile")

        static func profileName(_ name: String) -> String {
            let format = String(localized: "shareData.profileSection.name", defaultValue: "Profile: %@")
            return String(format: format, locale: Locale.current, name)
        }

        static func logCount(_ count: Int) -> String {
            let format = String(localized: "shareData.profileSection.logCount", defaultValue: "Total logs: %lld")
            return String(format: format, locale: Locale.current, count)
        }

        static let exportSectionTitle = String(localized: "shareData.export.title", defaultValue: "Export")
        static let exportButton = String(localized: "shareData.export.button", defaultValue: "Export Data")
        static let exportFooter = String(
            localized: "shareData.export.footer",
            defaultValue: "Save a JSON backup of this profile and its activity logs."
        )

        static let importSectionTitle = String(localized: "shareData.import.title", defaultValue: "Import")
        static let importButton = String(localized: "shareData.import.button", defaultValue: "Import Data")
        static let importFooter = String(
            localized: "shareData.import.footer",
            defaultValue: "Select a previously exported file to merge updates into this profile."
        )

        static func importSummary(_ added: Int, _ updated: Int) -> String {
            let format = String(
                localized: "shareData.import.summary",
                defaultValue: "%lld new entries added • %lld updated"
            )
            return String(format: format, locale: Locale.current, added, updated)
        }

        static let profileUpdatedNote = String(
            localized: "shareData.import.profileUpdated",
            defaultValue: "Profile settings were updated from the import."
        )

        enum AirDrop {
            static let sectionTitle = String(
                localized: "shareData.airdrop.title",
                defaultValue: "Share"
            )
            static let shareButton = String(
                localized: "shareData.airdrop.button",
                defaultValue: "Share Data"
            )
            static let footer = String(
                localized: "shareData.airdrop.footer",
                defaultValue: "Send the exported file to another device over AirDrop."
            )
        }

        enum Alert {
            static let exportSuccessTitle = String(
                localized: "shareData.alert.exportSuccess.title",
                defaultValue: "Export complete"
            )
            static func exportSuccessMessage(_ filename: String) -> String {
                let format = String(
                    localized: "shareData.alert.exportSuccess.message",
                    defaultValue: "Saved file: %@"
                )
                return String(format: format, locale: Locale.current, filename)
            }
            static let exportFailureTitle = String(
                localized: "shareData.alert.exportFailure.title",
                defaultValue: "Export failed"
            )
            static let exportFailureMessage = String(
                localized: "shareData.alert.exportFailure.message",
                defaultValue: "We couldn't save your data. Please try again."
            )
            static let importSuccessTitle = String(
                localized: "shareData.alert.importSuccess.title",
                defaultValue: "Import complete"
            )
            static let importFailureTitle = String(
                localized: "shareData.alert.importFailure.title",
                defaultValue: "Import failed"
            )
            static let airDropFailureTitle = String(
                localized: "shareData.alert.airdropFailure.title",
                defaultValue: "AirDrop failed"
            )
            private static let airDropFailureDefault = String(
                localized: "shareData.alert.airdropFailure.message",
                defaultValue: "AirDrop could not share the export."
            )
            static func airDropFailureMessage(_ reason: String) -> String {
                let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else {
                    return airDropFailureDefault
                }
                let format = String(
                    localized: "shareData.alert.airdropFailure.messageWithReason",
                    defaultValue: "AirDrop could not share the export. (%@)"
                )
                return String(format: format, locale: Locale.current, trimmed)
            }
        }

        enum Error {
            static let mismatchedProfile = String(
                localized: "shareData.error.mismatchedProfile",
                defaultValue: "This file belongs to a different profile. Switch to that profile and try again."
            )
            static let readFailed = String(
                localized: "shareData.error.readFailed",
                defaultValue: "The file could not be read. Make sure you selected a Nanny & Me export."
            )
        }
    }

    enum Logs {
        static let title = String(localized: "logs.title", defaultValue: "All Logs")
        static let emptyTitle = String(localized: "logs.empty.title", defaultValue: "No logs yet")
        static let emptySubtitle = String(localized: "logs.empty.subtitle", defaultValue: "Actions you record will appear here, organized by day.")
        static let active = String(localized: "logs.active", defaultValue: "Active")
        static let deleteConfirmationTitle = String(localized: "logs.delete.confirmationTitle", defaultValue: "Delete log?")
        static let deleteConfirmationMessage = String(
            localized: "logs.delete.confirmationMessage",
            defaultValue: "Are you sure you want to delete this log? This action cannot be undone."
        )
        static let deleteAction = String(localized: "logs.delete.action", defaultValue: "Delete Log")
        static let editAction = String(localized: "logs.edit.action", defaultValue: "Edit Log")
        static let continueAction = String(
            localized: "logs.continue.action",
            defaultValue: "Continue Action"
        )
        static let continueActionInfo = String(
            localized: "logs.continue.info",
            defaultValue: "Resume this action to keep tracking from its original start time."
        )
        static let filterButton = String(localized: "logs.filter.button", defaultValue: "Filter")
        static let filterTitle = String(localized: "logs.filter.title", defaultValue: "Filter Logs")
        static let filterStartToggle = String(localized: "logs.filter.startToggle", defaultValue: "Filter from date")
        static let filterStartLabel = String(localized: "logs.filter.startLabel", defaultValue: "Start date")
        static let filterEndToggle = String(localized: "logs.filter.endToggle", defaultValue: "Filter to date")
        static let filterEndLabel = String(localized: "logs.filter.endLabel", defaultValue: "End date")
        static let filterClear = String(localized: "logs.filter.clear", defaultValue: "Clear Filter")
        static let filterCategorySection = String(
            localized: "logs.filter.category.section",
            defaultValue: "Action type"
        )
        static let filterCategoryAll = String(
            localized: "logs.filter.category.all",
            defaultValue: "All actions"
        )

        static func entryTitle(_ startTime: String, _ duration: String, _ summary: String) -> String {
            let format = String(localized: "logs.entry.title", defaultValue: "%@. %@. %@")
            return String(format: format, locale: Locale.current, startTime, duration, summary)
        }

        static func entryTitleNoDuration(_ startTime: String, _ summary: String) -> String {
            let format = String(localized: "logs.entry.title.noDuration", defaultValue: "%@. %@")
            return String(format: format, locale: Locale.current, startTime, summary)
        }

        static func filterSummaryRange(_ start: String, _ end: String) -> String {
            let format = String(localized: "logs.filter.summary.range", defaultValue: "Showing %@ – %@")
            return String(format: format, locale: Locale.current, start, end)
        }

        static func filterSummaryStart(_ start: String) -> String {
            let format = String(localized: "logs.filter.summary.start", defaultValue: "Showing from %@")
            return String(format: format, locale: Locale.current, start)
        }

        static func filterSummaryEnd(_ end: String) -> String {
            let format = String(localized: "logs.filter.summary.end", defaultValue: "Showing through %@")
            return String(format: format, locale: Locale.current, end)
        }

        static func filterSummaryCategoryOnly(_ category: String) -> String {
            let format = String(localized: "logs.filter.summary.categoryOnly", defaultValue: "Showing %@ logs")
            return String(format: format, locale: Locale.current, category)
        }

        static func filterSummaryCategoryDetail(_ category: String) -> String {
            let format = String(localized: "logs.filter.summary.categoryDetail", defaultValue: "%@ logs")
            return String(format: format, locale: Locale.current, category)
        }

        static func filterSummaryCombined(_ first: String, _ second: String) -> String {
            let format = String(localized: "logs.filter.summary.combined", defaultValue: "%@ · %@")
            return String(format: format, locale: Locale.current, first, second)
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

        static func summaryFeedingBottle(type: String, volume: Int) -> String {
            let format = String(
                localized: "logs.summary.feedingBottleWithTypeAndVolume",
                defaultValue: "feeding - bottle (%1$@, %2$lld ml)"
            )
            return String(format: format, locale: Locale.current, type, volume)
        }

        static func summaryFeedingBottleTypeOnly(_ type: String) -> String {
            let format = String(localized: "logs.summary.feedingBottleWithType", defaultValue: "feeding - bottle (%@)")
            return String(format: format, locale: Locale.current, type)
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
        static let sleepDurationTitle = String(localized: "stats.card.sleepDuration.title", defaultValue: "Sleep Duration")
        static let sleepDurationSubtitle = String(
            localized: "stats.card.sleepDuration.subtitle",
            defaultValue: "Total rest today"
        )
        static let diaperChangesTitle = String(localized: "stats.card.diaperChanges.title", defaultValue: "Diaper Changes")
        static let diaperChangesSubtitle = String(
            localized: "stats.card.diaperChanges.subtitle",
            defaultValue: "Logged today"
        )
        static let diapersYAxis = String(localized: "stats.chart.yAxis.diapers", defaultValue: "Diapers")
        static let minutesYAxis = String(localized: "stats.chart.yAxis.minutes", defaultValue: "Minutes")
        static let secondsYAxis = String(localized: "stats.chart.yAxis.seconds", defaultValue: "Seconds")
        static let hoursYAxis = String(localized: "stats.chart.yAxis.hours", defaultValue: "Hours")
        static let lastSevenDays = String(localized: "stats.chart.lastSevenDays", defaultValue: "Last 7 Days")
        static let actionPickerLabel = String(localized: "stats.chart.actionPicker.label", defaultValue: "Activity")
        static let subtypeLegend = String(localized: "stats.chart.series.subtype", defaultValue: "Subtype")
        static let shareChartButton = String(localized: "stats.chart.share.button", defaultValue: "Share")
        static let shareChartAccessibility = String(
            localized: "stats.chart.share.accessibility",
            defaultValue: "Share chart"
        )
        static let patternTitle = String(
            localized: "stats.pattern.title",
            defaultValue: "Daily Pattern",
            comment: "Heading for the daily pattern chart"
        )
        static let patternSubtitle = String(
            localized: "stats.pattern.subtitle",
            defaultValue: "Typical activity times over the last week."
        )
        static let activityTrendsTitle = String(localized: "stats.chart.activityTrends.title", defaultValue: "Activity Trends")
        static let activityTrendsSubtitle = String(localized: "stats.chart.activityTrends.subtitle", defaultValue: "Once you start logging activities you'll see a weekly breakdown here.")
        static let dayAxisLabel = String(localized: "stats.chart.xAxis.day", defaultValue: "Day")
        static let hourAxisLabel = String(localized: "stats.chart.xAxis.hour", defaultValue: "Hour")

        static func emptyStateTitle(_ focus: String) -> String {
            let format = String(localized: "stats.chart.empty.title", defaultValue: "No %@ logged in the last week.")
            return String(format: format, locale: Locale.current, focus)
        }

        static func emptyStateSubtitle(_ focus: String) -> String {
            let format = String(localized: "stats.chart.empty.subtitle", defaultValue: "Track %@ to see trends over time.")
            return String(format: format, locale: Locale.current, focus)
        }

        static func patternEmptyTitle(_ focus: String) -> String {
            let format = String(localized: "stats.pattern.empty.title", defaultValue: "No clear pattern for %@ yet.")
            return String(format: format, locale: Locale.current, focus)
        }

        static func patternEmptySubtitle(_ focus: String) -> String {
            let format = String(
                localized: "stats.pattern.empty.subtitle",
                defaultValue: "Log more %@ entries to uncover daily trends."
            )
            return String(format: format, locale: Locale.current, focus)
        }

        static let calendarTabLabel = String(localized: "stats.calendar.tabLabel", defaultValue: "Calendar")

        static func calendarSummaryTitle(_ date: String) -> String {
            let format = String(localized: "stats.calendar.summary.title", defaultValue: "Summary for %@")
            return String(format: format, locale: Locale.current, date)
        }

        static func calendarSummaryCount(_ count: Int) -> String {
            if count == 1 {
                return String(localized: "stats.calendar.summary.count.one", defaultValue: "1 log recorded")
            }

            let format = String(localized: "stats.calendar.summary.count", defaultValue: "%lld logs recorded")
            return String(format: format, locale: Locale.current, count)
        }

        static let calendarEmptyTitle = String(
            localized: "stats.calendar.summary.empty",
            defaultValue: "No logs recorded for this day yet."
        )

        static func calendarSleepSubtitle(_ sessions: Int) -> String {
            let format = String(localized: "stats.calendar.sleep.subtitle", defaultValue: "Across %lld sessions")
            return String(format: format, locale: Locale.current, sessions)
        }

        static func calendarFeedingSubtitle(_ volume: Int) -> String {
            let format = String(localized: "stats.calendar.feeding.subtitle", defaultValue: "Bottle total: %lld ml")
            return String(format: format, locale: Locale.current, volume)
        }

        static let calendarFeedingSubtitleNoBottle = String(
            localized: "stats.calendar.feeding.subtitle.noBottle",
            defaultValue: "No bottle feeds logged"
        )

        static let calendarDiaperSubtitle = String(
            localized: "stats.calendar.diaper.subtitle",
            defaultValue: "Changes logged"
        )

        static let calendarTotalTitle = String(
            localized: "stats.calendar.total.title",
            defaultValue: "Total Logs"
        )

        static let calendarTotalSubtitle = String(
            localized: "stats.calendar.total.subtitle",
            defaultValue: "Across all activities"
        )

        static let calendarTimelineTitle = String(
            localized: "stats.calendar.timeline.title",
            defaultValue: "Logged actions"
        )

        static let calendarDurationZero = String(
            localized: "stats.calendar.duration.zero",
            defaultValue: "0m"
        )

        static let calendarDatePickerLabel = String(
            localized: "stats.calendar.datePicker.label",
            defaultValue: "Select a date"
        )
    }

    enum Actions {
        static let sleep = String(localized: "actions.sleep", defaultValue: "Sleep")
        static let diaper = String(localized: "actions.diaper", defaultValue: "Diaper")
        static let feeding = String(localized: "actions.feeding", defaultValue: "Feeding")
        static let diaperChange = String(localized: "actions.diaper.change", defaultValue: "Diaper change")

        static func diaperWithType(_ type: String) -> String {
            let format = String(localized: "actions.diaper.withType", defaultValue: "%@")
            return String(format: format, locale: Locale.current, type)
        }

        static func feedingBottle(_ volume: Int) -> String {
            let format = String(localized: "actions.feeding.bottle", defaultValue: "Bottle (%lld ml)")
            return String(format: format, locale: Locale.current, volume)
        }

        static func feedingBottleWithType(_ type: String, _ volume: Int) -> String {
            let format = String(
                localized: "actions.feeding.bottleWithTypeAndVolume",
                defaultValue: "Bottle (%1$@, %2$lld ml)"
            )
            return String(format: format, locale: Locale.current, type, volume)
        }

        static func feedingBottleWithTypeOnly(_ type: String) -> String {
            let format = String(localized: "actions.feeding.bottleWithType", defaultValue: "Bottle (%@)")
            return String(format: format, locale: Locale.current, type)
        }

        static func feedingWithType(_ type: String) -> String {
            let format = String(localized: "actions.feeding.withType", defaultValue: "%@")
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

    enum BottleType {
        static let formula = String(localized: "feeding.bottleType.formula", defaultValue: "Formula")
        static let breastMilk = String(localized: "feeding.bottleType.breastMilk", defaultValue: "Breast milk")
    }

    enum Profile {
        static let newProfile = String(localized: "profile.new", defaultValue: "New Profile")
    }

    enum Formatter {
        static let justNow = String(localized: "formatter.justNow", defaultValue: "Just now")

        static func ago(_ value: String) -> String {
            let format = String(localized: "formatter.ago", defaultValue: "%@ ago")
            return String(format: format, locale: Locale.current, value)
        }
    }
}
