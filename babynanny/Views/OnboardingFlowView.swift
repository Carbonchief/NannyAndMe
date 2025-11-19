import SwiftUI

struct OnboardingFlowView: View {
    @Binding var isPresented: Bool
    @EnvironmentObject private var authManager: SupabaseAuthManager
    @EnvironmentObject private var subscriptionService: RevenueCatSubscriptionService
    @State private var selection: Page = .welcome
    @State private var showAccountDecisionPage = true
    @State private var isAuthSheetPresented = false
    @State private var hasInitializedSelection = false
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                TabView(selection: $selection) {
                    welcomePage
                        .tag(Page.welcome)

                    benefitsPage
                        .tag(Page.benefits)

                    if showAccountDecisionPage {
                        accountDecisionPage
                            .tag(Page.accountDecision)
                    }

                    if showAccountDecisionPage == false || selection == .paywall {
                        paywallPage
                            .tag(Page.paywall)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                pageIndicator

                if selection == .accountDecision {
                    accountDecisionActions
                } else {
                    primaryActionButton
                }
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemBackground).ignoresSafeArea())
        }
        .interactiveDismissDisabled()
        .onAppear {
            guard hasInitializedSelection == false else { return }
            hasInitializedSelection = true
            configureInitialSelection()
        }
        .onChange(of: subscriptionService.hasProAccess) { _, newValue in
            guard newValue else { return }
            completeOnboarding()
        }
        .onChange(of: authManager.isAuthenticated) { _, isAuthenticated in
            guard isAuthenticated else { return }
            Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                await MainActor.run {
                    isAuthSheetPresented = false
                    advancePastAccountDecision()
                }
            }
        }
        .sheet(isPresented: $isAuthSheetPresented) {
            SupabaseAuthView()
                .environmentObject(authManager)
        }
    }
}

private extension OnboardingFlowView {
    var pages: [Page] {
        var result: [Page] = [.welcome, .benefits]
        if showAccountDecisionPage {
            result.append(.accountDecision)
        } else {
            result.append(.paywall)
        }
        return result
    }

    var accountDecisionPage: some View {
        GeometryReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    Image(systemName: "person.crop.circle.badge.checkmark")
                        .font(.system(size: 64))
                        .foregroundStyle(Color.accentColor)
                        .symbolRenderingMode(.hierarchical)

                    Text(L10n.Onboarding.FirstLaunch.accountDecisionTitle)
                        .font(.largeTitle.weight(.bold))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)

                    Text(L10n.Onboarding.FirstLaunch.accountDecisionMessage)
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
        RevenueCatPaywallContainer {
            completeOnboarding()
        }
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

    var accountDecisionActions: some View {
        VStack(spacing: 12) {
            Button {
                isAuthSheetPresented = true
            } label: {
                Text(L10n.Onboarding.FirstLaunch.accountDecisionCreateAccount)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
            }
            .frame(height: 48)
            .background(Color.accentColor)
            .foregroundStyle(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .buttonStyle(.plain)

            Button {
                advancePastAccountDecision()
            } label: {
                Text(L10n.Onboarding.FirstLaunch.accountDecisionStayLocal)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
            }
            .frame(height: 48)
            .foregroundStyle(Color.accentColor)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.accentColor.opacity(0.4), lineWidth: 1)
            )
            .buttonStyle(.plain)

            Text(L10n.Onboarding.FirstLaunch.accountDecisionFootnote)
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
    }

    var primaryActionButton: some View {
        Button {
            handlePrimaryAction()
        } label: {
            ZStack {
                Text(primaryButtonTitle)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
            }
            .frame(height: 48)
            .background(Color.accentColor)
            .foregroundStyle(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    var primaryButtonTitle: String {
        switch selection {
        case .accountDecision:
            return L10n.Onboarding.FirstLaunch.accountDecisionStayLocal
        case .welcome, .benefits:
            return L10n.Onboarding.FirstLaunch.next
        case .paywall:
            return L10n.Onboarding.FirstLaunch.maybeLater
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
                if showAccountDecisionPage {
                    selection = .accountDecision
                } else {
                    selection = .paywall
                }
            }
        case .accountDecision:
            advancePastAccountDecision()
        case .paywall:
            completeOnboarding()
        }
    }

    func completeOnboarding() {
        hasCompletedOnboarding = true
        isPresented = false
    }

    func configureInitialSelection() {
        selection = .welcome
        showAccountDecisionPage = authManager.isAuthenticated == false
    }

    func advancePastAccountDecision() {
        guard showAccountDecisionPage else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            showAccountDecisionPage = false
        }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            selection = .paywall
        }
    }
}

private extension OnboardingFlowView {
    enum Page: Int, CaseIterable {
        case welcome
        case benefits
        case accountDecision
        case paywall

        func previous() -> Page {
            switch self {
            case .welcome:
                return .welcome
            case .benefits:
                return .welcome
            case .accountDecision:
                return .benefits
            case .paywall:
                return .accountDecision
            }
        }
    }
}

#Preview {
    OnboardingFlowView(isPresented: .constant(true))
        .environmentObject(SupabaseAuthManager())
        .environmentObject(RevenueCatSubscriptionService())
}
