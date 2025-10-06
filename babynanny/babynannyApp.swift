//
//  babynannyApp.swift
//  babynanny
//
//  Created by Luan van der Walt on 2025/10/06.
//

import SwiftUI

@main
struct babynannyApp: App {
    @StateObject private var profileStore = ProfileStore()
    @StateObject private var actionStore = ActionLogStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(profileStore)
                .environmentObject(actionStore)
        }
    }
}
