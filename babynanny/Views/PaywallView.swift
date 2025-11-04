import SwiftUI

struct PaywallContentView<Footer: View>: View {
    @Binding var selectedPlan: PaywallPlan
    @ObservedObject var viewModel: OnboardingPaywallViewModel
    let onClose: () -> Void
    private let footer: Footer

    init(
        selectedPlan: Binding<PaywallPlan>,
        viewModel: OnboardingPaywallViewModel,
        onClose: @escaping () -> Void,
        @ViewBuilder footer: () -> Footer = { EmptyView() }
    ) {
        self._selectedPlan = selectedPlan
        self.viewModel = viewModel
        self.onClose = onClose
        self.footer = footer()
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    PaywallCard(
                        selectedPlan: $selectedPlan,
                        viewModel: viewModel,
                        onClose: onClose
                    )

                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(Color.red)
                            .padding(.horizontal, 12)
                    }

                    Text(L10n.Onboarding.FirstLaunch.termsDisclaimer)
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)

                    footer
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 12)
                .padding(.bottom, 36)
            }
            .frame(width: proxy.size.width)
            .frame(minHeight: proxy.size.height, alignment: .top)
        }
    }
}

struct PaywallCard: View {
    @Binding var selectedPlan: PaywallPlan
    @ObservedObject var viewModel: OnboardingPaywallViewModel
    let onClose: () -> Void

    var body: some View {
        let isTrialSelected = selectedPlan == .trial

        VStack(spacing: 16) {
            ZStack(alignment: .topTrailing) {
                Image(.logo)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 96, height: 96)
                    .shadow(color: Color.accentColor.opacity(0.08), radius: 12, x: 0, y: 8)
                    .frame(maxWidth: .infinity)
                    .accessibilityHidden(true)

                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.secondary)
                        .padding(5)
                        .background(
                            Circle()
                                .fill(Color(.systemBackground))
                                .shadow(color: Color.black.opacity(0.05), radius: 3, x: 0, y: 2)
                        )
                }
                .buttonStyle(.plain)
                .contentShape(Circle())
            }

            VStack(spacing: 6) {
                Text(L10n.Onboarding.FirstLaunch.paywallTitle)
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)

                Text(L10n.Onboarding.FirstLaunch.paywallSubtitle)
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .center, spacing: 12) {
                PaywallFeatureRow(icon: "map.circle.fill", text: L10n.Onboarding.FirstLaunch.paywallFeatureTwo)
                PaywallFeatureRow(icon: "person.2.fill", text: L10n.Onboarding.FirstLaunch.paywallFeatureThree)
                PaywallFeatureRow(icon: "bell.badge.fill", text: L10n.Onboarding.FirstLaunch.paywallFeatureFour)
                PaywallFeatureRow(icon: "lock.open.fill", text: L10n.Onboarding.FirstLaunch.paywallFeatureFive)
            }
            .frame(maxWidth: .infinity, alignment: .center)

            if viewModel.isLoadingProducts {
                ProgressView {
                    Text(L10n.Onboarding.FirstLaunch.paywallLoading)
                }
                .progressViewStyle(.circular)
                .tint(Color.accentColor)
                .padding(.vertical, 8)
            }

            VStack(spacing: 8) {
                PaywallPlanRow(
                    plan: .lifetime,
                    title: L10n.Onboarding.FirstLaunch.paywallPlanLifetimeTitle,
                    detail: viewModel.detailText(for: .lifetime),
                    badge: L10n.Onboarding.FirstLaunch.paywallPlanLifetimeBadge,
                    isSelected: selectedPlan == .lifetime,
                    action: {
                        selectedPlan = .lifetime
                    }
                )

                PaywallPlanRow(
                    plan: .trial,
                    title: L10n.Onboarding.FirstLaunch.paywallPlanMonthlyTitle,
                    detail: viewModel.detailText(for: .trial),
                    badge: L10n.Onboarding.FirstLaunch.paywallPlanMonthlyBadge,
                    isSelected: selectedPlan == .trial,
                    action: {
                        selectedPlan = .trial
                    }
                )
            }

            VStack(spacing: 8) {
                HStack {
                    Image(systemName: isTrialSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isTrialSelected ? Color.accentColor : Color.secondary)
                    Text(L10n.Onboarding.FirstLaunch.paywallFreeTrialToggle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isTrialSelected ? Color.primary : .secondary)
                    Spacer()
                }
                if isTrialSelected {
                    Text(L10n.Onboarding.FirstLaunch.paywallTrialDisclaimer)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.accentColor.opacity(0.08))
            )

            Button {
                Task {
                    await viewModel.restorePurchases()
                }
            } label: {
                HStack(spacing: 8) {
                    if viewModel.isRestoringPurchases {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(Color.accentColor)
                    }
                    Text(L10n.Onboarding.FirstLaunch.restorePurchases)
                        .font(.footnote.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
            .padding(.top, 4)
            .disabled(viewModel.isRestoringPurchases)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .center)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.08), radius: 28, x: 0, y: 24)
        )
        .accessibilityElement(children: .contain)
    }
}

struct PaywallFeatureRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            Text(text)
                .font(.body)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

struct PaywallPlanRow: View {
    let plan: PaywallPlan
    let title: String
    let detail: String
    let badge: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(isSelected ? Color.white : .primary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(detail)
                        .font(.body)
                        .foregroundStyle(isSelected ? Color.white.opacity(0.85) : .secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                HStack(spacing: 8) {
                    if !badge.isEmpty {
                        Text(badge.uppercased())
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color.orange.opacity(isSelected ? 0.2 : 0.15))
                            )
                            .foregroundStyle(isSelected ? Color.white : Color.orange)
                    }

                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(isSelected ? Color.white : Color.accentColor)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(isSelected ? Color.accentColor : Color.accentColor.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.accentColor.opacity(isSelected ? 0 : 0.2), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct PaywallPurchaseButton: View {
    @Binding var selectedPlan: PaywallPlan
    @ObservedObject var viewModel: OnboardingPaywallViewModel
    let analyticsLabel: String

    var body: some View {
        Button {
            Task {
                await viewModel.purchase(plan: selectedPlan)
            }
        } label: {
            ZStack {
                if viewModel.isProcessingPurchase {
                    HStack(spacing: 8) {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(Color.white)

                        Text(buttonTitle)
                            .font(.headline)
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    Text(buttonTitle)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 48)
            .background(Color.accentColor)
            .foregroundStyle(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }

    private var buttonTitle: String {
        if viewModel.isProcessingPurchase {
            return L10n.Onboarding.FirstLaunch.processingPurchase
        }

        if selectedPlan == .lifetime {
            return L10n.Onboarding.FirstLaunch.purchaseLifetime
        }

        return L10n.Onboarding.FirstLaunch.startTrial
    }

    private var isDisabled: Bool {
        viewModel.isProcessingPurchase
            || viewModel.isRestoringPurchases
            || viewModel.isLoadingProducts
    }
}

#Preview {
    PaywallContentView(
        selectedPlan: .constant(.trial),
        viewModel: OnboardingPaywallViewModel(),
        onClose: {}
    )
    .padding()
}
