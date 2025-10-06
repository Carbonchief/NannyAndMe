//
//  ContentView.swift
//  babynanny
//
//  Created by Luan van der Walt on 2025/10/06.
//

import SwiftUI

struct ContentView: View {
    @State private var selectedTab: Tab = .home
    @State private var isMenuVisible = false
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .leading) {
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

                if isMenuVisible {
                    Color.black.opacity(0.25)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.easeInOut) {
                                isMenuVisible = false
                            }
                        }

                    SideMenu {
                        withAnimation(.easeInOut) {
                            isMenuVisible = false
                            showSettings = true
                        }
                    }
                    .transition(.move(edge: .leading))
                }
            }
            .navigationTitle(selectedTab.title)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        withAnimation(.easeInOut) {
                            isMenuVisible.toggle()
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal")
                    }
                }
            }
            .navigationDestination(isPresented: $showSettings) {
                SettingsView()
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
    ContentView()
        .environmentObject(ProfileStore.preview)
}
