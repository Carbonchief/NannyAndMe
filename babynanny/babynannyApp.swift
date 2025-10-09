//
//  babynannyApp.swift
//  babynanny
//
//  Created by Luan van der Walt on 2025/10/06.
//

import SwiftUI
import GoogleMobileAds

@main
struct babynannyApp: App {
    @StateObject private var profileStore: ProfileStore
    @StateObject private var actionStore: ActionLogStore

    init() {
        let mobileAds = GADMobileAds.sharedInstance()
        mobileAds.start(completionHandler: nil)
#if targetEnvironment(simulator)
        mobileAds.requestConfiguration.testDeviceIdentifiers = [GADSimulatorID]
#endif

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
