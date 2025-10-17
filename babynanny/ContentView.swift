//
//  ContentView.swift
//  babynanny
//
//  Created by Luan van der Walt on 2025/10/06.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var profileStore: ProfileStore
    @EnvironmentObject private var shareDataCoordinator: ShareDataCoordinator
    @State private var selectedTab: Tab = .home
    @State private var previousTab: Tab = .home
    @State private var isMenuVisible = false
    @State private var showSettings = false
    @State private var showAllLogs = false
    @State private var showShareProfile = false
    @State private var isProfileSwitcherPresented = false
    @State private var isInitialProfilePromptPresented = false

    var body: some View {
        ZStack(alignment: .leading) {
            NavigationStack {
                VStack(spacing: 0) {
                    AnimatedTabContent(
                        selectedTab: selectedTab,
                        previousTab: previousTab,
                        onShowAllLogs: { showAllLogs = true }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .postHogLabel("tab.swipeContent")
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 30, coordinateSpace: .local)
                            .onEnded { value in
                                let horizontal = value.translation.width
                                let vertical = value.translation.height

                                guard abs(horizontal) > abs(vertical), abs(horizontal) > 40 else { return }

                                if horizontal < 0, let nextTab = selectedTab.next {
                                    Analytics.capture(
                                        "navigation_swipe_tab_content",
                                        properties: [
                                            "direction": "left",
                                            "target_tab": nextTab.analyticsIdentifier,
                                            "previous_tab": selectedTab.analyticsIdentifier
                                        ]
                                    )
                                    let oldValue = selectedTab
                                    previousTab = oldValue
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        selectedTab = nextTab
                                    }
                                } else if horizontal > 0, let previous = selectedTab.previous {
                                    Analytics.capture(
                                        "navigation_swipe_tab_content",
                                        properties: [
                                            "direction": "right",
                                            "target_tab": previous.analyticsIdentifier,
                                            "previous_tab": selectedTab.analyticsIdentifier
                                        ]
                                    )
                                    let oldValue = selectedTab
                                    previousTab = oldValue
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        selectedTab = previous
                                    }
                                }
                            }
                    )

                    Divider()

                    HStack(spacing: 0) {
                        ForEach(Tab.allCases, id: \.self) { tab in
                            VStack(spacing: 4) {
                                Image(systemName: tab.icon)
                                    .font(.system(size: 18, weight: .semibold))

                                Text(tab.title)
                                    .font(.footnote)
                            }
                            .padding(.vertical, 10)
                            .foregroundStyle(selectedTab == tab ? Color.accentColor : Color.secondary)
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                            .phOnTapCapture(
                                event: "navigation_select_tab_tabBar",
                                properties: [
                                    "target_tab": tab.analyticsIdentifier,
                                    "previous_tab": selectedTab.analyticsIdentifier
                                ]
                            ) {
                                guard tab != selectedTab else { return }
                                let oldValue = selectedTab
                                previousTab = oldValue
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    selectedTab = tab
                                }
                            }
                            .postHogLabel(tab.postHogLabel)
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .background(.ultraThinMaterial)
                }
                .disabled(isMenuVisible)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        Text(profileStore.activeProfile.displayName)
                            .font(.headline)
                    }

                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            Analytics.capture(
                                "navigation_toggle_menu_toolbar",
                                properties: ["is_open": isMenuVisible ? "true" : "false"]
                            )
                            withAnimation(.easeInOut) {
                                isMenuVisible.toggle()
                            }
                        } label: {
                            Image(systemName: "line.3.horizontal")
                        }
                        .postHogLabel("toolbar.menu")
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        ProfileAvatarView(imageData: profileStore.activeProfile.imageData, size: 36)
                            .phOnTapCapture(
                                event: "profile_open_switcher_toolbar",
                                properties: [
                                    "profile_id": profileStore.activeProfile.id.uuidString
                                ]
                            ) {
                                isProfileSwitcherPresented = true
                            }
                        .postHogLabel("toolbar.profileSwitcher")
                    }
                }
                .navigationBarTitleDisplayMode(.inline)
                .navigationDestination(isPresented: $showSettings) {
                    SettingsView()
                }
                .navigationDestination(isPresented: $showAllLogs) {
                    AllLogsView()
                }
                .navigationDestination(isPresented: $showShareProfile) {
                    ShareDataPage(profileID: profileStore.activeProfile.id)
                }
                .navigationDestination(
                    isPresented: Binding(
                        get: { shareDataCoordinator.isShowingShareData },
                        set: { shareDataCoordinator.isShowingShareData = $0 }
                    )
                ) {
                    ShareDataView()
                }
            }
            .sheet(isPresented: $isProfileSwitcherPresented) {
                ProfileSwitcherView()
                    .environmentObject(profileStore)
            }

            if isMenuVisible == false {
                Color.clear
                    .frame(width: 24)
                    .contentShape(Rectangle())
                    .ignoresSafeArea(edges: .vertical)
                    .postHogLabel("sideMenu.edgeSwipe")
                    .highPriorityGesture(
                        DragGesture(minimumDistance: 20, coordinateSpace: .local)
                            .onEnded { value in
                                let horizontal = value.translation.width
                                let vertical = value.translation.height

                                guard horizontal > 40, abs(horizontal) > abs(vertical) else { return }

                                Analytics.capture(
                                    "navigation_open_menu_edgeSwipe",
                                    properties: [
                                        "source": "edge_swipe"
                                    ]
                                )

                                withAnimation(.easeInOut) {
                                    isMenuVisible = true
                                }
                            }
                    )
                    .zIndex(3)
            }

            if isMenuVisible {
                Color.black.opacity(0.25)
                    .ignoresSafeArea()
                    .postHogLabel("sideMenu.dismissOverlay")
                    .onTapGesture {
                        Analytics.capture(
                            "navigation_close_menu_overlay",
                            properties: ["was_open": isMenuVisible ? "true" : "false"]
                        )
                        withAnimation(.easeInOut) {
                            isMenuVisible = false
                        }
                    }
                    .zIndex(1)

                SideMenu(
                    onSelectAllLogs: {
                        Analytics.capture("navigation_open_allLogs_menu", properties: ["source": "side_menu"])
                        withAnimation(.easeInOut) {
                            isMenuVisible = false
                            showAllLogs = true
                        }
                    },
                    onSelectShareProfile: {
                        Analytics.capture("navigation_open_shareProfile_menu", properties: ["source": "side_menu"])
                        withAnimation(.easeInOut) {
                            isMenuVisible = false
                            showShareProfile = true
                        }
                    },
                    onSelectSettings: {
                        Analytics.capture("navigation_open_settings_menu", properties: ["source": "side_menu"])
                        withAnimation(.easeInOut) {
                            isMenuVisible = false
                            showSettings = true
                        }
                    },
                    onSelectShareData: {
                        Analytics.capture("navigation_open_shareData_menu", properties: ["source": "side_menu"])
                        withAnimation(.easeInOut) {
                            isMenuVisible = false
                            shareDataCoordinator.presentShareData()
                        }
                    }
                )
                .transition(.move(edge: .leading))
                .zIndex(2)
            }
        }
        .sheet(isPresented: $isInitialProfilePromptPresented) {
            InitialProfileNamePromptView(
                initialName: profileStore.activeProfile.name,
                initialImageData: profileStore.activeProfile.imageData,
                allowsDismissal: profileStore.profiles.count > 1
            ) { newName, imageData in
                let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmedName.isEmpty == false else { return }
                profileStore.updateActiveProfile { profile in
                    profile.name = trimmedName
                    profile.imageData = imageData
                }
                isInitialProfilePromptPresented = false
            }
        }
        .onAppear {
            isInitialProfilePromptPresented = shouldShowInitialProfilePrompt(
                for: profileStore.activeProfile,
                profileCount: profileStore.profiles.count
            )
        }
        .onChange(of: profileStore.activeProfile) { _, profile in
            isInitialProfilePromptPresented = shouldShowInitialProfilePrompt(
                for: profile,
                profileCount: profileStore.profiles.count
            )
        }
        .onChange(of: profileStore.profiles) { _, profiles in
            isInitialProfilePromptPresented = shouldShowInitialProfilePrompt(
                for: profileStore.activeProfile,
                profileCount: profiles.count
            )
        }
    }
}

