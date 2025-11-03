import Foundation

/// Represents the purchase plans surfaced on the onboarding paywall.
enum PaywallPlan: CaseIterable, Identifiable {
    case lifetime
    case trial

    var id: String {
        switch self {
        case .lifetime:
            return "lifetime"
        case .trial:
            return "trial"
        }
    }

    var productID: String {
        switch self {
        case .lifetime:
            return "NAMlifetime"
        case .trial:
            return "NAMWeekly"
        }
    }

    var analyticsLabel: String {
        switch self {
        case .lifetime:
            return "onboarding_selectPlan_lifetime_paywall"
        case .trial:
            return "onboarding_selectPlan_trial_paywall"
        }
    }

    init?(productID: String) {
        if productID == PaywallPlan.lifetime.productID {
            self = .lifetime
        } else if productID == PaywallPlan.trial.productID {
            self = .trial
        } else {
            return nil
        }
    }
}
