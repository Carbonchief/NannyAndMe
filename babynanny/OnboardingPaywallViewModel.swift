import Foundation
import StoreKit
import os

/// Handles StoreKit interactions for the onboarding paywall.
@MainActor
final class OnboardingPaywallViewModel: ObservableObject {
    @Published private(set) var products: [PaywallPlan: Product] = [:]
    @Published private(set) var isLoadingProducts = false
    @Published private(set) var isProcessingPurchase = false
    @Published private(set) var isRestoringPurchases = false
    @Published private(set) var hasUnlockedPremium = false
    @Published var errorMessage: String?

    private let logger = Logger(subsystem: "com.prioritybit.babynanny", category: "paywall")
    private var transactionUpdatesTask: Task<Void, Never>?

    init() {
        transactionUpdatesTask = Task { [weak self] in
            await self?.observeTransactionUpdates()
        }

        Task { [weak self] in
            await self?.refreshEntitlements()
        }
    }

    deinit {
        transactionUpdatesTask?.cancel()
    }

    func loadProductsIfNeeded() async {
        if isLoadingProducts || products.count == PaywallPlan.allCases.count {
            return
        }

        isLoadingProducts = true
        defer { isLoadingProducts = false }

        do {
            let identifiers = PaywallPlan.allCases.map(\.productID)
            let storeProducts = try await Product.products(for: identifiers)

            var resolvedProducts = products
            var didResolveNewPlan = false
            for product in storeProducts {
                guard let plan = PaywallPlan(productID: product.id) else { continue }
                resolvedProducts[plan] = product
                didResolveNewPlan = true
            }

            if resolvedProducts.isEmpty {
                logger.error("StoreKit returned no paywall products")
                errorMessage = L10n.Onboarding.FirstLaunch.paywallErrorGeneric
            } else {
                products = resolvedProducts
                if didResolveNewPlan {
                    errorMessage = nil
                }
            }
        } catch {
            logger.error("Failed to load paywall products: \(error.localizedDescription, privacy: .public)")
            errorMessage = L10n.Onboarding.FirstLaunch.paywallErrorGeneric
        }
    }

    func product(for plan: PaywallPlan) -> Product? {
        products[plan]
    }

    func detailText(for plan: PaywallPlan) -> String {
        guard let product = products[plan] else {
            switch plan {
            case .lifetime:
                return L10n.Onboarding.FirstLaunch.paywallPlanLifetimeFallbackDetail
            case .trial:
                return L10n.Onboarding.FirstLaunch.paywallPlanMonthlyFallbackDetail
            }
        }

        switch plan {
        case .lifetime:
            return L10n.Onboarding.FirstLaunch.paywallPlanLifetimeDetail(product.displayPrice)
        case .trial:
            if let subscription = product.subscription {
                let period = subscriptionPeriodDescription(for: subscription.subscriptionPeriod)
                return L10n.Onboarding.FirstLaunch.paywallPlanMonthlyDetail(product.displayPrice, period)
            }
            return L10n.Onboarding.FirstLaunch.paywallPlanMonthlyFallbackDetail
        }
    }

    func purchase(plan: PaywallPlan) async {
        guard !isProcessingPurchase else { return }

        errorMessage = nil

        if products[plan] == nil {
            await loadProductsIfNeeded()
        }

        guard let product = products[plan] else {
            errorMessage = L10n.Onboarding.FirstLaunch.paywallErrorGeneric
            return
        }

        isProcessingPurchase = true
        defer { isProcessingPurchase = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await handle(transaction)
            case .userCancelled, .pending:
                break
            @unknown default:
                logger.error("Encountered unknown purchase result")
                errorMessage = L10n.Onboarding.FirstLaunch.paywallErrorGeneric
            }
        } catch {
            logger.error("Purchase failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = L10n.Onboarding.FirstLaunch.paywallErrorGeneric
        }
    }

    func restorePurchases() async {
        guard !isRestoringPurchases else { return }

        errorMessage = nil
        isRestoringPurchases = true
        defer { isRestoringPurchases = false }

        do {
            try await AppStore.sync()
            await refreshEntitlements()
        } catch {
            logger.error("Restore failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = L10n.Onboarding.FirstLaunch.paywallErrorGeneric
        }
    }

    func refreshEntitlements() async {
        var unlocked = false

        for await verificationResult in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(verificationResult) else { continue }
            guard PaywallPlan(productID: transaction.productID) != nil else { continue }
            unlocked = true
            break
        }

        hasUnlockedPremium = unlocked
    }

    private func observeTransactionUpdates() async {
        for await verificationResult in Transaction.updates {
            do {
                let transaction = try checkVerified(verificationResult)
                await handle(transaction)
            } catch {
                logger.error("Failed to verify transaction update: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func handle(_ transaction: Transaction) async {
        guard PaywallPlan(productID: transaction.productID) != nil else {
            await transaction.finish()
            return
        }

        errorMessage = nil
        hasUnlockedPremium = true
        await transaction.finish()
    }

    private func checkVerified(_ result: VerificationResult<Transaction>) throws -> Transaction {
        switch result {
        case .verified(let transaction):
            return transaction
        case .unverified(_, let error):
            if let error {
                throw error
            } else {
                throw StoreKitError(.unknown)
            }
        }
    }

    private func subscriptionPeriodDescription(for period: Product.SubscriptionPeriod) -> String {
        var components = DateComponents()
        switch period.unit {
        case .day:
            components.day = period.value
        case .week:
            components.weekOfMonth = period.value
        case .month:
            components.month = period.value
        case .year:
            components.year = period.value
        @unknown default:
            components.day = period.value
        }

        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        formatter.allowedUnits = [.day, .weekOfMonth, .month, .year]
        formatter.maximumUnitCount = 1
        formatter.locale = Locale.current

        return formatter.string(from: components) ?? ""
    }
}
