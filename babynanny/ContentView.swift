//
//  ContentView.swift
//  babynanny
//
//  Created by Luan van der Walt on 2025/10/06.
//

import CoreLocation
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var profileStore: ProfileStore
    @EnvironmentObject private var actionStore: ActionLogStore
    @EnvironmentObject private var shareDataCoordinator: ShareDataCoordinator
    @EnvironmentObject private var authManager: SupabaseAuthManager
    @EnvironmentObject private var locationManager: LocationManager
    @AppStorage("trackActionLocations") private var trackActionLocations = false
    @AppStorage("hasUnlockedPremium") private var hasUnlockedPremium = false
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @StateObject private var paywallViewModel = OnboardingPaywallViewModel()
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
    @State private var isPaywallPresented = false
    @State private var selectedPaywallPlan: PaywallPlan = .trial
    @State private var pendingMapUnlock = false
    @State private var isLocationPromptPresented = false
    @State private var menuDragOffset: CGFloat = 0
    @State private var pendingShareAlertProfile: ChildProfile?
    @State private var shareResponseErrorMessage: String?

    private var visibleTabs: [Tab] {
        return [.home, .reports, .map]
    }

    private var isActiveProfileReadOnly: Bool {
        actionStore.isProfileReadOnly(profileStore.activeProfile.id)
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
                                    activate(tab: nextTab)
                                } else if horizontal > 0, let previous = previousTab(before: selectedTab, in: tabs) {
                                    activate(tab: previous)
                                }
                            }
                    )

                    VStack(spacing: 16) {
                        HStack(spacing: 16) {
                            HStack(spacing: 8) {
                                ForEach(tabs, id: \.self) { tab in
                                    Button {
                                        handleTabTap(tab)
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
                            .disabled(isActiveProfileReadOnly)
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

                        ProfileAvatarView(imageData: profileStore.activeProfile.imageData,
                                          size: 36)
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
            .sheet(isPresented: $isPaywallPresented, onDismiss: {
                if hasUnlockedPremium == false {
                    pendingMapUnlock = false
                }
            }) {
                NavigationStack {
                    PaywallContentView(
                        selectedPlan: $selectedPaywallPlan,
                        viewModel: paywallViewModel,
                        onClose: { isPaywallPresented = false }
                    ) {
                        PaywallPurchaseButton(
                            selectedPlan: $selectedPaywallPlan,
                            viewModel: paywallViewModel,
                            analyticsLabel: "contentView_purchase_button_paywall"
                        )
                        .padding(.top, 12)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                    .background(Color(.systemBackground).ignoresSafeArea())
                }
                .task {
                    await paywallViewModel.loadProductsIfNeeded()
                }
            }
            .sheet(isPresented: $isAuthSheetPresented) {
                SupabaseAuthView()
                    .environmentObject(authManager)
            }
            .fullScreenCover(isPresented: $isOnboardingPresented) {
                OnboardingFlowView(isPresented: $isOnboardingPresented)
            }
            .overlay {
                Color.clear
                    .allowsHitTesting(false)
                    .alert(item: $pendingShareAlertProfile) { profile in
                        Alert(
                            title: Text(L10n.Profiles.pendingShareTitle),
                            message: Text(L10n.Profiles.pendingShareMessage(profile.displayName)),
                            primaryButton: .default(Text(L10n.Profiles.pendingShareAccept)) {
                                handlePendingShareResponse(for: profile, accept: true)
                            },
                            secondaryButton: .destructive(Text(L10n.Profiles.pendingShareDecline)) {
                                handlePendingShareResponse(for: profile, accept: false)
                            }
                        )
                    }
            }
            .overlay {
                Color.clear
                    .allowsHitTesting(false)
                    .alert(
                        L10n.ShareData.Supabase.failureTitle,
                        isPresented: Binding(
                            get: { shareResponseErrorMessage != nil },
                            set: { isPresented in
                                if isPresented == false {
                                    shareResponseErrorMessage = nil
                                }
                            }
                        )
                    ) {
                        Button(L10n.Common.done) {
                            shareResponseErrorMessage = nil
                        }
                    } message: {
                        Text(shareResponseErrorMessage ?? "")
                    }
            }
            .alert(isPresented: $isLocationPromptPresented, content: locationTrackingAlert)
            .onChange(of: authManager.isAuthenticated) { _, isAuthenticated in
                if isAuthenticated {
                    isAuthSheetPresented = false
                    synchronizeSupabaseAccount()
                }
            }
            .onChange(of: shareDataCoordinator.shouldPresentAuthentication) { _, shouldPresent in
                guard shouldPresent else { return }
                isAuthSheetPresented = true
                shareDataCoordinator.clearAuthenticationRequest()
            }

            .task(id: authManager.isAuthenticated) {
                guard authManager.isAuthenticated else { return }
                synchronizeSupabaseAccount()
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
                    if profile.imageData != imageData {
                        profile.imageData = imageData
                        profile.avatarURL = nil
                    }
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
            evaluatePendingShareAlert()
        }
        .onChange(of: profileStore.activeProfile) { _, profile in
            isInitialProfilePromptPresented = shouldShowInitialProfilePrompt(
                for: profile,
                profileCount: profileStore.profiles.count
            )
            triggerPendingShareAlert(for: profile)
        }
        .onChange(of: profileStore.activeProfileID) { _, _ in
            evaluatePendingShareAlert()
        }
        .onChange(of: profileStore.profiles) { _, profiles in
            isInitialProfilePromptPresented = shouldShowInitialProfilePrompt(
                for: profileStore.activeProfile,
                profileCount: profiles.count
            )
            evaluatePendingShareAlert()
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
            synchronizeTrackingPreference(with: locationManager.authorizationStatus)
        }
        .onChange(of: locationManager.authorizationStatus) { _, status in
            synchronizeTrackingPreference(with: status)
        }
        .onChange(of: hasUnlockedPremium) { _, newValue in
            if newValue {
                isPaywallPresented = false
                if pendingMapUnlock {
                    pendingMapUnlock = false
                    activate(tab: .map)
                }
            } else {
                isPaywallPresented = false
                pendingMapUnlock = false
                if selectedTab == .map {
                    let oldValue = selectedTab
                    previousTab = oldValue
                    withAnimation(.easeInOut(duration: 0.3)) {
                        selectedTab = .home
                    }
                }
            }
        }
    }

    private func handleProfileCycle(direction: ProfileNavigationDirection) {
        _ = profileStore.cycleActiveProfile(direction: direction)
    }

    private func synchronizeSupabaseAccount() {
        let currentProfiles = profileStore.profiles

        Task { @MainActor in
            let snapshot = await authManager.synchronizeCaregiverAccount(with: currentProfiles)
            await actionStore.performUserInitiatedRefresh(using: snapshot)
        }
    }

    private func evaluatePendingShareAlert() {
        triggerPendingShareAlert(for: profileStore.activeProfile)
    }

    private func triggerPendingShareAlert(for profile: ChildProfile) {
        if profile.shareStatus == .pending {
            if pendingShareAlertProfile?.id != profile.id {
                pendingShareAlertProfile = profile
            }
        } else if pendingShareAlertProfile?.id == profile.id {
            pendingShareAlertProfile = nil
        }
    }

    private func handlePendingShareResponse(for profile: ChildProfile, accept: Bool) {
        pendingShareAlertProfile = nil
        Task {
            let result = await authManager.respondToShareInvitation(profileID: profile.id, accept: accept)
            await MainActor.run {
                switch result {
                case .success:
                    profileStore.applyShareStatus(accept ? .accepted : .revoked, to: profile.id)
                    synchronizeSupabaseAccount()
                case .failure(let error):
                    shareResponseErrorMessage = error.message
                    triggerPendingShareAlert(for: profile)
                }
            }
        }
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
    func handleTabTap(_ tab: Tab) {
        if tab == selectedTab {
            tabResetID = UUID()
            return
        }

        activate(tab: tab)
    }

    func activate(tab: Tab) {
        guard tab != selectedTab else { return }
        guard canActivate(tab: tab) else { return }

        let oldValue = selectedTab
        previousTab = oldValue
        withAnimation(.easeInOut(duration: 0.3)) {
            selectedTab = tab
        }

        if tab == .map {
            maybePresentLocationPrompt()
        }
    }

    func canActivate(tab: Tab) -> Bool {
        guard tab == .map else { return true }
        guard hasUnlockedPremium else {
            pendingMapUnlock = true
            selectedPaywallPlan = .trial
            paywallViewModel.errorMessage = nil
            isPaywallPresented = true
            return false
        }
        return true
    }

    func maybePresentLocationPrompt() {
        guard trackActionLocations == false else { return }
        guard locationManager.authorizationStatus != .denied,
              locationManager.authorizationStatus != .restricted else { return }
        isLocationPromptPresented = true
    }

    func enableActionLocations() {
        guard hasUnlockedPremium else { return }
        withAnimation {
            trackActionLocations = true
        }
        locationManager.requestPermissionIfNeeded()
        locationManager.ensurePreciseAccuracyIfNeeded()
    }

    func locationTrackingAlert() -> Alert {
        Alert(
            title: Text(L10n.Map.LocationPrompt.title),
            message: Text(L10n.Map.LocationPrompt.message),
            primaryButton: .default(Text(L10n.Map.LocationPrompt.enable)) {
                enableActionLocations()
            },
            secondaryButton: .cancel(Text(L10n.Common.cancel))
        )
    }

    func ensureSelectionIsVisible(in tabs: [Tab]) {
        guard tabs.contains(selectedTab) == false else { return }
        previousTab = tabs.first ?? .home
        if let first = tabs.first {
            selectedTab = first
        } else {
            selectedTab = .home
        }
    }

    func synchronizeTrackingPreference(with status: CLAuthorizationStatus) {
        guard status == .denied || status == .restricted else { return }
        guard trackActionLocations else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            trackActionLocations = false
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
