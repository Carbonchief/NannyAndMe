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
    @EnvironmentObject private var authManager: SupabaseAuthManager
    @AppStorage("trackActionLocations") private var trackActionLocations = false
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var selectedTab: Tab = .home
    @State private var previousTab: Tab = .home
    @State private var tabResetID = UUID()
    @State private var isMenuVisible = false
    @State private var showSettings = false
    @State private var showAllLogs = false
    @State private var isProfileSwitcherPresented = false
    @State private var isInitialProfilePromptPresented = false
    @State private var isManualEntryPresented = false
    @State private var isAuthSheetPresented = false
    @State private var isOnboardingPresented = false
    @State private var menuDragOffset: CGFloat = 0

    private var visibleTabs: [Tab] {
        var tabs: [Tab] = [.home, .reports]
        if trackActionLocations {
            tabs.append(.map)
        }
        return tabs
    }

    var body: some View {
        let tabs = visibleTabs

        return ZStack(alignment: .leading) {
            NavigationStack {
                VStack(spacing: 0) {
                    AnimatedTabContent(
                        selectedTab: selectedTab,
                        previousTab: previousTab,
                        tabResetID: tabResetID,
                        onShowAllLogs: { showAllLogs = true }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 30, coordinateSpace: .local)
                            .onEnded { value in
                                let horizontal = value.translation.width
                                let vertical = value.translation.height

                                guard abs(horizontal) > abs(vertical), abs(horizontal) > 40 else { return }

                                if horizontal < 0, let nextTab = nextTab(after: selectedTab, in: tabs) {
                                    let oldValue = selectedTab
                                    previousTab = oldValue
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        selectedTab = nextTab
                                    }
                                } else if horizontal > 0, let previous = previousTab(before: selectedTab, in: tabs) {
                                    let oldValue = selectedTab
                                    previousTab = oldValue
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        selectedTab = previous
                                    }
                                }
                            }
                    )

                    VStack(spacing: 16) {
                        HStack(spacing: 16) {
                            HStack(spacing: 8) {
                                ForEach(tabs, id: \.self) { tab in
                                    Button {
                                        if tab == selectedTab {
                                            tabResetID = UUID()
                                        } else {
                                            let oldValue = selectedTab
                                            previousTab = oldValue
                                            withAnimation(.easeInOut(duration: 0.3)) {
                                                selectedTab = tab
                                            }
                                        }
                                    } label: {
                                        Image(systemName: tab.icon)
                                            .font(.system(size: 18, weight: .semibold))
                                            .frame(maxWidth: .infinity)
                                            .frame(height: 44)
                                            .foregroundStyle(selectedTab == tab ? Color.accentColor : Color.secondary)
                                            .background(
                                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                                    .fill(selectedTab == tab ? Color.accentColor.opacity(0.12) : Color.clear)
                                            )
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(tab.title)
                                    .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(.ultraThinMaterial, in: Capsule())

                            Button {
                                isManualEntryPresented = true
                            } label: {
                                Image(systemName: "plus")
                                    .font(.system(size: 18, weight: .semibold))
                                    .frame(width: 48, height: 48)
                                    .foregroundStyle(Color.accentColor)
                            }
                            .buttonStyle(.plain)
                            .background(.ultraThinMaterial, in: Circle())
                            .accessibilityLabel(L10n.ManualEntry.title)
                            .accessibilityHint(L10n.ManualEntry.accessibilityHint)
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                    }
                    .background(Color(.systemBackground).ignoresSafeArea(edges: .bottom))
                }
                .disabled(isMenuVisible)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        Text(profileStore.activeProfile.displayName)
                            .font(.headline)
                    }

                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            withAnimation(.easeInOut) {
                                isMenuVisible.toggle()
                                menuDragOffset = 0
                            }
                        } label: {
                            Image(systemName: "line.3.horizontal")
                        }
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        let doubleTap = TapGesture(count: 2)
                            .onEnded {
                                handleProfileCycle(direction: .next)
                            }

                        let singleTap = TapGesture()
                            .onEnded {
                                isProfileSwitcherPresented = true
                            }

                        ProfileAvatarView(imageData: profileStore.activeProfile.imageData, size: 36)
                            .contentShape(Rectangle())
                            .gesture(doubleTap.exclusively(before: singleTap))
                            .accessibilityLabel(L10n.Profiles.title)
                            .accessibilityAddTraits(.isButton)
                    }
                }
                .navigationBarTitleDisplayMode(.inline)
                .navigationDestination(isPresented: $showSettings) {
                    SettingsView()
                }
                .navigationDestination(isPresented: $showAllLogs) {
                    AllLogsView()
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
            .sheet(isPresented: $isManualEntryPresented) {
                ManualActionEntrySheet()
            }
            .sheet(isPresented: $isAuthSheetPresented) {
                SupabaseAuthView()
                    .environmentObject(authManager)
            }
            .fullScreenCover(isPresented: $isOnboardingPresented) {
                OnboardingFlowView(isPresented: $isOnboardingPresented)
            }
            .onChange(of: authManager.isAuthenticated) { isAuthenticated in
                if isAuthenticated {
                    isAuthSheetPresented = false
                }
            }

            if isMenuVisible == false {
                Color.clear
                    .frame(width: 24)
                    .contentShape(Rectangle())
                    .ignoresSafeArea(edges: .vertical)
                    .highPriorityGesture(
                        DragGesture(minimumDistance: 20, coordinateSpace: .local)
                            .onEnded { value in
                                let horizontal = value.translation.width
                                let vertical = value.translation.height

                                guard horizontal > 40, abs(horizontal) > abs(vertical) else { return }

                                withAnimation(.easeInOut) {
                                    isMenuVisible = true
                                }
                            }
                    )
                    .zIndex(3)
            }

            if isMenuVisible {
                ZStack(alignment: .leading) {
                    Color.black.opacity(0.25)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.easeInOut) {
                                isMenuVisible = false
                                menuDragOffset = 0
                            }
                        }
                        .zIndex(1)

                    SideMenu(
                        onSelectAllLogs: {
                            withAnimation(.easeInOut) {
                                isMenuVisible = false
                                showAllLogs = true
                                menuDragOffset = 0
                            }
                        },
                        onSelectSettings: {
                            withAnimation(.easeInOut) {
                                isMenuVisible = false
                                showSettings = true
                                menuDragOffset = 0
                            }
                        },
                        onSelectShareData: {
                            withAnimation(.easeInOut) {
                                isMenuVisible = false
                                shareDataCoordinator.presentShareData()
                                menuDragOffset = 0
                            }
                        },
                        onSelectAuthentication: {
                            withAnimation(.easeInOut) {
                                isMenuVisible = false
                                menuDragOffset = 0
                            }
                            isAuthSheetPresented = true
                        }
                    )
                    .offset(x: menuDragOffset)
                    .transition(.move(edge: .leading))
                    .zIndex(2)
                }
                .simultaneousGesture(
                    DragGesture()
                        .onChanged { value in
                            guard isMenuVisible else { return }
                            let horizontal = value.translation.width
                            menuDragOffset = min(0, horizontal)
                        }
                        .onEnded { value in
                            guard isMenuVisible else { return }
                            let horizontal = value.translation.width
                            let dismissThreshold: CGFloat = -80

                            if horizontal <= dismissThreshold {
                                withAnimation(.easeInOut) {
                                    isMenuVisible = false
                                }
                                menuDragOffset = 0
                            } else {
                                withAnimation(.easeInOut) {
                                    menuDragOffset = 0
                                }
                            }
                        }
                )
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
            if hasCompletedOnboarding == false {
                isOnboardingPresented = true
            }
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
        .onChange(of: hasCompletedOnboarding) { _, completed in
            if completed {
                isOnboardingPresented = false
                profileStore.rescheduleRemindersAfterOnboarding()
            }
        }
        .onChange(of: trackActionLocations) { _, _ in
            ensureSelectionIsVisible(in: visibleTabs)
        }
        .onAppear {
            ensureSelectionIsVisible(in: visibleTabs)
        }
    }

    private func handleProfileCycle(direction: ProfileNavigationDirection) {
        _ = profileStore.cycleActiveProfile(direction: direction)
    }
}

