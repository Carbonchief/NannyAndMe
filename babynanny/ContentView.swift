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
    @State private var isMenuVisible = false
    @State private var showSettings = false
    @State private var isProfileSwitcherPresented = false

    var body: some View {
        ZStack(alignment: .leading) {
            NavigationStack {
                TabView(selection: $selectedTab) {
                    HomeView()
                        .tag(Tab.home)
                        .tabItem {
                            Label("Home", systemImage: Tab.home.icon)
                        }

                    StatsView()
                        .tag(Tab.stats)
                        .tabItem {
                            Label("Stats", systemImage: Tab.stats.icon)
                        }
                }
                .disabled(isMenuVisible)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        VStack(spacing: 2) {
                            Text(profileStore.activeProfile.displayName)
                                .font(.headline)
                            Text(selectedTab.title)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
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

                SideMenu {
                    withAnimation(.easeInOut) {
                        isMenuVisible = false
                        showSettings = true
                    }
                }
                .transition(.move(edge: .leading))
                .zIndex(2)
            }
        }
    }
}

private enum Tab: Hashable {
    case home
    case stats

    var title: String {
        switch self {
        case .home:
            return "Home"
        case .stats:
            return "Stats"
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
}

#Preview {
    ContentView().environmentObject(ProfileStore.preview)

}
