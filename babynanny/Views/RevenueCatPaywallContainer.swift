import RevenueCatUI
import SwiftUI

struct RevenueCatPaywallContainer: View {
    @EnvironmentObject private var subscriptionService: RevenueCatSubscriptionService
    var body: some View {
        VStack {
            if let offering = subscriptionService.offerings?.current {
                PaywallView(offering: offering)
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                    Text(L10n.Settings.Subscription.loadingPaywall)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .task {
                    await subscriptionService.refreshOfferings()
                }
            }
        }
        .interactiveDismissDisabled(false)
        .alert(L10n.Settings.Subscription.errorTitle,
               isPresented: Binding(
                get: { subscriptionService.lastError != nil },
                set: { presented in
                    if presented == false {
                        subscriptionService.clearError()
                    }
                }
               )) {
            Button(L10n.Common.done, role: .cancel) {
                subscriptionService.clearError()
            }
        } message: {
            Text(subscriptionService.lastError?.localizedDescription ?? "")
        }
    }
}
