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

                if selection == .paywall {
                    Button {
                        completeOnboarding()
                    } label: {
                        Text(L10n.Onboarding.FirstLaunch.maybeLater)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .postHogLabel("onboarding_maybeLater_button_firstLaunch")
                }
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

            if selection != .paywall {
                Button {
                    completeOnboarding()
                } label: {
                    Text(L10n.Onboarding.FirstLaunch.skip)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                .buttonStyle(.plain)
                .postHogLabel("onboarding_skip_button_firstLaunch")
            } else {
                Spacer().frame(width: 44)
            }
        }
    }

    var welcomePage: some View {
        VStack(spacing: 20) {
            Image(systemName: "sparkles")
                .font(.system(size: 64))
                .foregroundStyle(Color.accentColor)
                .symbolRenderingMode(.hierarchical)

            Text(L10n.Onboarding.FirstLaunch.welcomeTitle)
                .font(.largeTitle.weight(.bold))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)

            Text(L10n.Onboarding.FirstLaunch.welcomeMessage)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    var benefitsPage: some View {
        VStack(spacing: 20) {
            Image(systemName: "chart.line.uptrend.xyaxis")
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
                    benefitRow(icon: "bell.badge", text: L10n.Onboarding.FirstLaunch.benefitPointTwo)
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
            Image(systemName: "creditcard")
                .font(.system(size: 64))
                .foregroundStyle(Color.accentColor)
                .symbolRenderingMode(.hierarchical)

            Text(L10n.Onboarding.FirstLaunch.paywallTitle)
                .font(.largeTitle.weight(.bold))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)

            Text(L10n.Onboarding.FirstLaunch.paywallSubtitle)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)

            VStack(alignment: .leading, spacing: 12) {
                benefitRow(icon: "infinity", text: L10n.Onboarding.FirstLaunch.paywallFeatureOne)
                benefitRow(icon: "arrow.triangle.2.circlepath", text: L10n.Onboarding.FirstLaunch.paywallFeatureTwo)
                benefitRow(icon: "person.2.badge.gearshape", text: L10n.Onboarding.FirstLaunch.paywallFeatureThree)
            }
            .frame(maxWidth: 420)

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
