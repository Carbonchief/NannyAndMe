import AuthenticationServices
import Foundation
import SwiftUI

struct SupabaseAuthView: View {
    @EnvironmentObject private var authManager: SupabaseAuthManager
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var password = ""
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case email
        case password
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        headerCard
                        credentialCard

                        if let message = authManager.lastErrorMessage {
                            messageCard(
                                text: message,
                                tint: .red,
                                systemImage: "exclamationmark.triangle.fill"
                            )
                        }

                        if let info = authManager.infoMessage {
                            messageCard(
                                text: info,
                                tint: .green,
                                systemImage: "checkmark.seal.fill"
                            )
                        }

                        primaryActionButton

                        alternativeSignInDivider

                        SignInWithAppleButton(.signIn) { request in
                            AnalyticsTracker.capture("apple_sign_in_tap")
                            authManager.configureAppleRequest(request)
                        } onCompletion: { result in
                            Task {
                                await authManager.completeAppleSignIn(result: result)
                            }
                        }
                        .frame(height: 54)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                        )
                        .shadow(color: Color.black.opacity(0.2), radius: 20, x: 0, y: 12)
                        .disabled(authManager.isLoading || authManager.configurationError != nil)
                        .signInWithAppleButtonStyle(.white)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 32)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.Auth.dismiss) { dismiss() }
                }
            }
            .onAppear { authManager.clearMessages() }
            .onChange(of: authManager.isAuthenticated) { _, isAuthenticated in
                if isAuthenticated { dismiss() }
            }
        }
    }

    private var isPrimaryButtonDisabled: Bool {
        guard authManager.configurationError == nil else { return true }
        return sanitizedEmail.isEmpty || sanitizedPassword.count < 6 || authManager.isLoading
    }

    private func performPrimaryAction() {
        AnalyticsTracker.capture("email_login_tap", properties: ["email": sanitizedEmail])
        authManager.clearMessages()
        let email = sanitizedEmail
        let password = sanitizedPassword
        Task { await authManager.authenticate(email: email, password: password) }
    }

    private func performPasswordReset() {
        AnalyticsTracker.capture("password_reset_tap", properties: ["email": sanitizedEmail])
        authManager.clearMessages()
        let email = sanitizedEmail
        Task { await authManager.sendPasswordReset(email: email) }
    }

    private var sanitizedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var sanitizedPassword: String {
        password.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isPasswordResetDisabled: Bool {
        sanitizedEmail.isEmpty || authManager.isLoading
    }

    private var headerCard: some View {
        VStack(alignment: .center, spacing: 8) {
            Text(L10n.Auth.title)
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)

            Text(L10n.Auth.description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(24)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.25), radius: 25, x: 0, y: 16)
    }

    private var credentialCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            TextField(L10n.Auth.emailLabel, text: $email)
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .focused($focusedField, equals: .email)
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

            SecureField(L10n.Auth.passwordLabel, text: $password)
                .textContentType(.password)
                .focused($focusedField, equals: .password)
                .submitLabel(.go)
                .onSubmit {
                    guard isPrimaryButtonDisabled == false else { return }
                    performPrimaryAction()
                }
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

            HStack {
                Spacer()
                Button(action: performPasswordReset) {
                    if authManager.isLoading {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text(L10n.Auth.forgotPassword)
                            .font(.footnote.weight(.semibold))
                    }
                }
                .buttonStyle(.borderless)
                .disabled(isPasswordResetDisabled)
            }

            Text(L10n.Auth.passwordHint)
                .font(.footnote)
                .foregroundStyle(.primary.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.primary.opacity(0.05), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.25), radius: 20, x: 0, y: 12)
    }

    private var primaryActionButton: some View {
        Button(action: performPrimaryAction) {
            if authManager.isLoading {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
            } else {
                Text(L10n.Auth.primaryAction)
                    .font(.headline)
                    .tracking(0.2)
            }
        }
        .frame(maxWidth: .infinity)
        .buttonStyle(PrimaryAuthButtonStyle(isDisabled: isPrimaryButtonDisabled))
        .disabled(isPrimaryButtonDisabled)
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
        .padding(18)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(tint.opacity(0.4), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.2), radius: 16, x: 0, y: 10)
    }

    private var alternativeSignInDivider: some View {
        HStack(alignment: .center, spacing: 12) {
            dividerCapsule

            Text(L10n.Auth.alternativeSignInDivider.uppercased(with: Locale.current))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(0.8)

            dividerCapsule
        }
        .padding(.horizontal, 4)
    }

    private var dividerCapsule: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.12))
            .frame(height: 1)
            .frame(maxWidth: .infinity)
    }
}

#Preview {
    SupabaseAuthView()
        .environmentObject(SupabaseAuthManager())
}

private struct PrimaryAuthButtonStyle: ButtonStyle {
    let isDisabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                LinearGradient(
                    colors: gradientColors(isPressed: configuration.isPressed),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(isDisabled ? 0 : 0.25), radius: 22, x: 0, y: 14)
            .opacity(isDisabled ? 0.6 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }

    private func gradientColors(isPressed: Bool) -> [Color] {
        if isDisabled {
            return [
                Color.gray.opacity(0.55),
                Color.gray.opacity(0.45)
            ]
        }

        if isPressed {
            return [
                Color.accentColor.opacity(0.85),
                Color.accentColor.opacity(0.65)
            ]
        }

        return [
            Color.accentColor,
            Color.accentColor.opacity(0.8)
        ]
    }
}
