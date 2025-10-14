//
//  babynannyApp.swift
//  babynanny
//
//  Created by Luan van der Walt on 2025/10/06.
//

import PostHog
import SwiftUI
import UIKit

@main
struct babynannyApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var profileStore: ProfileStore
    @StateObject private var actionStore: ActionLogStore

    init() {
        let scheduler = UserNotificationReminderScheduler()
        let profileStore = ProfileStore(reminderScheduler: scheduler)
        let actionStore = ActionLogStore(reminderScheduler: scheduler)
        profileStore.registerActionStore(actionStore)
        actionStore.registerProfileStore(profileStore)
        _profileStore = StateObject(wrappedValue: profileStore)
        _actionStore = StateObject(wrappedValue: actionStore)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(profileStore)
                .environmentObject(actionStore)
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _: UIApplication,
        didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let POSTHOG_API_KEY = "phc_LnHkvLd42Z0HUUa1DWyq7fGkrDXoXzKO2AuORKfqqwP"
        let POSTHOG_HOST = "https://eu.i.posthog.com"

        let config = PostHogConfig(apiKey: POSTHOG_API_KEY, host: POSTHOG_HOST)

        PostHogSDK.shared.setup(config)

        return true
    }
}