private struct AnimatedTabContent: View {
    let selectedTab: Tab
    let previousTab: Tab
    let tabResetID: UUID
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
                HomeView(tabResetID: tabResetID, onShowAllLogs: onShowAllLogs)
                    .transition(transition)

            case .map:
                ActionMapView(tabResetID: tabResetID)
                    .transition(transition)

            case .reports:
                ReportsView(tabResetID: tabResetID)
                    .transition(transition)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: selectedTab)
        .background(Color(.systemBackground))
    }
}

private func shouldShowInitialProfilePrompt(for profile: ChildProfile,
                                            profileCount: Int) -> Bool {
    return profileCount <= 1 && profile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
}

private enum Tab: Hashable, CaseIterable {
    case home
    case map
    case reports

    var title: String {
        switch self {
        case .home:
            return L10n.Tab.home
        case .map:
            return L10n.Tab.map
        case .reports:
            return L10n.Tab.reports
        }
    }

    var icon: String {
        switch self {
        case .home:
            return "house"
        case .map:
            return "map"
        case .reports:
            return "chart.bar"
        }
    }

    var order: Int {
        switch self {
        case .home:
            return 0
        case .reports:
            return 1
        case .map:
            return 2
        }
    }

    var analyticsIdentifier: String {
        switch self {
        case .home:
            return "home"
        case .map:
            return "map"
        case .reports:
            return "reports"
        }
    }
}

private extension ContentView {
    func ensureSelectionIsVisible(in tabs: [Tab]) {
        guard tabs.contains(selectedTab) == false else { return }
        previousTab = tabs.first ?? .home
        if let first = tabs.first {
            selectedTab = first
        } else {
            selectedTab = .home
        }
    }
}

private extension ContentView {
    func nextTab(after tab: Tab, in tabs: [Tab]) -> Tab? {
        guard let index = tabs.firstIndex(of: tab), index < tabs.count - 1 else { return nil }
        return tabs[index + 1]
    }

    func previousTab(before tab: Tab, in tabs: [Tab]) -> Tab? {
        guard let index = tabs.firstIndex(of: tab), index > 0 else { return nil }
        return tabs[index - 1]
    }
}

#Preview {
    let profileStore = ProfileStore.preview
    let profile = profileStore.activeProfile

    var state = ProfileActionState()
    state.history = [
        BabyActionSnapshot(category: .feeding, startDate: Date().addingTimeInterval(-3600), endDate: Date().addingTimeInterval(-3300), feedingType: .bottle, bottleType: .formula, bottleVolume: 100)
    ]

    let actionStore = ActionLogStore.previewStore(profiles: [profile.id: state])

    return ContentView()
        .environmentObject(profileStore)
        .environmentObject(actionStore)
        .environmentObject(ShareDataCoordinator())
        .environmentObject(LocationManager.shared)
}
