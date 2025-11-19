import RevenueCatUI
import SwiftUI

struct RevenueCatPaywallContainer: View {
    @EnvironmentObject private var subscriptionService: RevenueCatSubscriptionService
    let onDismiss: (() -> Void)?

    init(onDismiss: (() -> Void)? = nil) {
        self.onDismiss = onDismiss
    }

    var body: some View {
        VStack {
            if let offering = subscriptionService.offerings?.current {
                ZStack(alignment: .topTrailing) {
                    PaywallView(offering: offering)

                    if let onDismiss {
                        Button {
                            onDismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Color.secondary)
                                .padding(8)
                                .background(
                                    Circle()
                                        .fill(Color(.systemBackground))
                                        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
                                )
                        }
                        .buttonStyle(.plain)
                        .padding(12)
                    }
                }
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
