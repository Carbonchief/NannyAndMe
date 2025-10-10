//
//  ContentView.swift
//  babynanny
//
//  Created by Luan van der Walt on 2025/10/06.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var profileStore: ProfileStore
    @State private var selectedTab: Tab = .home
    @State private var previousTab: Tab = .home
    @State private var isMenuVisible = false
    @State private var showSettings = false
    @State private var showAllLogs = false
    @State private var showShareData = false
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

                    Divider()

                    HStack(spacing: 0) {
                        ForEach(Tab.allCases, id: \.self) { tab in
                            Button {
                                guard tab != selectedTab else { return }
                                let oldValue = selectedTab
                                previousTab = oldValue
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    selectedTab = tab
                                }
                            } label: {
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
                            }
                            .buttonStyle(.plain)
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
                            withAnimation(.easeInOut) {
                                isMenuVisible.toggle()
                            }
                        } label: {
                            Image(systemName: "line.3.horizontal")
                        }
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            isProfileSwitcherPresented = true
                        } label: {
                            ProfileAvatarView(imageData: profileStore.activeProfile.imageData, size: 36)
                        }
                    }
                }
                .navigationDestination(isPresented: $showSettings) {
                    SettingsView()
                }
                .navigationDestination(isPresented: $showAllLogs) {
                    AllLogsView()
                }
                .navigationDestination(isPresented: $showShareData) {
                    ShareDataView()
                }
            }
            .sheet(isPresented: $isProfileSwitcherPresented) {
                ProfileSwitcherView()
                    .environmentObject(profileStore)
            }

            if isMenuVisible {
                Color.black.opacity(0.25)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.easeInOut) {
                            isMenuVisible = false
                        }
                    }
                    .zIndex(1)

                SideMenu(
                    onSelectAllLogs: {
                        withAnimation(.easeInOut) {
                            isMenuVisible = false
                            showAllLogs = true
                        }
                    },
                    onSelectSettings: {
                        withAnimation(.easeInOut) {
                            isMenuVisible = false
                            showSettings = true
                        }
                    },
                    onSelectShareData: {
                        withAnimation(.easeInOut) {
                            isMenuVisible = false
                            showShareData = true
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
                allowsDismissal: profileStore.profiles.count > 1
            ) { newName in
                let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmedName.isEmpty == false else { return }
                profileStore.updateActiveProfile { profile in
                    profile.name = trimmedName
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
}

#Preview {
    let profile = ChildProfile(name: "Aria", birthDate: Date())
    let profileStore = ProfileStore(initialProfiles: [profile], activeProfileID: profile.id, directory: FileManager.default.temporaryDirectory, filename: "previewContentProfiles.json")

    var state = ProfileActionState()
    state.history = [
        BabyAction(category: .feeding, startDate: Date().addingTimeInterval(-3600), endDate: Date().addingTimeInterval(-3300), feedingType: .bottle, bottleVolume: 100)
    ]

    let actionStore = ActionLogStore.previewStore(profiles: [profile.id: state])

    return ContentView()
        .environmentObject(profileStore)
        .environmentObject(actionStore)
}