private struct AnimatedTabContent: View {
    let selectedTab: Tab
    let previousTab: Tab
    let onShowAllLogs: () -> Void

    private var transition: AnyTransition {
        guard selectedTab != previousTab else {
            return .identity
        }

        let isForward = selectedTab.order > previousTab.order

        return .asymmetric(
            insertion: .move(edge: isForward ? .trailing : .leading),
            removal: .move(edge: isForward ? .leading : .trailing)
        )
    }

    var body: some View {
        ZStack {
            switch selectedTab {
            case .home:
                HomeView(onShowAllLogs: onShowAllLogs)
                    .transition(transition)

            case .stats:
                StatsView()
                    .transition(transition)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: selectedTab)
        .background(Color(.systemBackground))
    }
}

private func shouldShowInitialProfilePrompt(for profile: ChildProfile, profileCount: Int) -> Bool {
    profileCount <= 1 && profile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
}

private enum Tab: Hashable, CaseIterable {
    case home
    case stats

    var title: String {
        switch self {
        case .home:
            return L10n.Tab.home
        case .stats:
            return L10n.Tab.stats
        }
    }

    var icon: String {
        switch self {
        case .home:
            return "house"
        case .stats:
            return "chart.bar"
        }
    }

    var order: Int {
        switch self {
        case .home:
            return 0
        case .stats:
            return 1
        }
    }

    var postHogLabel: String {
        switch self {
        case .home:
            return "tab.home"
        case .stats:
            return "tab.stats"
        }
    }

    var analyticsIdentifier: String {
        switch self {
        case .home:
            return "home"
        case .stats:
            return "stats"
        }
    }

    var next: Tab? {
        guard let index = Self.allCases.firstIndex(of: self), index < Self.allCases.count - 1 else {
            return nil
        }
        return Self.allCases[index + 1]
    }

    var previous: Tab? {
        guard let index = Self.allCases.firstIndex(of: self), index > 0 else {
            return nil
        }
        return Self.allCases[index - 1]
    }
}

#Preview {
    let profile = ChildProfile(name: "Aria", birthDate: Date())
    let profileStore = ProfileStore(initialProfiles: [profile], activeProfileID: profile.id, directory: FileManager.default.temporaryDirectory, filename: "previewContentProfiles.json")

    var state = ProfileActionState()
    state.history = [
        BabyAction(category: .feeding, startDate: Date().addingTimeInterval(-3600), endDate: Date().addingTimeInterval(-3300), feedingType: .bottle, bottleType: .formula, bottleVolume: 100)
    ]

    let actionStore = ActionLogStore.previewStore(profiles: [profile.id: state])

    return ContentView()
        .environmentObject(profileStore)
        .environmentObject(actionStore)
        .environmentObject(ShareDataCoordinator())
}
