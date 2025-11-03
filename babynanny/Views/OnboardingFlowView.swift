import SwiftUI

struct OnboardingFlowView: View {
    @Binding var isPresented: Bool
    @StateObject private var paywallViewModel = OnboardingPaywallViewModel()
    @State private var selection: Page = .welcome
    @State private var selectedPlan: PaywallPlan = .trial
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("hasUnlockedPremium") private var hasUnlockedPremium = false

    private let pages = Page.allCases

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemBackground).ignoresSafeArea())
        }
        .interactiveDismissDisabled()
        .task {
            await paywallViewModel.loadProductsIfNeeded()
        }
        .onChange(of: paywallViewModel.hasUnlockedPremium) { _, newValue in
            hasUnlockedPremium = newValue
            guard newValue else { return }
            completeOnboarding()
        }
        .onChange(of: selectedPlan) { _, _ in
            paywallViewModel.errorMessage = nil
        }
    }
}

private extension OnboardingFlowView {
    var welcomePage: some View {
        GeometryReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    Image(.logo)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 120, height: 120)
                        .shadow(color: Color.accentColor.opacity(0.1), radius: 16, x: 0, y: 12)
                        .accessibilityHidden(true)

                    Text(L10n.Onboarding.FirstLaunch.welcomeTitle)
                        .font(.largeTitle.weight(.bold))
                        .multilineTextAlignment(.center)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.horizontal, 12)

                    Text(L10n.Onboarding.FirstLaunch.welcomeMessage)
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
            }
            .frame(width: proxy.size.width)
            .frame(minHeight: proxy.size.height, alignment: .top)
        }
    }

    var benefitsPage: some View {
        GeometryReader { proxy in
            ScrollView(showsIndicators: false) {
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
                            benefitRow(icon: "doc.richtext", text: L10n.Onboarding.FirstLaunch.benefitPointTwo)
                            benefitRow(icon: "sparkles", text: L10n.Onboarding.FirstLaunch.benefitPointThree)
                        }
                        .frame(maxWidth: 420)
                        .padding(.top, 8)
                    }
                    .padding(.horizontal, 12)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
            }
            .frame(width: proxy.size.width)
            .frame(minHeight: proxy.size.height, alignment: .top)
        }
    }

    var paywallPage: some View {
        PaywallContentView(
            selectedPlan: $selectedPlan,
            viewModel: paywallViewModel,
            onClose: completeOnboarding
        )
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
            ZStack {
                if selection == .paywall && paywallViewModel.isProcessingPurchase {
                    HStack(spacing: 8) {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(Color.white)

                        Text(primaryButtonTitle)
                            .font(.headline)
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    Text(primaryButtonTitle)
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
        .disabled(isPrimaryButtonDisabled)
        .postHogLabel(primaryButtonAnalyticsLabel)
    }

    var primaryButtonTitle: String {
        switch selection {
        case .welcome, .benefits:
            return L10n.Onboarding.FirstLaunch.next
        case .paywall:
            if paywallViewModel.isProcessingPurchase {
                return L10n.Onboarding.FirstLaunch.processingPurchase
            }
            if selectedPlan == .lifetime {
                return L10n.Onboarding.FirstLaunch.purchaseLifetime
            } else {
                return L10n.Onboarding.FirstLaunch.startTrial
            }
        }
    }

    var isPrimaryButtonDisabled: Bool {
        switch selection {
        case .welcome, .benefits:
            return false
        case .paywall:
            return paywallViewModel.isProcessingPurchase
                || paywallViewModel.isRestoringPurchases
                || paywallViewModel.isLoadingProducts
        }
    }

    var primaryButtonAnalyticsLabel: String {
        switch selection {
        case .welcome:
            return "onboarding_next_button_welcome"
        case .benefits:
            return "onboarding_next_button_benefits"
        case .paywall:
            return selectedPlan.analyticsLabel
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
            Task {
                await paywallViewModel.purchase(plan: selectedPlan)
            }
        }
    }

    func completeOnboarding() {
        hasCompletedOnboarding = true
        isPresented = false
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
