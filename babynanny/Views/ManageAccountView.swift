//
//  ManageAccountView.swift
//  babynanny
//
//  Created by OpenAI Assistant on 2025/02/07.
//

import SwiftUI

@MainActor
struct ManageAccountView: View {
    @EnvironmentObject private var authManager: SupabaseAuthManager
    @EnvironmentObject private var profileStore: ProfileStore
    @Environment(\.dismiss) private var dismiss
    @State private var isProcessingDeletion = false
    @State private var isConfirmingDeletion = false
    @State private var alertTitle: String?
    @State private var alertMessage: String?
    @State private var shouldDismissAfterAlert = false
    @State private var shouldResetProfilesAfterAlert = false

    var body: some View {
        Form {
            Section(
                header: Text(L10n.ManageAccount.deleteSectionTitle),
                footer: Text(L10n.ManageAccount.deleteDescription)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            ) {
                Button(role: .destructive) {
                    isConfirmingDeletion = true
                } label: {
                    Label(L10n.ManageAccount.deleteAction, systemImage: "trash")
                }
                .disabled(isProcessingDeletion || authManager.isAuthenticated == false)
            }

            if authManager.isAuthenticated {
                Section(header: Text(L10n.ManageAccount.accountSectionTitle)) {
                    Button {
                        AnalyticsTracker.capture("logout_tap")
                        Task { await authManager.signOut() }
                    } label: {
                        Label(L10n.Menu.logout, systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
        }
        .navigationTitle(L10n.ManageAccount.title)
        .disabled(isProcessingDeletion)
        .toolbar { processingToolbar }
        .alert(isPresented: alertBinding) {
            Alert(
                title: Text(alertTitle ?? ""),
                message: alertMessage.map(Text.init),
                dismissButton: .default(Text(L10n.Common.done)) {
                    alertTitle = nil
                    alertMessage = nil
                    if shouldDismissAfterAlert {
                        if shouldResetProfilesAfterAlert {
                            profileStore.removeAllProfilesAfterAccountDeletion()
                            shouldResetProfilesAfterAlert = false
                        }
                        shouldDismissAfterAlert = false
                        dismiss()
                    }
                }
            )
        }
        .confirmationDialog(
            L10n.ManageAccount.deleteConfirmationTitle,
            isPresented: $isConfirmingDeletion,
            titleVisibility: .visible
        ) {
            Button(L10n.ManageAccount.deleteAction, role: .destructive) {
                performAccountDeletion()
            }
            Button(L10n.Common.cancel, role: .cancel) {
                isConfirmingDeletion = false
            }
        } message: {
            Text(L10n.ManageAccount.deleteConfirmationMessage)
        }
    }

    private var processingToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            if isProcessingDeletion {
                ProgressView()
            }
        }
    }

    private var alertBinding: Binding<Bool> {
        Binding(
            get: { alertTitle != nil },
            set: { shouldShow in
                if shouldShow == false {
                    alertTitle = nil
                    alertMessage = nil
                }
            }
        )
    }

    private func performAccountDeletion() {
        guard isProcessingDeletion == false else { return }

        isProcessingDeletion = true
        isConfirmingDeletion = false
        alertTitle = nil
        alertMessage = nil

        Task {
            let success = await authManager.deleteOwnedAccountData()

            await MainActor.run {
                isProcessingDeletion = false

                if success {
                    alertTitle = L10n.ManageAccount.deleteSuccessTitle
                    alertMessage = L10n.ManageAccount.deleteSuccessMessage
                    shouldDismissAfterAlert = true
                    shouldResetProfilesAfterAlert = true
                } else {
                    alertTitle = L10n.ManageAccount.deleteFailureTitle
                    alertMessage = authManager.lastErrorMessage ?? L10n.ManageAccount.deleteFailureMessage
                    shouldDismissAfterAlert = false
                    shouldResetProfilesAfterAlert = false
                }
            }
        }
    }
}

#Preview {
    let stack = AppDataStack.preview()
    let context = stack.modelContainer.mainContext
    let actionStore = ActionLogStore(modelContext: context, dataStack: stack)
    let profileStore = ProfileStore(modelContext: context, dataStack: stack)
    return NavigationStack {
        ManageAccountView()
            .environmentObject(actionStore)
            .environmentObject(profileStore)
            .environmentObject(SupabaseAuthManager())
    }
}
