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
            Form {
                if let configurationError = authManager.configurationError {
                    Section { Text(configurationError).font(.callout).foregroundStyle(.red) }
                }

                Section {
                    Text(L10n.Auth.description)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    TextField(L10n.Auth.emailLabel, text: $email)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .focused($focusedField, equals: .email)

                    SecureField(L10n.Auth.passwordLabel, text: $password)
                        .textContentType(.password)
                        .focused($focusedField, equals: .password)
                        .submitLabel(.go)
                        .onSubmit {
                            guard isPrimaryButtonDisabled == false else { return }
                            performPrimaryAction()
                        }

                    Text(L10n.Auth.passwordHint)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let message = authManager.lastErrorMessage {
                    Section { Text(message).font(.callout).foregroundStyle(.red) }
                }

                if let info = authManager.infoMessage {
                    Section { Text(info).font(.callout).foregroundStyle(.green) }
                }

                Section {
                    Button(action: performPrimaryAction) {
                        if authManager.isLoading {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .frame(maxWidth: .infinity)
                        } else {
                            Text(L10n.Auth.primaryAction)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(isPrimaryButtonDisabled)
                    .buttonStyle(.borderedProminent)
                }
            }
            .navigationTitle(L10n.Auth.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.Auth.dismiss) { dismiss() }
                }
            }
            .onAppear {
                authManager.clearMessages()
                focusedField = .email
            }
            .onChange(of: authManager.isAuthenticated) { isAuthenticated in
                if isAuthenticated { dismiss() }
            }
        }
    }

    private var isPrimaryButtonDisabled: Bool {
        guard authManager.configurationError == nil else { return true }
        return sanitizedEmail.isEmpty || sanitizedPassword.count < 6 || authManager.isLoading
    }

    private func performPrimaryAction() {
        authManager.clearMessages()
        let email = sanitizedEmail
        let password = sanitizedPassword
        Task { await authManager.authenticate(email: email, password: password) }
    }

    private var sanitizedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var sanitizedPassword: String {
        password.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

#Preview {
    SupabaseAuthView()
        .environmentObject(SupabaseAuthManager())
}
