import SwiftUI

struct PasswordResetPromptView: View {
    @EnvironmentObject private var authManager: SupabaseAuthManager
    @Environment(\.dismiss) private var dismiss

    let email: String?

    @State private var newPassword = ""
    @FocusState private var isPasswordFieldFocused: Bool

    private var sanitizedPassword: String {
        newPassword.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isUpdateDisabled: Bool {
        sanitizedPassword.count < 6 || authManager.isLoading
    }

    private var promptDescription: String {
        if let email {
            return L10n.Auth.passwordResetPrompt(email)
        }
        return L10n.Auth.passwordResetPromptFallback
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.Auth.passwordResetTitle)
                        .font(.title2.weight(.semibold))

                    Text(promptDescription)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 12) {
                    SecureField(L10n.Auth.newPasswordLabel, text: $newPassword)
                        .textContentType(.newPassword)
                        .focused($isPasswordFieldFocused)
                        .submitLabel(.done)
                        .onSubmit { updatePassword() }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Color(.secondarySystemBackground))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                        )

                    Text(L10n.Auth.passwordHint)
                        .font(.footnote)
                        .foregroundStyle(.primary.opacity(0.7))
                }

                if let message = authManager.lastErrorMessage {
                    messageCard(text: message, tint: .red, systemImage: "exclamationmark.triangle.fill")
                }

                if let info = authManager.infoMessage {
                    messageCard(text: info, tint: .green, systemImage: "checkmark.seal.fill")
                }

                Button(action: updatePassword) {
                    if authManager.isPerformingPasswordReset {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                    } else {
                        Text(L10n.Auth.passwordResetAction)
                            .font(.headline)
                    }
                }
                .frame(maxWidth: .infinity)
                .buttonStyle(.borderedProminent)
                .disabled(isUpdateDisabled)

                Spacer()
            }
            .padding(20)
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.Common.cancel) {
                        authManager.dismissPasswordResetPrompt()
                        dismiss()
                    }
                }
            }
            .onAppear {
                authManager.lastErrorMessage = nil
                isPasswordFieldFocused = true
            }
        }
    }

    private func messageCard(text: String, tint: Color, systemImage: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .font(.title3.weight(.semibold))

            Text(text)
                .font(.callout)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(tint.opacity(0.4), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.15), radius: 12, x: 0, y: 8)
    }

    private func updatePassword() {
        guard isUpdateDisabled == false else { return }
        let password = sanitizedPassword
        Task {
            let success = await authManager.completePasswordReset(newPassword: password)
            if success {
                dismiss()
            }
        }
    }
}

#Preview {
    PasswordResetPromptView(email: "jane@example.com")
        .environmentObject(SupabaseAuthManager())
}
