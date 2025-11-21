import SwiftUI

/// A simple flow for updating a Supabase password after a recovery link is confirmed.
struct PasswordChangeView: View {
    @EnvironmentObject private var authManager: SupabaseAuthManager
    @Environment(\.dismiss) private var dismiss

    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case newPassword
        case confirmPassword
    }

    var body: some View {
        NavigationStack {
            Form {
                if let error = authManager.lastErrorMessage {
                    statusMessage(text: error, tint: .red, systemImage: "exclamationmark.triangle.fill")
                }

                if let info = authManager.infoMessage {
                    statusMessage(text: info, tint: .green, systemImage: "checkmark.circle.fill")
                }

                Section {
                    Text(L10n.Auth.passwordChangeDescription)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Section(footer: Text(L10n.Auth.passwordHint)) {
                    SecureField(L10n.Auth.passwordChangeNewPassword, text: $newPassword)
                        .textContentType(.newPassword)
                        .focused($focusedField, equals: .newPassword)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .confirmPassword }

                    SecureField(L10n.Auth.passwordChangeConfirmPassword, text: $confirmPassword)
                        .textContentType(.newPassword)
                        .focused($focusedField, equals: .confirmPassword)
                        .submitLabel(.done)
                        .onSubmit(submitPasswordChange)
                }

                Section {
                    Button(action: submitPasswordChange) {
                        if authManager.isLoading {
                            ProgressView()
                        } else {
                            Text(L10n.Auth.passwordChangeCTA)
                                .font(.headline)
                        }
                    }
                    .disabled(isSubmitDisabled)
                }
            }
            .navigationTitle(L10n.Auth.passwordChangeTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.Common.cancel) {
                        authManager.clearMessages()
                        authManager.dismissPasswordChangeRequirement()
                        dismiss()
                    }
                }
            }
            .onAppear { authManager.clearMessages() }
        }
    }

    private var sanitizedNewPassword: String {
        newPassword.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var sanitizedConfirmPassword: String {
        confirmPassword.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSubmitDisabled: Bool {
        sanitizedNewPassword.isEmpty || sanitizedConfirmPassword.isEmpty || authManager.isLoading
    }

    private func submitPasswordChange() {
        guard sanitizedNewPassword == sanitizedConfirmPassword else {
            authManager.lastErrorMessage = L10n.Auth.passwordChangeMismatch
            return
        }

        guard sanitizedNewPassword.count >= 6 else {
            authManager.lastErrorMessage = L10n.Auth.passwordChangeRequirement
            return
        }

        let password = sanitizedNewPassword
        Task { @MainActor in
            if await authManager.changePassword(to: password) {
                dismiss()
            }
        }
    }

    private func statusMessage(text: String, tint: Color, systemImage: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)

            Text(text)
                .foregroundStyle(.primary)
                .font(.subheadline)
        }
        .padding(.vertical, 6)
    }
}

#Preview {
    PasswordChangeView()
        .environmentObject(SupabaseAuthManager())
}
