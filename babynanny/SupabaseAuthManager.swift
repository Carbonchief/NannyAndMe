import Foundation
import Supabase

@MainActor
final class SupabaseAuthManager: ObservableObject {
    @Published private(set) var isAuthenticated = false
    @Published private(set) var currentUserEmail: String?
    @Published private(set) var configurationError: String?
    @Published var lastErrorMessage: String?
    @Published var infoMessage: String?
    @Published var isLoading = false

    private let client: SupabaseClient?
    private var hasSynchronizedCaregiverDataForCurrentSession = false
    private static let emailVerificationRedirectURL = URL(string: "nannyme://auth/verify")

    init() {
        do {
            let configuration = try SupabaseConfiguration.loadFromBundle()
            client = SupabaseClient(supabaseURL: configuration.url, supabaseKey: configuration.anonKey)
            configurationError = nil
            Task { await refreshSession() }
        } catch {
            client = nil
            configurationError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func clearMessages() {
        lastErrorMessage = nil
        infoMessage = nil
    }

    func authenticate(email: String, password: String) async -> Bool {
        guard let client else {
            lastErrorMessage = configurationError
            return false
        }

        clearMessages()
        isLoading = true
        defer { isLoading = false }

        let sanitizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let sanitizedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            let response = try await client.auth.signUp(
                email: sanitizedEmail,
                password: sanitizedPassword,
                redirectTo: Self.emailVerificationRedirectURL
            )
            apply(authResponse: response)

            if isAuthenticated {
                infoMessage = L10n.Auth.accountCreated
                return true
            }

            do {
                let session = try await client.auth.signIn(email: sanitizedEmail, password: sanitizedPassword)
                apply(session: session)
                if isAuthenticated {
                    infoMessage = nil
                    return true
                }
            } catch {
                if Self.isEmailConfirmationRequiredError(error) {
                    infoMessage = L10n.Auth.emailConfirmationInfo
                    return true
                }

                lastErrorMessage = Self.userFriendlyMessage(from: error)
                return false
            }

            infoMessage = L10n.Auth.emailConfirmationInfo
            return true
        } catch {
            guard Self.isUserAlreadyRegisteredError(error) else {
                lastErrorMessage = Self.userFriendlyMessage(from: error)
                return false
            }

            do {
                let session = try await client.auth.signIn(email: sanitizedEmail, password: sanitizedPassword)
                apply(session: session)
                if isAuthenticated {
                    infoMessage = nil
                }
                return isAuthenticated
            } catch {
                lastErrorMessage = Self.userFriendlyMessage(from: error)
                return false
            }
        }
    }

    func signOut() async {
        guard let client else { return }

        clearMessages()
        isLoading = true
        defer { isLoading = false }

        do {
            try await client.auth.signOut()
            isAuthenticated = false
            currentUserEmail = nil
            hasSynchronizedCaregiverDataForCurrentSession = false
        } catch {
            lastErrorMessage = Self.userFriendlyMessage(from: error)
        }
    }

    private func apply(authResponse: AuthResponse) {
        switch authResponse {
        case let .session(session):
            apply(session: session)
        case let .user(user):
            currentUserEmail = user.email
        }
    }

    private func apply(session: Session) {
        isAuthenticated = true
        currentUserEmail = session.user.email
        infoMessage = nil
        hasSynchronizedCaregiverDataForCurrentSession = false
    }

    private func refreshSession() async {
        guard let client else { return }
        do {
            let session = try await client.auth.session
            apply(session: session)
        } catch let goTrueError as GoTrueError {
            if case .sessionNotFound = goTrueError {
                return
            }
            lastErrorMessage = Self.userFriendlyMessage(from: goTrueError)
        } catch {
            // Ignore missing session errors, only surface unexpected failures.
            if (error as NSError).code != 401 {
                lastErrorMessage = Self.userFriendlyMessage(from: error)
            }
        }
    }

    func handleAuthenticationURL(_ url: URL) async {
        guard let client else { return }
        clearMessages()
        do {
            let session = try await client.auth.session(from: url)
            apply(session: session)
        } catch {
            lastErrorMessage = Self.userFriendlyMessage(from: error)
        }
    }

    func synchronizeCaregiverAccount(with profiles: [ChildProfile]) async {
        guard let client, isAuthenticated else { return }
        guard hasSynchronizedCaregiverDataForCurrentSession == false else { return }

        do {
            let session = try await client.auth.session
            try await upsertCaregiver(for: session.user)
            try await upsertBabyProfiles(profiles, caregiverID: session.user.id)
            hasSynchronizedCaregiverDataForCurrentSession = true
        } catch {
            hasSynchronizedCaregiverDataForCurrentSession = false
            lastErrorMessage = Self.userFriendlyMessage(from: error)
        }
    }

    private func upsertCaregiver(for user: User) async throws {
        guard let client else { return }

        guard let email = user.email ?? currentUserEmail else { return }

        let record = CaregiverRecord(
            id: user.id,
            email: email,
            passwordHash: resolvedPasswordHash(from: user),
            lastSignInAt: Date()
        )

        try await client.database
            .from("caregivers")
            .upsert(values: [record], onConflict: "id", returning: .minimal)
    }

    private func upsertBabyProfiles(_ profiles: [ChildProfile], caregiverID: UUID) async throws {
        guard let client else { return }

        let records = profiles.map { BabyProfileRecord(profile: $0, caregiverID: caregiverID) }
        guard records.isEmpty == false else { return }

        try await client.database
            .from("baby_profiles")
            .upsert(values: records, onConflict: "id", returning: .minimal)
    }

    private func resolvedPasswordHash(from user: User) -> String {
        user.id.uuidString
    }

    private static func userFriendlyMessage(from error: Error) -> String {
        if let localizedError = error as? LocalizedError, let description = localizedError.errorDescription {
            return description
        }
        return error.localizedDescription
    }

    private static func isUserAlreadyRegisteredError(_ error: Error) -> Bool {
        if case let GoTrueError.api(apiError) = error {
            let messages = [
                apiError.errorDescription,
                apiError.message,
                apiError.msg,
                apiError.error
            ].compactMap { $0 }

            if messages.contains(where: { $0.localizedCaseInsensitiveContains("already registered") }) {
                return true
            }
        }

        let nsError = error as NSError
        if let code = nsError.userInfo["code"] as? String, code.caseInsensitiveCompare("user_already_registered") == .orderedSame {
            return true
        }

        let messageSources: [String] = [
            nsError.userInfo["message"] as? String,
            nsError.userInfo[NSLocalizedDescriptionKey] as? String,
            nsError.localizedDescription
        ].compactMap { $0 }

        return messageSources.contains { message in
            message.localizedCaseInsensitiveContains("already registered")
        }
    }

    private static func isEmailConfirmationRequiredError(_ error: Error) -> Bool {
        if case let GoTrueError.api(apiError) = error {
            let messages = [
                apiError.errorDescription,
                apiError.message,
                apiError.msg,
                apiError.error
            ].compactMap { $0 }

            if messages.contains(where: { $0.localizedCaseInsensitiveContains("email not confirmed") }) {
                return true
            }
        }

        let nsError = error as NSError
        let messageSources: [String] = [
            nsError.userInfo["message"] as? String,
            nsError.userInfo["msg"] as? String,
            nsError.userInfo["error_description"] as? String,
            nsError.userInfo["error"] as? String,
            nsError.localizedDescription
        ].compactMap { $0 }

        return messageSources.contains { message in
            message.localizedCaseInsensitiveContains("email not confirmed")
        }
    }
}

private struct CaregiverRecord: Codable, Identifiable {
    var id: UUID
    var email: String
    var passwordHash: String
    var lastSignInAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case passwordHash = "password_hash"
        case lastSignInAt = "last_sign_in_at"
    }
}

private struct BabyProfileRecord: Codable, Identifiable {
    var id: UUID
    var caregiverID: UUID
    var name: String
    var dateOfBirth: String
    var avatarURL: String?

    init(profile: ChildProfile, caregiverID: UUID) {
        id = profile.id
        self.caregiverID = caregiverID
        name = profile.name
        dateOfBirth = Self.dateFormatter.string(from: profile.birthDate)
        avatarURL = nil
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    enum CodingKeys: String, CodingKey {
        case id
        case caregiverID = "caregiver_id"
        case name
        case dateOfBirth = "date_of_birth"
        case avatarURL = "avatar_url"
    }
}
