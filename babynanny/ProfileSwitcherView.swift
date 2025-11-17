import SwiftUI

struct ProfileSwitcherView: View {
    @EnvironmentObject private var profileStore: ProfileStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("hasUnlockedPremium") private var hasUnlockedPremium = false
    @StateObject private var paywallViewModel = OnboardingPaywallViewModel()
    @State private var isAddProfilePromptPresented = false
    @State private var isPaywallPresented = false
    @State private var selectedPaywallPlan: PaywallPlan = .trial
    @State private var pendingAddProfileUnlock = false

    var body: some View {
        NavigationStack {
            List {
                Section(header: Text(L10n.Profiles.activeSection)) {
                    ForEach(profileStore.profiles) { profile in
                        let isReadOnly = profile.sharePermission == .view

                        Button {
                            profileStore.setActiveProfile(profile)
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                ProfileAvatarView(imageData: profile.imageData,
                                                  size: 44)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(profile.displayName)
                                        .font(.headline)

                                    Text(profile.birthDate, style: .date)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)

                                    if profile.isShared || isReadOnly {
                                        ProfileAccessBadges(isShared: profile.isShared,
                                                            isReadOnly: isReadOnly)
                                    }
                                }

                                Spacer()

                                if profile.id == profileStore.activeProfileID {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }

                Section {
                    Button {
                        if hasUnlockedPremium || profileStore.profiles.isEmpty {
                            isAddProfilePromptPresented = true
                        } else {
                            pendingAddProfileUnlock = true
                            selectedPaywallPlan = .trial
                            paywallViewModel.errorMessage = nil
                            isPaywallPresented = true
                        }
                    } label: {
                        Label(L10n.Profiles.addProfile, systemImage: "plus")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(L10n.Profiles.title)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.Common.done) {
                        dismiss()
                    }
                }
            }
        }
        .sheet(isPresented: $isAddProfilePromptPresented) {
            AddProfilePromptView { name, birthDate, imageData in
                profileStore.addProfile(name: name, birthDate: birthDate, imageData: imageData)
            }
        }
        .sheet(isPresented: $isPaywallPresented, onDismiss: {
            if !hasUnlockedPremium {
                pendingAddProfileUnlock = false
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
                        analyticsLabel: "profileSwitcher_purchase_button_paywall"
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
        .onChange(of: hasUnlockedPremium) { _, newValue in
            if newValue {
                if pendingAddProfileUnlock {
                    pendingAddProfileUnlock = false
                    isAddProfilePromptPresented = true
                }
                isPaywallPresented = false
            } else {
                pendingAddProfileUnlock = false
            }
        }
        .presentationDetents([.medium, .large])
    }
}

struct ProfileAccessBadges: View {
    let isShared: Bool
    let isReadOnly: Bool

    var body: some View {
        HStack(spacing: 6) {
            if isShared {
                badge(text: L10n.Profiles.sharedBadge, color: .blue)
            }
            if isReadOnly {
                badge(text: L10n.Profiles.viewOnlyBadge, color: .orange)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func badge(text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(color)
            .background(
                Capsule()
                    .fill(color.opacity(0.15))
            )
    }
}

#Preview {
    ProfileSwitcherView()
        .environmentObject(ProfileStore.preview)
}
