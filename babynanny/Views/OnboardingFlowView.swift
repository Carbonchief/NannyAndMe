import SwiftUI

struct OnboardingFlowView: View {
    @Binding var isPresented: Bool
    @State private var selection: Page = .welcome
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    private let pages = Page.allCases

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                header
                TabView(selection: $selection) {
                    welcomePage
                        .tag(Page.welcome)

                    benefitsPage
                        .tag(Page.benefits)

                    paywallPage
                        .tag(Page.paywall)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                pageIndicator

                primaryActionButton
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 32)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemBackground).ignoresSafeArea())
        }
        .interactiveDismissDisabled()
    }
}

private extension OnboardingFlowView {
    var header: some View {
        HStack {
            if selection != .welcome {
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        selection = selection.previous()
                    }
                } label: {
                    Text(L10n.Onboarding.FirstLaunch.back)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                .buttonStyle(.plain)
                .postHogLabel("onboarding_back_button_firstLaunch")
            } else {
                Spacer().frame(width: 44)
            }

            Spacer()

            if selection == .paywall {
                Button {
                    completeOnboarding()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .postHogLabel("onboarding_close_button_paywall")
            } else {
                Button {
                    completeOnboarding()
                } label: {
                    Text(L10n.Onboarding.FirstLaunch.skip)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                .buttonStyle(.plain)
                .postHogLabel("onboarding_skip_button_firstLaunch")
            }
        }
    }

    var welcomePage: some View {
        VStack(spacing: 24) {
            Image("Logo")
                .resizable()
                .scaledToFit()
                .frame(width: 120, height: 120)
                .shadow(color: Color.accentColor.opacity(0.1), radius: 16, x: 0, y: 12)
                .accessibilityHidden(true)

            Text(L10n.Onboarding.FirstLaunch.welcomeTitle)
                .font(.largeTitle.weight(.bold))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)

            Text(L10n.Onboarding.FirstLaunch.welcomeMessage)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    var benefitsPage: some View {
        VStack(spacing: 20) {
            Image(systemName: "map.circle")
                .font(.system(size: 64))
                .foregroundStyle(Color.accentColor)
                .symbolRenderingMode(.hierarchical)

            Text(L10n.Onboarding.FirstLaunch.benefitsTitle)
                .font(.largeTitle.weight(.bold))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)

            VStack(spacing: 12) {
                Text(L10n.Onboarding.FirstLaunch.benefitsMessage)
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 10) {
                    benefitRow(icon: "checkmark.seal", text: L10n.Onboarding.FirstLaunch.benefitPointOne)
                    benefitRow(icon: "chart.bar", text: L10n.Onboarding.FirstLaunch.benefitPointTwo)
                }
                .frame(maxWidth: 420)
                .padding(.top, 8)
            }
            .padding(.horizontal, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    var paywallPage: some View {
        VStack(spacing: 24) {
            PaywallCard()

            Text(L10n.Onboarding.FirstLaunch.termsDisclaimer)
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    func benefitRow(icon: String, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 28, height: 28)
            Text(text)
                .font(.body)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var pageIndicator: some View {
        HStack(spacing: 8) {
            ForEach(pages, id: \.self) { page in
                Capsule()
                    .fill(page == selection ? Color.accentColor : Color.accentColor.opacity(0.2))
                    .frame(width: page == selection ? 28 : 12, height: 6)
                    .animation(.easeInOut(duration: 0.2), value: selection)
            }
        }
        .padding(.top, 8)
    }

    var primaryActionButton: some View {
        Button {
            handlePrimaryAction()
        } label: {
            Text(primaryButtonTitle)
                .font(.headline)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Color.accentColor)
                .foregroundStyle(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .postHogLabel(primaryButtonAnalyticsLabel)
    }

    var primaryButtonTitle: String {
        switch selection {
        case .welcome, .benefits:
            return L10n.Onboarding.FirstLaunch.next
        case .paywall:
            return L10n.Onboarding.FirstLaunch.startTrial
        }
    }

    var primaryButtonAnalyticsLabel: String {
        switch selection {
        case .welcome:
            return "onboarding_next_button_welcome"
        case .benefits:
            return "onboarding_next_button_benefits"
        case .paywall:
            return "onboarding_startTrial_button_paywall"
        }
    }

    func handlePrimaryAction() {
        switch selection {
        case .welcome:
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                selection = .benefits
            }
        case .benefits:
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                selection = .paywall
            }
        case .paywall:
            completeOnboarding()
        }
    }

    func completeOnboarding() {
        hasCompletedOnboarding = true
        isPresented = false
    }
}

private struct PaywallCard: View {
    var body: some View {
        VStack(spacing: 24) {
            Image("Logo")
                .resizable()
                .scaledToFit()
                .frame(width: 96, height: 96)
                .shadow(color: Color.accentColor.opacity(0.08), radius: 12, x: 0, y: 8)
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text(L10n.Onboarding.FirstLaunch.paywallTitle)
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)

                Text(L10n.Onboarding.FirstLaunch.paywallSubtitle)
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 12) {
                PaywallFeatureRow(icon: "checkmark.circle.fill", text: L10n.Onboarding.FirstLaunch.paywallFeatureOne)
                PaywallFeatureRow(icon: "checkmark.circle.fill", text: L10n.Onboarding.FirstLaunch.paywallFeatureTwo)
                PaywallFeatureRow(icon: "checkmark.circle.fill", text: L10n.Onboarding.FirstLaunch.paywallFeatureThree)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 12) {
                PaywallPlanRow(
                    title: L10n.Onboarding.FirstLaunch.paywallPlanLifetimeTitle,
                    detail: L10n.Onboarding.FirstLaunch.paywallPlanLifetimePrice,
                    badge: L10n.Onboarding.FirstLaunch.paywallPlanLifetimeBadge,
                    isHighlighted: true
                )

                PaywallPlanRow(
                    title: L10n.Onboarding.FirstLaunch.paywallPlanMonthlyTitle,
                    detail: L10n.Onboarding.FirstLaunch.paywallPlanMonthlyPrice,
                    badge: L10n.Onboarding.FirstLaunch.paywallPlanMonthlyBadge,
                    isHighlighted: false
                )
            }

            VStack(spacing: 8) {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                    Text(L10n.Onboarding.FirstLaunch.paywallFreeTrialToggle)
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                }

                Text(L10n.Onboarding.FirstLaunch.paywallTrialDisclaimer)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.accentColor.opacity(0.08))
            )
        }
        .padding(28)
        .frame(maxWidth: 560)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.08), radius: 28, x: 0, y: 24)
        )
        .accessibilityElement(children: .contain)
    }
}

private struct PaywallFeatureRow: View {
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
        }
        .accessibilityElement(children: .combine)
    }
}

private struct PaywallPlanRow: View {
    let title: String
    let detail: String
    let badge: String
    let isHighlighted: Bool

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(isHighlighted ? Color.white : .primary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    if !badge.isEmpty {
                        Text(badge.uppercased())
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(isHighlighted ? Color.white.opacity(0.16) : Color.accentColor.opacity(0.15))
                            )
                            .foregroundStyle(isHighlighted ? Color.white : Color.accentColor)
                    }
                }

                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(isHighlighted ? Color.white.opacity(0.85) : .secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Image(systemName: isHighlighted ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(isHighlighted ? Color.white : Color.accentColor)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(isHighlighted ? Color.accentColor : Color.accentColor.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.accentColor.opacity(isHighlighted ? 0 : 0.2), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}

private extension OnboardingFlowView {
    enum Page: Int, CaseIterable {
        case welcome
        case benefits
        case paywall

        func previous() -> Page {
            switch self {
            case .welcome:
                return .welcome
            case .benefits:
                return .welcome
            case .paywall:
                return .benefits
            }
        }
    }
}

#Preview {
    OnboardingFlowView(isPresented: .constant(true))
}
