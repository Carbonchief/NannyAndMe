import Foundation
import RevenueCat
import RevenueCatCustomerCenter
import RevenueCatUI
import SwiftUI
import UIKit

@MainActor
final class RevenueCatSubscriptionService: NSObject, ObservableObject, PurchasesDelegate {
    static let entitlementID = "Nanny & Me Pro"

    @Published private(set) var customerInfo: CustomerInfo?
    @Published private(set) var offerings: Offerings?
    @Published private(set) var isLoadingOfferings = false
    @Published private(set) var isRestoringPurchases = false
    @Published private(set) var lastError: Error?

    var hasProAccess: Bool {
        customerInfo?.entitlements[Self.entitlementID]?.isActive == true
    }

    override init() {
        super.init()
        Purchases.shared.delegate = self
        Task {
            await refreshCustomerInfo()
            await refreshOfferings()
        }
    }

    func refreshCustomerInfo() async {
        do {
            customerInfo = try await Purchases.shared.customerInfo()
            lastError = nil
        } catch {
            lastError = error
        }
    }

    func refreshOfferings() async {
        guard isLoadingOfferings == false else { return }
        isLoadingOfferings = true
        defer { isLoadingOfferings = false }

        do {
            offerings = try await Purchases.shared.offerings()
            lastError = nil
        } catch {
            lastError = error
        }
    }

    func restorePurchases() async {
        guard isRestoringPurchases == false else { return }
        isRestoringPurchases = true
        defer { isRestoringPurchases = false }

        do {
            customerInfo = try await Purchases.shared.restorePurchases()
            lastError = nil
        } catch {
            lastError = error
        }
    }

    func logInIfNeeded(appUserID: String) async {
        guard Purchases.shared.appUserID != appUserID else { return }
        do {
            let result = try await Purchases.shared.logIn(appUserID)
            customerInfo = result.customerInfo
            lastError = nil
        } catch {
            lastError = error
        }
    }

    func logOutIfNeeded() async {
        do {
            let result = try await Purchases.shared.logOut()
            customerInfo = result
            lastError = nil
        } catch {
            lastError = error
        }
    }

    func presentCustomerCenter(from scene: UIWindowScene) async {
        guard let controller = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController else { return }

        do {
            try await CustomerCenter.present(from: controller)
            lastError = nil
        } catch {
            lastError = error
        }
    }

    func clearError() {
        lastError = nil
    }

    nonisolated func purchases(_ purchases: Purchases, receivedUpdated customerInfo: CustomerInfo) {
        Task { @MainActor in
            self.customerInfo = customerInfo
        }
    }
}

