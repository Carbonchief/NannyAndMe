import AuthenticationServices
import CryptoKit
import Foundation
import os
import Supabase

@MainActor
final class SupabaseAuthManager: ObservableObject {
    @Published private(set) var isAuthenticated = false
    @Published private(set) var currentUserEmail: String?
    @Published private(set) var currentUserID: UUID?
    @Published private(set) var configurationError: String?
    @Published var lastErrorMessage: String?
    @Published var infoMessage: String?
    @Published var isLoading = false
    @Published var isPasswordChangeRequired = false

    private let client: SupabaseClient?
    private let logger = Logger(subsystem: "com.prioritybit.babynanny", category: "supabase-auth")
    private let supabaseAnonKey: String?
    private let supabaseBaseURL: URL?
    private var hasSynchronizedCaregiverDataForCurrentSession = false
    private var currentAppleNonce: String?
    private var currentAccessToken: String?
    private var lastAuthMethod: String?
    private weak var subscriptionService: RevenueCatSubscriptionService?
    private static let emailVerificationRedirectURL = URL(string: "nannyme://auth/verify")
    private static let passwordResetRedirectURL = URL(string: "nannyme://auth/reset")
    private static let profilePhotosBucketName = "ProfilePhotos"

    private enum AuthURLFlow: String {
        case recovery
        case signup
        case magiclink
        case unknown
    }

    enum ProfileShareResult {
        case success
        case recipientNotFound
        case alreadyShared
        case notOwner
        case failure(String)
    }

    struct ProfileShareEntry: Identifiable, Equatable {
        let id: UUID
        let email: String?
        let permission: ProfileSharePermission
        let status: ProfileShareStatus
        let createdAt: Date?
        let updatedAt: Date?
    }

    enum ProfileShareDetailsResult {
        case success([ProfileShareEntry])
        case notOwner
        case failure(String)
    }

    struct ProfileShareOperationError: LocalizedError {
        let message: String

        var errorDescription: String? { message }
    }

    init() {
        do {
            let configuration = try SupabaseConfiguration.loadFromBundle()
            client = SupabaseClient(supabaseURL: configuration.url, supabaseKey: configuration.anonKey)
            supabaseAnonKey = configuration.anonKey
            supabaseBaseURL = configuration.url
            configurationError = nil
            Task { await refreshSession() }
        } catch {
            client = nil
            supabaseAnonKey = nil
            supabaseBaseURL = nil
            configurationError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func registerSubscriptionService(_ service: RevenueCatSubscriptionService) {
        subscriptionService = service
    }

    func clearMessages() {
        lastErrorMessage = nil
        infoMessage = nil
    }

    func dismissPasswordChangeRequirement() {
        isPasswordChangeRequired = false
    }

    func sendPasswordReset(email: String) async {
        guard let client else {
            lastErrorMessage = configurationError
            return
        }

        let sanitizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard sanitizedEmail.isEmpty == false else {
            lastErrorMessage = L10n.Auth.passwordResetMissingEmail
            return
        }

        clearMessages()
        isLoading = true
        defer { isLoading = false }

        do {
            try await client.auth.resetPasswordForEmail(
                sanitizedEmail,
                redirectTo: Self.passwordResetRedirectURL
            )
            infoMessage = L10n.Auth.passwordResetEmailSent
        } catch {
            let message = Self.userFriendlyMessage(from: error)
            lastErrorMessage = message.isEmpty ? L10n.Auth.passwordResetFailure : message
        }
    }

    func changePassword(to newPassword: String) async -> Bool {
        guard let client else {
            lastErrorMessage = configurationError
            return false
        }

        clearMessages()
        let sanitizedPassword = newPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard sanitizedPassword.count >= 6 else {
            lastErrorMessage = L10n.Auth.passwordChangeRequirement
            return false
        }

        isLoading = true
        defer { isLoading = false }

        do {
            _ = try await client.auth.update(user: UserAttributes(password: sanitizedPassword))
            infoMessage = L10n.Auth.passwordChangeSuccess
            isPasswordChangeRequired = false
            AnalyticsTracker.capture("password_change_success")
            return true
        } catch {
            lastErrorMessage = Self.userFriendlyMessage(from: error)
            return false
        }
    }

    func authenticate(email: String, password: String) async -> Bool {
        guard let client else {
            lastErrorMessage = configurationError
            return false
        }

        clearMessages()
        lastAuthMethod = "email"
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

    func configureAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        request.requestedScopes = [.fullName, .email]
        let nonce = randomNonce()
        currentAppleNonce = nonce
        request.nonce = sha256(nonce)
    }

    func completeAppleSignIn(result: Result<ASAuthorization, Error>) async {
        guard let client else {
            lastErrorMessage = configurationError
            return
        }

        clearMessages()
        lastAuthMethod = "apple"
        isLoading = true
        defer {
            isLoading = false
            currentAppleNonce = nil
        }

        do {
            let authorization = try result.get()

            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                throw AppleSignInError.invalidCredential
            }

            guard let tokenData = credential.identityToken,
                  let token = String(data: tokenData, encoding: .utf8) else {
                throw AppleSignInError.missingIdentityToken
            }

            guard let nonce = currentAppleNonce else {
                throw AppleSignInError.missingNonce
            }

            let session = try await client.auth.signInWithIdToken(
                credentials: .init(provider: .apple, idToken: token, nonce: nonce)
            )

            apply(session: session)
            infoMessage = nil
        } catch is ASAuthorizationError {
            lastErrorMessage = L10n.Auth.appleSignInFailed
        } catch let appleError as AppleSignInError {
            lastErrorMessage = appleError.errorDescription
        } catch {
            lastErrorMessage = Self.userFriendlyMessage(from: error)
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
            currentUserID = nil
            currentAccessToken = nil
            hasSynchronizedCaregiverDataForCurrentSession = false
            isPasswordChangeRequired = false
            await subscriptionService?.logOutIfNeeded()
            AnalyticsTracker.capture("logout_success")
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
            currentUserID = user.id
        }
    }

    private func apply(session: Session) {
        isAuthenticated = true
        currentUserEmail = session.user.email
        currentUserID = session.user.id
        currentAccessToken = session.accessToken
        infoMessage = nil
        hasSynchronizedCaregiverDataForCurrentSession = false
        if let email = session.user.email {
            AnalyticsTracker.identifyUser(email: email)
            let method = lastAuthMethod ?? "unknown"
            AnalyticsTracker.capture(
                "login_success",
                properties: [
                    "method": method,
                    "email": email
                ]
            )
        }
        Task { @MainActor [weak subscriptionService] in
            guard let service = subscriptionService else { return }
            await service.logInIfNeeded(appUserID: session.user.id.uuidString)
        }
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

    func upsertCurrentCaregiverAPNSToken() async {
        guard let client else { return }
        guard isAuthenticated else { return }
        guard let apnsToken = currentAPNSToken() else { return }

        do {
            let session = try await client.auth.session
            guard let email = session.user.email ?? currentUserEmail else { return }

            let record = CaregiverRecord(
                id: session.user.id,
                email: email,
                passwordHash: resolvedPasswordHash(from: session.user),
                lastSignInAt: Date(),
                apnsToken: apnsToken
            )

            _ = try await client.database
                .from("caregivers")
                .upsert([record], onConflict: "id", returning: .minimal)
                .execute()

            currentUserID = session.user.id
            currentUserEmail = email
            hasSynchronizedCaregiverDataForCurrentSession = false
        } catch {
            lastErrorMessage = Self.userFriendlyMessage(from: error)
        }
    }

    func downloadAvatarImage(from url: URL) async throws -> Data {
        guard let token = currentAccessToken else {
            throw AvatarDownloadError.missingSession
        }

        let resolvedURL = normalizedAvatarURL(from: url)

        var request = URLRequest(url: resolvedURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let supabaseAnonKey {
            request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        }
        request.setValue("image/*", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AvatarDownloadError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw AvatarDownloadError.httpStatus(httpResponse.statusCode)
        }
        return data
    }

    func handleAuthenticationURL(_ url: URL) async {
        guard let client else { return }
        clearMessages()
        let flowType = Self.authFlowType(from: url)
        do {
            let session = try await client.auth.session(from: url)
            apply(session: session)
            isPasswordChangeRequired = flowType == .recovery
        } catch {
            lastErrorMessage = Self.userFriendlyMessage(from: error)
            isPasswordChangeRequired = false
        }
    }

    private static func authFlowType(from url: URL) -> AuthURLFlow? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }

        var queryParameters: [String: String] = [:]

        if let query = components.query {
            queryParameters.merge(parameters(from: query)) { _, new in new }
        }

        if let fragment = components.fragment {
            queryParameters.merge(parameters(from: fragment)) { _, new in new }
        }

        if let rawType = queryParameters["type"], let flow = AuthURLFlow(rawValue: rawType) {
            return flow
        }

        if components.path.lowercased().contains("reset") {
            return .recovery
        }

        return nil
    }

    private static func parameters(from rawString: String) -> [String: String] {
        rawString
            .split(separator: "&")
            .reduce(into: [String: String]()) { partialResult, pair in
                let components = pair.split(separator: "=", maxSplits: 1)
                guard let key = components.first else { return }
                let value = components.count > 1 ? String(components[1]) : ""
                partialResult[String(key)] = value.removingPercentEncoding ?? value
            }
    }

    func synchronizeCaregiverAccount(with profiles: [ChildProfile]) async -> CaregiverSnapshot? {
        guard let client, isAuthenticated else { return nil }

        if hasSynchronizedCaregiverDataForCurrentSession {
            return await fetchCaregiverSnapshot()
        }

        do {
            let session = try await client.auth.session
            try await upsertCaregiver(for: session.user)
            let remoteSnapshot = try await fetchCaregiverSnapshotFromSupabase()
            let hasRemoteData = remoteSnapshot.profileCount > 0 || remoteSnapshot.actionCount > 0
            let localHasNamedProfiles = profiles.contains { profile in
                profile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            }

            if hasRemoteData && localHasNamedProfiles == false {
                hasSynchronizedCaregiverDataForCurrentSession = true
                return remoteSnapshot
            }

            if profiles.isEmpty == false {
                try await upsertBabyProfiles(profiles, caregiverID: session.user.id)
            }

            let snapshot = try await fetchCaregiverSnapshotFromSupabase()
            hasSynchronizedCaregiverDataForCurrentSession = true
            return snapshot
        } catch {
            hasSynchronizedCaregiverDataForCurrentSession = false
            lastErrorMessage = Self.userFriendlyMessage(from: error)
            return nil
        }
    }

    func fetchCaregiverSnapshot() async -> CaregiverSnapshot? {
        guard let client = client, isAuthenticated else { return nil }

        do {
            if currentUserID == nil {
                let session = try await client.auth.session
                currentUserID = session.user.id
                currentUserEmail = session.user.email
            }

            let snapshot = try await fetchCaregiverSnapshotFromSupabase()
            return snapshot
        } catch {
            lastErrorMessage = Self.userFriendlyMessage(from: error)
            return nil
        }
    }

    func upsertBabyProfiles(_ profiles: [ChildProfile]) async {
        guard profiles.isEmpty == false else {
            logger.debug("Skipping baby profile upsert; no profiles provided")
            return
        }
        guard let client else {
            logger.error("Skipping baby profile upsert; Supabase client unavailable")
            return
        }
        guard isAuthenticated else {
            logger.warning("Skipping baby profile upsert; user is not authenticated")
            return
        }
        guard let caregiverID = currentUserID else {
            logger.error("Skipping baby profile upsert; missing caregiver identifier")
            return
        }

        do {
            let records = try await makeBabyProfileRecords(from: profiles,
                                                            caregiverID: caregiverID,
                                                            client: client,
                                                            shouldEncodeCaregiverID: true)

            try await upsertBabyProfileRecords(records, client: client)
        } catch {
            logger.error("Failed to upsert baby profiles: \(error.localizedDescription, privacy: .public)")
            lastErrorMessage = Self.userFriendlyMessage(from: error)
        }
    }

    @discardableResult
    func syncBabyActions(upserting actions: [BabyActionSnapshot],
                         deletingIDs: [UUID],
                         profileID: UUID) async -> Bool {
        guard let client else {
            logger.error("syncBabyActions aborted; missing Supabase client")
            return false
        }
        guard isAuthenticated else {
            logger.warning("syncBabyActions aborted; user not authenticated")
            return false
        }
        guard let caregiverID = currentUserID else {
            logger.error("syncBabyActions aborted; caregiver identifier unavailable")
            return false
        }

        let sanitizedActions = actions.map { $0.withValidatedDates() }
        let records = sanitizedActions.compactMap { action in
            BabyActionRecord(action: action,
                             caregiverID: caregiverID,
                             profileID: profileID,
                             shouldEncodeCaregiverID: true)
        }

        let shouldUpsert = records.isEmpty == false
        let shouldDelete = deletingIDs.isEmpty == false

        guard shouldUpsert || shouldDelete else { return true }

        do {
            if shouldUpsert {
                let existingIDs = try await fetchExistingIdentifiers(records.map(\.id),
                                                                     in: "baby_action",
                                                                     client: client)
                let insertRecords = records.filter { existingIDs.contains($0.id) == false }
                let updateRecords = records.filter { existingIDs.contains($0.id) }
                    .map { $0.withoutCaregiverIDUpdates() }

                if insertRecords.isEmpty == false {
                    _ = try await client.database
                        .from("baby_action")
                        .insert(insertRecords, returning: .minimal)
                        .execute()
                }

                if updateRecords.isEmpty == false {
                    for record in updateRecords {
                        _ = try await client.database
                            .from("baby_action")
                            .update(record)
                            .eq("id", value: record.id.uuidString.lowercased())
                            .execute()
                    }
                }
            }

            if shouldDelete {
                let identifiers = deletingIDs.map(\.uuidString)
                _ = try await client.database
                    .from("baby_action")
                    .delete()
                    .in("id", value: identifiers)
                    .execute()
            }
        } catch {
            logger.error("syncBabyActions failed for profile \(profileID.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)")
            lastErrorMessage = Self.userFriendlyMessage(from: error)
            return false
        }

        return true
    }

    private func upsertCaregiver(for user: User) async throws {
        guard let client else { return }

        guard let email = user.email ?? currentUserEmail else { return }

        let apnsToken = currentAPNSToken()

        let record = CaregiverRecord(
            id: user.id,
            email: email,
            passwordHash: resolvedPasswordHash(from: user),
            lastSignInAt: Date(),
            apnsToken: apnsToken
        )

        do {
            _ = try await client.database
                .from("caregivers")
                .upsert([record], onConflict: "id", returning: .minimal)
                .execute()
        } catch {
            throw error
        }
    }

    private func upsertBabyProfiles(_ profiles: [ChildProfile], caregiverID: UUID) async throws {
        guard let client else { return }

        let records = try await makeBabyProfileRecords(from: profiles,
                                                       caregiverID: caregiverID,
                                                       client: client,
                                                       shouldEncodeCaregiverID: true)
        try await upsertBabyProfileRecords(records, client: client)
    }

    private func makeBabyProfileRecords(from profiles: [ChildProfile],
                                        caregiverID: UUID,
                                        client: SupabaseClient,
                                        shouldEncodeCaregiverID: Bool) async throws -> [BabyProfileRecord] {
        guard profiles.isEmpty == false else { return [] }

        var records: [BabyProfileRecord] = []
        records.reserveCapacity(profiles.count)

        for profile in profiles {
            let resolvedCaregiverID = try await resolveCaregiverID(for: profile,
                                                                   currentCaregiverID: caregiverID,
                                                                   client: client)
            let avatarURL = try await resolveAvatarURL(for: profile,
                                                       caregiverID: caregiverID,
                                                       client: client)
            let shouldClearAvatar = profile.imageData == nil && profile.avatarURL == nil
            let record = BabyProfileRecord(profile: profile,
                                           caregiverID: resolvedCaregiverID,
                                           shouldEncodeCaregiverID: shouldEncodeCaregiverID,
                                           avatarURL: avatarURL,
                                           shouldClearAvatar: shouldClearAvatar)
            records.append(record)
        }

        return records
    }

    private func upsertBabyProfileRecords(_ records: [BabyProfileRecord],
                                          client: SupabaseClient) async throws {
        guard records.isEmpty == false else { return }

        let sanitizedRecords = records.map { $0.withoutCaregiverIDUpdates() }

        do {
            let existingIDs = try await fetchExistingIdentifiers(records.map(\.id),
                                                                 in: "baby_profiles",
                                                                 client: client)
            let insertRecords = records.filter { existingIDs.contains($0.id) == false }
            let updateRecords = sanitizedRecords.filter { existingIDs.contains($0.id) }

            try await insertBabyProfileRecords(insertRecords, client: client)
            try await updateBabyProfileRecords(updateRecords, client: client)
        } catch {
            let fallbackRecords = sanitizedRecords
            try await updateBabyProfileRecords(fallbackRecords, client: client)
        }
    }

    private func insertBabyProfileRecords(_ records: [BabyProfileRecord],
                                          client: SupabaseClient) async throws {
        guard records.isEmpty == false else { return }

        _ = try await client.database
            .from("baby_profiles")
            .insert(records, returning: .minimal)
            .execute()
    }

    private func updateBabyProfileRecords(_ records: [BabyProfileRecord],
                                          client: SupabaseClient) async throws {
        guard records.isEmpty == false else { return }

        for record in records {
            _ = try await client.database
                .from("baby_profiles")
                .update(record)
                .eq("id", value: record.id.uuidString.lowercased())
                .execute()
        }
    }

    private func fetchExistingIdentifiers(_ ids: [UUID],
                                          in table: String,
                                          client: SupabaseClient) async throws -> Set<UUID> {
        guard ids.isEmpty == false else { return [] }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom(SupabaseDateDecoder.decode)
        let response: PostgrestResponse<[IdentifierRecord]> = try await client.database
            .from(table)
            .select("id")
            .in("id", value: ids.map { $0.uuidString.lowercased() })
            .execute()

        let records: [IdentifierRecord] = try decodeResponse(response.value,
                                                              decoder: decoder,
                                                              context: "existing-ids-\(table)")
        return Set(records.map(\.id))
    }

    private func resolveCaregiverID(for profile: ChildProfile,
                                    currentCaregiverID: UUID,
                                    client: SupabaseClient) async throws -> UUID {
        guard profile.isShared else { return currentCaregiverID }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom(SupabaseDateDecoder.decode)

        let response: PostgrestResponse<[BabyProfileOwnershipRecord]> = try await client.database
            .from("baby_profiles")
            .select("id, caregiver_id")
            .eq("id", value: profile.id.uuidString.lowercased())
            .limit(1)
            .execute()

        let records: [BabyProfileOwnershipRecord] = try decodeResponse(response.value,
                                                                       decoder: decoder,
                                                                       context: "profile-ownership")

        guard let ownershipRecord = records.first else { return currentCaregiverID }

        if ownershipRecord.caregiverID != currentCaregiverID {
            return ownershipRecord.caregiverID
        }

        return currentCaregiverID
    }

    private func resolveAvatarURL(for profile: ChildProfile,
                                  caregiverID: UUID,
                                  client: SupabaseClient) async throws -> String? {
        guard let imageData = profile.imageData, imageData.isEmpty == false else { return nil }

        let fileType = Self.resolveAvatarFileType(for: imageData)
        let fileName = Self.avatarFileName(for: profile.id, fileExtension: fileType.fileExtension)
        let storagePath = Self.avatarStoragePath(for: fileName, caregiverID: caregiverID)
        let bucket = client.storage.from(Self.profilePhotosBucketName)
        let options = FileOptions(contentType: fileType.contentType, upsert: true)

        do {
            _ = try await bucket.upload(path: storagePath, file: imageData, options: options)
        } catch {
            throw error
        }

        if let authenticatedURL = makeAuthenticatedStorageURL(for: storagePath) {
            return authenticatedURL.absoluteString
        }

        let publicURL = try bucket.getPublicURL(path: storagePath)
        return publicURL.absoluteString
    }

    private static func resolveAvatarFileType(for data: Data) -> (contentType: String, fileExtension: String) {
        if data.prefix(Self.pngSignature.count).elementsEqual(Self.pngSignature) {
            return ("image/png", "png")
        }
        return ("image/jpeg", "jpg")
    }

    private static func avatarFileName(for profileID: UUID, fileExtension: String) -> String {
        "\(profileID.uuidString).\(fileExtension)"
    }

    private static func avatarStoragePath(for fileName: String, caregiverID: UUID) -> String {
        "\(caregiverID.uuidString)/\(fileName)"
    }

    private static let pngSignature: [UInt8] = [0x89, 0x50, 0x4E, 0x47]

    private func makeAuthenticatedStorageURL(for storagePath: String) -> URL? {
        guard let baseURL = supabaseBaseURL,
              var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.path = "/storage/v1/object/authenticated/\(Self.profilePhotosBucketName)/\(storagePath)"
        return components.url
    }

    private func normalizedAvatarURL(from url: URL) -> URL {
        guard url.scheme != nil else {
            if let rebuilt = rebuildAvatarURL(fromRelativeString: url.absoluteString) {
                return rebuilt
            }
            return url
        }

        if url.path.contains("/storage/v1/object/public/") {
            if var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                components.path = components.path.replacingOccurrences(of: "/storage/v1/object/public/",
                                                                       with: "/storage/v1/object/authenticated/")
                if let rebuilt = components.url {
                    return rebuilt
                }
            }
        }

        return url
    }

    private func rebuildAvatarURL(fromRelativeString value: String) -> URL? {
        guard let baseURL = supabaseBaseURL else { return nil }
        var relative = value
        if relative.hasPrefix("/") {
            relative.removeFirst()
        }

        if relative.hasPrefix("storage/v1") == false {
            relative = "storage/v1/object/authenticated/\(Self.profilePhotosBucketName)/\(relative)"
        }

        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.path = "/" + relative
        return components.url
    }

    private func fetchCaregiverSnapshotFromSupabase() async throws -> CaregiverSnapshot {
        guard let client else {
            throw SnapshotError.clientUnavailable
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom(SupabaseDateDecoder.decode)

        let caregiverID: UUID
        if let existingID = currentUserID {
            caregiverID = existingID
        } else {
            let session = try await client.auth.session
            caregiverID = session.user.id
            currentUserID = caregiverID
            currentUserEmail = session.user.email
        }

        let profilesResponse: PostgrestResponse<[BabyProfileRecord]> = try await client.database
            .from("baby_profiles")
            .select()
            .execute()

        let actionsResponse: PostgrestResponse<[BabyActionRecord]> = try await client.database
            .from("baby_action")
            .select()
            .execute()

        let profileRecords: [BabyProfileRecord] = try decodeResponse(profilesResponse.value,
                                                                     decoder: decoder,
                                                                     context: "profiles")
        let actionRecords: [BabyActionRecord] = try decodeResponse(actionsResponse.value,
                                                                   decoder: decoder,
                                                                   context: "actions")

        let shareSnapshot = try await fetchSharePermissions(for: caregiverID, client: client)

        return CaregiverSnapshot(caregiverID: caregiverID,
                                 profiles: profileRecords,
                                 actions: actionRecords,
                                 sharePermissions: shareSnapshot.permissions,
                                 shareStatuses: shareSnapshot.statuses)
    }

    private struct SharePermissionSnapshot {
        let permissions: [UUID: ProfileSharePermission]
        let statuses: [UUID: ProfileShareStatus]
    }

    private func fetchSharePermissions(for caregiverID: UUID,
                                       client: SupabaseClient) async throws -> SharePermissionSnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom(SupabaseDateDecoder.decode)

        let response: PostgrestResponse<[BabyProfileSharePermissionRecord]> = try await client.database
            .from("baby_profile_shares")
            .select("baby_profile_id, permission, status")
            .eq("recipient_caregiver_id", value: caregiverID.uuidString.lowercased())
            .execute()

        let records: [BabyProfileSharePermissionRecord] = try decodeResponse(response.value,
                                                                             decoder: decoder,
                                                                             context: "profile-share-permissions")

        var permissions: [UUID: ProfileSharePermission] = [:]
        var statuses: [UUID: ProfileShareStatus] = [:]

        for record in records {
            let rawStatus = record.status?.lowercased()
            let status = rawStatus.flatMap { ProfileShareStatus(rawValue: $0) } ?? .accepted
            guard status == .pending || status == .accepted else { continue }
            statuses[record.babyProfileID] = status
            let permission = record.permission.flatMap { ProfileSharePermission(rawValue: $0.lowercased()) } ?? .view
            if status == .accepted {
                permissions[record.babyProfileID] = permission
            }
        }

        return SharePermissionSnapshot(permissions: permissions, statuses: statuses)
    }

    func deleteBabyProfile(withID id: UUID) async {
        guard let client, isAuthenticated, let currentUserID else { return }

        let identifier = id.uuidString
        let normalizedIdentifier = identifier.lowercased()
        var recordedError: Error?

        func recordError(_ error: Error) {
            if recordedError == nil {
                recordedError = error
            }
        }

        var shareMembership: BabyProfileShareMembershipRecord?

        do {
            let decoder = JSONDecoder()
            let response: PostgrestResponse<[BabyProfileShareMembershipRecord]> = try await client.database
                .from("baby_profile_shares")
                .select("baby_profile_id, owner_caregiver_id, recipient_caregiver_id")
                .eq("baby_profile_id", value: identifier)
                .eq("recipient_caregiver_id", value: currentUserID.uuidString)
                .limit(1)
                .execute()

            let records: [BabyProfileShareMembershipRecord] = try decodeResponse(
                response.value,
                decoder: decoder,
                context: "profile-share-membership"
            )
            shareMembership = records.first
        } catch {
            recordError(error)

            if let recordedError {
                lastErrorMessage = Self.userFriendlyMessage(from: recordedError)
            }
            return
        }

        if let shareMembership, shareMembership.recipientCaregiverID == currentUserID {
            do {
                let update = BabyProfileShareStatusUpdate(status: "revoked")
                _ = try await client.database
                    .from("baby_profile_shares")
                    .update(update)
                    .eq("baby_profile_id", value: identifier)
                    .eq("recipient_caregiver_id", value: currentUserID.uuidString)
                    .execute()
            } catch {
                recordError(error)
            }

            if let recordedError {
                lastErrorMessage = Self.userFriendlyMessage(from: recordedError)
            }
            return
        }

        do {
            let decoder = JSONDecoder()
            let response: PostgrestResponse<[BabyProfileOwnershipRecord]> = try await client.database
                .from("baby_profiles")
                .select("id, caregiver_id")
                .eq("id", value: identifier)
                .limit(1)
                .execute()

            let records: [BabyProfileOwnershipRecord] = try decodeResponse(
                response.value,
                decoder: decoder,
                context: "profile-ownership"
            )

            guard let ownershipRecord = records.first else { return }
            guard ownershipRecord.caregiverID == currentUserID else { return }
        } catch {
            recordError(error)

            if let recordedError {
                lastErrorMessage = Self.userFriendlyMessage(from: recordedError)
            }
            return
        }

        do {
            let response: PostgrestResponse<Void> = try await client.database
                .from("baby_action")
                .delete()
                .eq("profile_id", value: normalizedIdentifier)
                .execute(options: .init(count: .exact))
            _ = response.count
        } catch {
            recordError(error)
        }


        guard recordedError == nil else {
            lastErrorMessage = Self.userFriendlyMessage(from: recordedError!)
            return
        }

        do {
            _ = try await client.database
                .from("baby_profile_shares")
                .delete()
                .eq("baby_profile_id", value: identifier)
                .execute()
        } catch {
            recordError(error)
        }

        guard recordedError == nil else {
            lastErrorMessage = Self.userFriendlyMessage(from: recordedError!)
            return
        }

        do {
            _ = try await client.database
                .from("baby_profiles")
                .delete()
                .eq("id", value: identifier)
                .execute()
        } catch {
            recordError(error)
        }

        if let recordedError {
            lastErrorMessage = Self.userFriendlyMessage(from: recordedError)
        }
    }

    func deleteOwnedAccountData() async -> Bool {
        guard let client else {
            lastErrorMessage = configurationError
            return false
        }

        clearMessages()
        isLoading = true
        defer { isLoading = false }

        if currentUserID == nil {
            do {
                let session = try await client.auth.session
                currentUserID = session.user.id
                currentUserEmail = session.user.email
            } catch {
                lastErrorMessage = Self.userFriendlyMessage(from: error)
                return false
            }
        }

        guard isAuthenticated, let userID = currentUserID else {
            lastErrorMessage = L10n.ManageAccount.notAuthenticated
            return false
        }

        var recordedError: Error?

        func recordError(_ error: Error) {
            if recordedError == nil {
                recordedError = error
            }
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom(SupabaseDateDecoder.decode)

        let ownedProfileIDs: [UUID]
        do {
            let response: PostgrestResponse<[BabyProfileOwnershipRecord]> = try await client.database
                .from("baby_profiles")
                .select("id, caregiver_id")
                .eq("caregiver_id", value: userID.uuidString)
                .execute()

            let records: [BabyProfileOwnershipRecord] = try decodeResponse(
                response.value,
                decoder: decoder,
                context: "account-profile-ownership"
            )
            ownedProfileIDs = records
                .filter { $0.caregiverID == userID }
                .map(\.id)
        } catch {
            recordError(error)

            if let recordedError {
                lastErrorMessage = Self.userFriendlyMessage(from: recordedError)
            }

            return false
        }

        let identifiers = ownedProfileIDs.map { $0.uuidString.lowercased() }

        do {
            let update = BabyActionClearEditorUpdate(lastEditedBy: nil)
            _ = try await client.database
                .from("baby_action")
                .update(update)
                .eq("last_edited_by", value: userID.uuidString)
                .execute()
        } catch {
            recordError(error)
        }

        guard recordedError == nil else {
            lastErrorMessage = Self.userFriendlyMessage(from: recordedError!)
            return false
        }

        do {
            _ = try await client.database
                .from("baby_action")
                .delete()
                .eq("caregiver_id", value: userID.uuidString)
                .execute(options: .init(count: .exact))
        } catch {
            recordError(error)
        }

        guard recordedError == nil else {
            lastErrorMessage = Self.userFriendlyMessage(from: recordedError!)
            return false
        }

        if identifiers.isEmpty == false {
            do {
                _ = try await client.database
                    .from("baby_profile_shares")
                    .delete()
                    .in("baby_profile_id", value: identifiers)
                    .execute()
            } catch {
                recordError(error)
            }

            guard recordedError == nil else {
                lastErrorMessage = Self.userFriendlyMessage(from: recordedError!)
                return false
            }

            do {
                _ = try await client.database
                    .from("baby_profiles")
                    .delete()
                    .eq("caregiver_id", value: userID.uuidString)
                    .execute()
            } catch {
                recordError(error)
            }
        }

        guard recordedError == nil else {
            lastErrorMessage = Self.userFriendlyMessage(from: recordedError!)
            return false
        }

        do {
            _ = try await client.database
                .from("baby_profile_shares")
                .delete()
                .eq("recipient_caregiver_id", value: userID.uuidString)
                .execute()
        } catch {
            recordError(error)
        }

        guard recordedError == nil else {
            lastErrorMessage = Self.userFriendlyMessage(from: recordedError!)
            return false
        }

        do {
            _ = try await client.database
                .from("caregivers")
                .delete()
                .eq("id", value: userID.uuidString)
                .execute()
        } catch {
            recordError(error)
        }

        if let recordedError {
            lastErrorMessage = Self.userFriendlyMessage(from: recordedError)
            return false
        }

        return true
    }

    func shareBabyProfile(profileID: UUID,
                          recipientEmail: String,
                          permission: ProfileSharePermission) async -> ProfileShareResult {
        guard let client else {
            let message = configurationError ?? L10n.ShareData.Supabase.failureConfiguration
            return .failure(message)
        }

        guard isAuthenticated, let ownerID = currentUserID else {
            return .failure(L10n.ShareData.Supabase.notAuthenticated)
        }

        do {
            let isOwner = try await ensureOwnership(of: profileID, ownerID: ownerID)
            guard isOwner else {
                return .notOwner
            }
        } catch {
            let message = Self.userFriendlyMessage(from: error)
            return .failure(message)
        }

        let sanitizedEmail = recipientEmail
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard sanitizedEmail.isEmpty == false else {
            return .failure(L10n.ShareData.Supabase.invalidEmailMessage)
        }

        do {
            let decoder = JSONDecoder()
            let caregiverResponse: PostgrestResponse<[CaregiverIdentifierRecord]> = try await client.database
                .from("caregivers")
                .select("id")
                .eq("email", value: sanitizedEmail)
                .limit(1)
                .execute()

            let caregivers: [CaregiverIdentifierRecord] = try decodeResponse(
                caregiverResponse.value,
                decoder: decoder,
                context: "profile-share-caregivers"
            )

            guard let recipientID = caregivers.first?.id else {
                return .recipientNotFound
            }

            let record = BabyProfileShareRecord(
                babyProfileID: profileID,
                ownerCaregiverID: ownerID,
                recipientCaregiverID: recipientID,
                permission: permission.rawValue,
                status: ProfileShareStatus.accepted.rawValue
            )

            _ = try await client.database
                .from("baby_profile_shares")
                .insert([record], returning: .minimal)
                .execute()

            return .success
        } catch {
            let message = Self.userFriendlyMessage(from: error)
            let additionalDetails: [String] = [
                message,
                (error as NSError).userInfo["message"] as? String ?? "",
                (error as NSError).userInfo["hint"] as? String ?? "",
                (error as NSError).userInfo["details"] as? String ?? ""
            ]
            if additionalDetails.contains(where: { detail in
                detail.localizedCaseInsensitiveContains("duplicate")
                    || detail.localizedCaseInsensitiveContains("already")
            }) {
                return .alreadyShared
            }

            return .failure(message)
        }
    }

    func fetchProfileShareDetails(profileID: UUID) async -> ProfileShareDetailsResult {
        guard let client else {
            let message = configurationError ?? L10n.ShareData.Supabase.failureConfiguration
            return .failure(message)
        }

        guard isAuthenticated, let ownerID = currentUserID else {
            return .failure(L10n.ShareData.Supabase.notAuthenticated)
        }

        do {
            let isOwner = try await ensureOwnership(of: profileID, ownerID: ownerID)
            guard isOwner else {
                return .notOwner
            }

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .custom(SupabaseDateDecoder.decode)

            let response: PostgrestResponse<[BabyProfileShareDetailRecord]> = try await client.database
                .from("baby_profile_shares")
                .select("id, permission, status, created_at, updated_at, recipient_caregiver_id, recipient:recipient_caregiver_id ( email )")
                .eq("baby_profile_id", value: profileID.uuidString.lowercased())
                .order("created_at", ascending: true)
                .execute()

            let records: [BabyProfileShareDetailRecord] = try decodeResponse(
                response.value,
                decoder: decoder,
                context: "profile-share-details"
            )

            let entries = records.map { record in
                ProfileShareEntry(
                    id: record.id,
                    email: record.recipient?.email,
                    permission: ProfileSharePermission(rawValue: record.permission.lowercased()) ?? .view,
                    status: ProfileShareStatus(rawValue: record.status.lowercased()) ?? .pending,
                    createdAt: record.createdAt,
                    updatedAt: record.updatedAt
                )
            }

            return .success(entries)
        } catch {
            let message = Self.userFriendlyMessage(from: error)
            return .failure(message)
        }
    }

    func updateProfileSharePermission(shareID: UUID,
                                      permission: ProfileSharePermission) async -> Result<Void, ProfileShareOperationError> {
        let update = BabyProfileShareUpdate(permission: permission.rawValue, status: nil)
        return await updateProfileShare(shareID: shareID, update: update)
    }

    func revokeProfileShare(shareID: UUID) async -> Result<Void, ProfileShareOperationError> {
        let update = BabyProfileShareUpdate(permission: nil, status: ProfileShareStatus.revoked.rawValue)
        return await updateProfileShare(shareID: shareID, update: update)
    }

    func reinviteProfileShare(shareID: UUID) async -> Result<Void, ProfileShareOperationError> {
        let update = BabyProfileShareUpdate(permission: nil, status: ProfileShareStatus.pending.rawValue)
        return await updateProfileShare(shareID: shareID, update: update)
    }

    func respondToShareInvitation(profileID: UUID,
                                  accept: Bool) async -> Result<Void, ProfileShareOperationError> {
        let desiredStatus: ProfileShareStatus = accept ? .accepted : .revoked
        return await updateRecipientShareStatus(for: profileID, status: desiredStatus)
    }

    private func updateRecipientShareStatus(for profileID: UUID,
                                            status: ProfileShareStatus) async -> Result<Void, ProfileShareOperationError> {
        guard let client else {
            let message = configurationError ?? L10n.ShareData.Supabase.failureConfiguration
            return .failure(ProfileShareOperationError(message: message))
        }

        guard isAuthenticated, let recipientID = currentUserID else {
            return .failure(ProfileShareOperationError(message: L10n.ShareData.Supabase.notAuthenticated))
        }

        guard status == .accepted || status == .revoked else {
            return .failure(ProfileShareOperationError(message: L10n.ShareData.Supabase.failureTitle))
        }

        do {
            let update = BabyProfileShareStatusUpdate(status: status.rawValue)
            _ = try await client.database
                .from("baby_profile_shares")
                .update(update)
                .eq("baby_profile_id", value: profileID.uuidString.lowercased())
                .eq("recipient_caregiver_id", value: recipientID.uuidString.lowercased())
                .eq("status", value: ProfileShareStatus.pending.rawValue)
                .execute()
            return .success(())
        } catch {
            let message = Self.userFriendlyMessage(from: error)
            return .failure(ProfileShareOperationError(message: message))
        }
    }

    private func updateProfileShare(shareID: UUID,
                                    update: BabyProfileShareUpdate) async -> Result<Void, ProfileShareOperationError> {
        guard let client else {
            let message = configurationError ?? L10n.ShareData.Supabase.failureConfiguration
            return .failure(ProfileShareOperationError(message: message))
        }

        guard isAuthenticated, let ownerID = currentUserID else {
            return .failure(ProfileShareOperationError(message: L10n.ShareData.Supabase.notAuthenticated))
        }

        do {
            _ = try await client.database
                .from("baby_profile_shares")
                .update(update)
                .eq("id", value: shareID.uuidString)
                .eq("owner_caregiver_id", value: ownerID.uuidString)
                .execute()
            return .success(())
        } catch {
            let message = Self.userFriendlyMessage(from: error)
            return .failure(ProfileShareOperationError(message: message))
        }
    }

    private func ensureOwnership(of profileID: UUID, ownerID: UUID) async throws -> Bool {
        guard let client else {
            throw SnapshotError.clientUnavailable
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom(SupabaseDateDecoder.decode)

        let response: PostgrestResponse<[BabyProfileOwnershipRecord]> = try await client.database
            .from("baby_profiles")
            .select("id, caregiver_id")
            .eq("id", value: profileID.uuidString.lowercased())
            .limit(1)
            .execute()

        let records: [BabyProfileOwnershipRecord] = try decodeResponse(
            response.value,
            decoder: decoder,
            context: "profile-ownership"
        )

        guard let ownershipRecord = records.first else {
            return false
        }

        return ownershipRecord.caregiverID == ownerID
    }

    private func resolvedPasswordHash(from user: User) -> String {
        user.id.uuidString
    }

    private func currentAPNSToken() -> String? {
        let token = UserDefaults.standard.string(forKey: AppStorageKey.pushNotificationDeviceToken)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let token, token.isEmpty == false else { return nil }
        return token
    }

    private enum AppleSignInError: LocalizedError {
        case invalidCredential
        case missingIdentityToken
        case missingNonce

        var errorDescription: String? { L10n.Auth.appleSignInFailed }
    }

    private func randomNonce(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var remaining = length
        var generator = SystemRandomNumberGenerator()
        var result = String()
        result.reserveCapacity(length)

        while remaining > 0 {
            guard let random = charset.randomElement(using: &generator) else { continue }
            result.append(random)
            remaining -= 1
        }

        return result
    }

    private func sha256(_ input: String) -> String {
        let hashed = SHA256.hash(data: Data(input.utf8))
        return hashed.map { String(format: "%02x", $0) }.joined()
    }

    private static func userFriendlyMessage(from error: Error) -> String {
        if error is DecodingError {
            let detail = decodingErrorDetails(from: error)
            return "\(error.localizedDescription) (\(detail))"
        }

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

private enum SupabaseDateDecoder {
    static func decode(_ decoder: Decoder) throws -> Date {
        let container = try decoder.singleValueContainer()

        if let string = try? container.decode(String.self) {
            if let date = iso8601Formatter(fractional: true).date(from: string)
                ?? iso8601Formatter(fractional: false).date(from: string)
                ?? fractionalPlainDateTimeFormatter().date(from: string)
                ?? plainDateTimeFormatter().date(from: string)
                ?? spaceSeparatedFormatter().date(from: string) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid date string: \(string)"
            )
        }

        if let milliseconds = try? container.decode(Double.self) {
            return Date(timeIntervalSince1970: milliseconds / 1000)
        }

        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Unsupported date value"
        )
    }

    private static func iso8601Formatter(fractional: Bool) -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        if fractional {
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        } else {
            formatter.formatOptions = [.withInternetDateTime]
        }
        return formatter
    }

    private static func plainDateTimeFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter
    }

    private static func fractionalPlainDateTimeFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"
        return formatter
    }

    private static func spaceSeparatedFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ssXXXXX"
        return formatter
    }
}

private struct CaregiverRecord: Codable, Identifiable {
    var id: UUID
    var email: String
    var passwordHash: String
    var lastSignInAt: Date
    var apnsToken: String?

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case passwordHash = "password_hash"
        case lastSignInAt = "last_sign_in_at"
        case apnsToken = "apns_token"
    }
}

private struct BabyProfileRecord: Codable, Identifiable {
    var id: UUID
    var caregiverID: UUID
    var name: String
    var dateOfBirth: String?
    var avatarURL: String?
    var createdAt: Date?
    var editedAt: Date?
    private var shouldClearAvatarOnUpload = false
    private var shouldEncodeCaregiverID = true

    init(profile: ChildProfile,
         caregiverID: UUID,
         shouldEncodeCaregiverID: Bool,
         avatarURL: String?,
         shouldClearAvatar: Bool) {
        id = profile.id
        self.caregiverID = caregiverID
        self.shouldEncodeCaregiverID = shouldEncodeCaregiverID
        name = profile.name
        dateOfBirth = Self.dateFormatter.string(from: profile.birthDate)
        self.avatarURL = avatarURL
        shouldClearAvatarOnUpload = shouldClearAvatar
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        caregiverID = try container.decode(UUID.self, forKey: .caregiverID)
        name = try container.decode(String.self, forKey: .name)
        dateOfBirth = try container.decodeIfPresent(String.self, forKey: .dateOfBirth)
        avatarURL = try container.decodeIfPresent(String.self, forKey: .avatarURL)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
        editedAt = try container.decodeIfPresent(Date.self, forKey: .editedAt)
        shouldClearAvatarOnUpload = false
        shouldEncodeCaregiverID = true
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        if shouldEncodeCaregiverID {
            try container.encode(caregiverID, forKey: .caregiverID)
        }
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(dateOfBirth, forKey: .dateOfBirth)
        if let avatarURL {
            try container.encode(avatarURL, forKey: .avatarURL)
        } else if shouldClearAvatarOnUpload {
            try container.encodeNil(forKey: .avatarURL)
        }
        try container.encodeIfPresent(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(editedAt, forKey: .editedAt)
    }

    func withoutCaregiverIDUpdates() -> BabyProfileRecord {
        var record = self
        record.shouldEncodeCaregiverID = false
        return record
    }

    func asMetadataUpdate() -> ProfileStore.ProfileMetadataUpdate {
        ProfileStore.ProfileMetadataUpdate(
            id: id,
            name: name,
            birthDate: birthDateValue,
            imageData: nil,
            avatarURL: avatarURL
        )
    }

    private var birthDateValue: Date? {
        guard let dateOfBirth else { return nil }
        return Self.dateFormatter.date(from: dateOfBirth)
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
        case createdAt = "created_at"
        case editedAt = "edited_at"
    }
}

private struct CaregiverIdentifierRecord: Decodable {
    var id: UUID
}

private struct BabyProfileShareRecord: Encodable {
    var babyProfileID: UUID
    var ownerCaregiverID: UUID
    var recipientCaregiverID: UUID
    var permission: String?
    var status: String?

    enum CodingKeys: String, CodingKey {
        case babyProfileID = "baby_profile_id"
        case ownerCaregiverID = "owner_caregiver_id"
        case recipientCaregiverID = "recipient_caregiver_id"
        case permission
        case status
    }
}

private struct BabyProfileShareDetailRecord: Decodable {
    var id: UUID
    var permission: String
    var status: String
    var createdAt: Date?
    var updatedAt: Date?
    var recipientCaregiverID: UUID
    var recipient: CaregiverEmailRecord?

    enum CodingKeys: String, CodingKey {
        case id
        case permission
        case status
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case recipientCaregiverID = "recipient_caregiver_id"
        case recipient
    }
}

private struct BabyProfileSharePermissionRecord: Decodable {
    var babyProfileID: UUID
    var permission: String?
    var status: String?

    enum CodingKeys: String, CodingKey {
        case babyProfileID = "baby_profile_id"
        case permission
        case status
    }
}

private struct BabyProfileShareMembershipRecord: Decodable {
    var babyProfileID: UUID
    var ownerCaregiverID: UUID
    var recipientCaregiverID: UUID

    enum CodingKeys: String, CodingKey {
        case babyProfileID = "baby_profile_id"
        case ownerCaregiverID = "owner_caregiver_id"
        case recipientCaregiverID = "recipient_caregiver_id"
    }
}

private struct CaregiverEmailRecord: Decodable {
    var email: String?
}

private struct IdentifierRecord: Decodable {
    var id: UUID
}

private struct BabyProfileOwnershipRecord: Decodable {
    var id: UUID
    var caregiverID: UUID

    enum CodingKeys: String, CodingKey {
        case id
        case caregiverID = "caregiver_id"
    }
}

private struct BabyProfileShareStatusUpdate: Encodable {
    var status: String

    enum CodingKeys: String, CodingKey {
        case status
    }
}

private struct BabyProfileShareUpdate: Encodable {
    var permission: String?
    var status: String?

    enum CodingKeys: String, CodingKey {
        case permission
        case status
    }
}

private struct BabyActionClearEditorUpdate: Encodable {
    var lastEditedBy: UUID?

    enum CodingKeys: String, CodingKey {
        case lastEditedBy = "last_edited_by"
    }
}

private struct BabyActionRecord: Codable, Identifiable {
    var id: UUID
    var caregiverID: UUID
    var subtypeID: UUID
    var started: Date
    var stopped: Date?
    var note: String?
    var note2: String?
    var createdAt: Date?
    var editedAt: Date?
    var profileReferenceID: UUID?
    var lastEditedBy: UUID?
    private var shouldEncodeCaregiverID = true

    init?(action: BabyActionSnapshot, caregiverID: UUID, profileID: UUID, shouldEncodeCaregiverID: Bool = true) {
        guard let subtypeID = SupabaseAuthManager.resolveSubtypeID(for: action) else { return nil }
        self.id = action.id
        self.caregiverID = caregiverID
        self.subtypeID = subtypeID
        self.started = action.startDate.normalizedToUTC()
        self.stopped = action.endDate?.normalizedToUTC()
        self.note = SupabaseAuthManager.resolveNote(for: action)
        self.note2 = profileID.uuidString
        self.createdAt = action.startDate.normalizedToUTC()
        self.editedAt = action.updatedAt
        self.profileReferenceID = profileID
        self.lastEditedBy = caregiverID
        self.shouldEncodeCaregiverID = shouldEncodeCaregiverID
    }

    var profileID: UUID? {
        if let profileReferenceID { return profileReferenceID }
        guard let note2 else { return nil }
        return UUID(uuidString: note2)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case caregiverIDLower = "caregiver_id"
        case caregiverIDLegacy = "Caregiver_Id"
        case subtypeIDLower = "subtype_id"
        case subtypeIDLegacy = "Subtype_Id"
        case startedAt = "started_at"
        case startedLegacy = "Started"
        case startedLower = "started"
        case stoppedAt = "stopped_at"
        case stoppedLegacy = "Stopped"
        case stoppedLower = "stopped"
        case noteLower = "note"
        case noteLegacy = "Note"
        case note2Lower = "note2"
        case note2Legacy = "Note2"
        case createdAt = "created_at"
        case editedAt = "edited_at"
        case updatedAt = "updated_at"
        case profileIDLower = "profile_id"
        case profileIDLegacy = "Profile_Id"
        case lastEditedBy = "last_edited_by"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        caregiverID = try container.decode(UUID.self, forKeys: [.caregiverIDLower, .caregiverIDLegacy])
        subtypeID = try container.decode(UUID.self, forKeys: [.subtypeIDLower, .subtypeIDLegacy])
        started = try container.decode(Date.self, forKeys: [.startedAt, .startedLower, .startedLegacy])
        stopped = try container.decodeIfPresent(Date.self, forKeys: [.stoppedAt, .stoppedLower, .stoppedLegacy])
        note = try container.decodeIfPresent(String.self, forKeys: [.noteLower, .noteLegacy])
        note2 = try container.decodeIfPresent(String.self, forKeys: [.note2Lower, .note2Legacy])
        createdAt = try container.decodeIfPresent(Date.self, forKeys: [.createdAt])
        let editedTimestamp = try container.decodeIfPresent(Date.self, forKeys: [.editedAt])
        let updatedTimestamp = try container.decodeIfPresent(Date.self, forKeys: [.updatedAt])
        editedAt = editedTimestamp ?? updatedTimestamp
        let rawProfileIdentifier = try container.decodeIfPresent(String.self, forKeys: [.profileIDLower, .profileIDLegacy])
        if let normalizedProfileIdentifier = rawProfileIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
           normalizedProfileIdentifier.isEmpty == false {
            if let parsedProfileIdentifier = UUID(uuidString: normalizedProfileIdentifier) {
                profileReferenceID = parsedProfileIdentifier
            } else {
                profileReferenceID = nil
            }
        } else {
            profileReferenceID = nil
        }

        if profileReferenceID == nil, let rawNote2 = note2 {
            profileReferenceID = UUID(uuidString: rawNote2)
        }

        lastEditedBy = try container.decodeIfPresent(UUID.self, forKey: .lastEditedBy)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        if shouldEncodeCaregiverID {
            try container.encode(caregiverID, forKey: .caregiverIDLower)
        }
        try container.encode(subtypeID, forKey: .subtypeIDLower)
        try container.encode(started, forKey: .startedAt)
        if let stopped {
            try container.encode(stopped, forKey: .stoppedAt)
        } else {
            try container.encodeNil(forKey: .stoppedAt)
        }
        if let note {
            try container.encode(note, forKey: .noteLower)
        } else {
            try container.encodeNil(forKey: .noteLower)
        }
        if let note2 {
            try container.encode(note2, forKey: .note2Lower)
        } else {
            try container.encodeNil(forKey: .note2Lower)
        }
        if let profileReferenceID {
            try container.encode(profileReferenceID, forKey: .profileIDLower)
        } else {
            try container.encodeNil(forKey: .profileIDLower)
        }
        if let createdAt {
            try container.encode(createdAt, forKey: .createdAt)
        } else {
            try container.encodeNil(forKey: .createdAt)
        }
        if let editedAt {
            try container.encode(editedAt, forKey: .editedAt)
        } else {
            try container.encodeNil(forKey: .editedAt)
        }
        if let lastEditedBy {
            try container.encode(lastEditedBy, forKey: .lastEditedBy)
        } else {
            try container.encodeNil(forKey: .lastEditedBy)
        }
    }

    func withoutCaregiverIDUpdates() -> BabyActionRecord {
        var record = self
        record.shouldEncodeCaregiverID = false
        return record
    }
}

private enum SupabaseActionSubtypeID {
    static let sleep = UUID(uuidString: "f0c1dc20-19b2-4fbd-865a-238548df3744")!
    static let pee = UUID(uuidString: "28a7600c-e58a-4806-a46a-b9732a4d2db6")!
    static let poo = UUID(uuidString: "171b6d76-4eaa-405d-a328-0a5f7dddb169")!
    static let peeAndPoo = UUID(uuidString: "bf8ae717-96ab-4814-8d8f-b0d5670fe0ee")!
    static let bottleFormula = UUID(uuidString: "50fda70f-6828-4364-b030-dfc4f5c7f98a")!
    static let bottleBreastMilk = UUID(uuidString: "173128c8-1b16-4e36-be6a-892ad0e021ec")!
    static let bottleCowMilk = UUID(uuidString: "54d9a6e7-4f3e-4967-bd73-6efd74555fa5")!
    static let meal = UUID(uuidString: "dbb27605-c426-4185-b3b6-f703b35b986d")!
    static let leftBreast = UUID(uuidString: "a4e20539-c7e2-4ef3-b04e-ad3665602588")!
    static let rightBreast = UUID(uuidString: "43572b05-637a-4a5b-a85c-ce9c47a08aa5")!
}

extension SupabaseAuthManager {
    enum SnapshotError: Error {
        case clientUnavailable
        case invalidPayload
    }

    enum AvatarDownloadError: LocalizedError {
        case missingSession
        case invalidResponse
        case httpStatus(Int)

        var errorDescription: String? {
            switch self {
            case .missingSession:
                return "Missing Supabase session for avatar download."
            case .invalidResponse:
                return "Invalid response while downloading avatar."
            case .httpStatus(let code):
                return "Avatar download failed with status \(code)."
            }
        }
    }

    struct CaregiverSnapshot: Sendable {
        private let caregiverID: UUID
        private let profiles: [BabyProfileRecord]
        private let actions: [BabyActionRecord]
        private let explicitProfileIdentifiers: Set<UUID>
        private let sharedPermissions: [UUID: ProfileSharePermission]
        private let sharedStatuses: [UUID: ProfileShareStatus]

        fileprivate init(caregiverID: UUID,
                         profiles: [BabyProfileRecord],
                         actions: [BabyActionRecord],
                         sharePermissions: [UUID: ProfileSharePermission] = [:],
                         shareStatuses: [UUID: ProfileShareStatus] = [:],
                         explicitProfileIdentifiers: Set<UUID> = []) {
            self.caregiverID = caregiverID
            self.profiles = profiles
            self.actions = actions
            self.sharedPermissions = sharePermissions
            self.sharedStatuses = shareStatuses
            self.explicitProfileIdentifiers = explicitProfileIdentifiers
        }

        init(actionsByProfile: [UUID: [BabyActionSnapshot]], caregiverID: UUID = UUID()) {
            var actionRecords: [BabyActionRecord] = []
            for (profileID, snapshots) in actionsByProfile {
                for snapshot in snapshots {
                    guard let record = BabyActionRecord(action: snapshot,
                                                        caregiverID: caregiverID,
                                                        profileID: profileID) else { continue }
                    actionRecords.append(record)
                }
            }
            self.init(caregiverID: caregiverID,
                      profiles: [],
                      actions: actionRecords,
                      sharePermissions: [:],
                      shareStatuses: [:],
                      explicitProfileIdentifiers: Set(actionsByProfile.keys))
        }

        var profileIdentifiers: Set<UUID> {
            var identifiers = Set(profiles.map(\.id))
            identifiers.formUnion(explicitProfileIdentifiers)
            for record in actions {
                if let profileID = record.profileID {
                    identifiers.insert(profileID)
                }
            }
            return identifiers
        }

        var actionsByProfile: [UUID: [BabyActionSnapshot]] {
            var grouped: [UUID: [BabyActionSnapshot]] = [:]

            for record in actions {
                guard let profileID = record.profileID,
                      let snapshot = SupabaseAuthManager.makeSnapshot(from: record) else { continue }
                grouped[profileID, default: []].append(snapshot)
            }

            for identifier in profileIdentifiers where grouped[identifier] == nil {
                grouped[identifier] = []
            }

            for (key, value) in grouped {
                grouped[key] = value.sorted(by: { $0.startDate > $1.startDate })
            }

            return grouped
        }

        var actionIdentifiersByProfile: [UUID: Set<UUID>] {
            actions.reduce(into: [UUID: Set<UUID>]()) { partialResult, record in
                guard let profileID = record.profileID else { return }
                partialResult[profileID, default: []].insert(record.id)
            }
        }

        var metadataUpdates: [ProfileStore.ProfileMetadataUpdate] {
            profiles.map { $0.asMetadataUpdate() }
        }

        var profileCount: Int {
            profiles.count
        }

        var actionCount: Int {
            actions.count
        }

        var sharedProfileIDs: Set<UUID> {
            Set(sharedStatuses.keys)
        }

        var shareStatuses: [UUID: ProfileShareStatus] {
            sharedStatuses
        }

        var profilePermissions: [UUID: ProfileSharePermission] {
            var permissions = sharedPermissions

            for profile in profiles {
                if profile.caregiverID == caregiverID {
                    permissions[profile.id] = .edit
                } else if permissions[profile.id] == nil {
                    permissions[profile.id] = .view
                }
            }

            for identifier in profileIdentifiers where permissions[identifier] == nil {
                permissions[identifier] = .view
            }

            return permissions
        }
    }

    nonisolated static func resolveSubtypeID(for action: BabyActionSnapshot) -> UUID? {
        switch action.category {
        case .sleep:
            return SupabaseActionSubtypeID.sleep
        case .diaper:
            switch action.diaperType ?? .both {
            case .pee:
                return SupabaseActionSubtypeID.pee
            case .poo:
                return SupabaseActionSubtypeID.poo
            case .both:
                return SupabaseActionSubtypeID.peeAndPoo
            }
        case .feeding:
            if let feedingType = action.feedingType {
                switch feedingType {
                case .bottle:
                    let bottleType = action.bottleType ?? .formula
                    switch bottleType {
                    case .formula:
                        return SupabaseActionSubtypeID.bottleFormula
                    case .breastMilk:
                        return SupabaseActionSubtypeID.bottleBreastMilk
                    case .cowMilk:
                        return SupabaseActionSubtypeID.bottleCowMilk
                    }
                case .leftBreast:
                    return SupabaseActionSubtypeID.leftBreast
                case .rightBreast:
                    return SupabaseActionSubtypeID.rightBreast
                case .meal:
                    return SupabaseActionSubtypeID.meal
                }
            } else if action.bottleVolume != nil || action.bottleType != nil {
                let bottleType = action.bottleType ?? .formula
                switch bottleType {
                case .formula:
                    return SupabaseActionSubtypeID.bottleFormula
                case .breastMilk:
                    return SupabaseActionSubtypeID.bottleBreastMilk
                case .cowMilk:
                    return SupabaseActionSubtypeID.bottleCowMilk
                }
            } else {
                return SupabaseActionSubtypeID.meal
            }
        }
    }

    nonisolated static func resolveNote(for action: BabyActionSnapshot) -> String? {
        var components: [String] = []

        if let volume = action.bottleVolume, volume > 0 {
            components.append("volume=\(volume)")
        }

        if let placename = action.placename?.trimmingCharacters(in: .whitespacesAndNewlines), placename.isEmpty == false {
            components.append("place=\(placename)")
        }

        if let latitude = action.latitude, let longitude = action.longitude {
            let formatted = String(format: "coords=%.6f,%.6f",
                                   locale: Locale(identifier: "en_US_POSIX"),
                                   latitude, longitude)
            components.append(formatted)
        }

        return components.isEmpty ? nil : components.joined(separator: ";")
    }

    private nonisolated static func makeSnapshot(from record: BabyActionRecord) -> BabyActionSnapshot? {
        let metadata = parseMetadata(from: record.note)
        let baseUpdatedAt = record.editedAt ?? record.createdAt ?? record.stopped ?? record.started

        switch record.subtypeID {
        case SupabaseActionSubtypeID.sleep:
            return BabyActionSnapshot(
                id: record.id,
                category: .sleep,
                startDate: record.started,
                endDate: record.stopped,
                latitude: metadata.latitude,
                longitude: metadata.longitude,
                placename: metadata.placename,
                updatedAt: baseUpdatedAt
            ).withValidatedDates()
        case SupabaseActionSubtypeID.pee:
            return BabyActionSnapshot(
                id: record.id,
                category: .diaper,
                startDate: record.started,
                endDate: record.stopped,
                diaperType: .pee,
                latitude: metadata.latitude,
                longitude: metadata.longitude,
                placename: metadata.placename,
                updatedAt: baseUpdatedAt
            ).withValidatedDates()
        case SupabaseActionSubtypeID.poo:
            return BabyActionSnapshot(
                id: record.id,
                category: .diaper,
                startDate: record.started,
                endDate: record.stopped,
                diaperType: .poo,
                latitude: metadata.latitude,
                longitude: metadata.longitude,
                placename: metadata.placename,
                updatedAt: baseUpdatedAt
            ).withValidatedDates()
        case SupabaseActionSubtypeID.peeAndPoo:
            return BabyActionSnapshot(
                id: record.id,
                category: .diaper,
                startDate: record.started,
                endDate: record.stopped,
                diaperType: .both,
                latitude: metadata.latitude,
                longitude: metadata.longitude,
                placename: metadata.placename,
                updatedAt: baseUpdatedAt
            ).withValidatedDates()
        case SupabaseActionSubtypeID.bottleFormula:
            return BabyActionSnapshot(
                id: record.id,
                category: .feeding,
                startDate: record.started,
                endDate: record.stopped,
                feedingType: .bottle,
                bottleType: .formula,
                bottleVolume: metadata.volume,
                latitude: metadata.latitude,
                longitude: metadata.longitude,
                placename: metadata.placename,
                updatedAt: baseUpdatedAt
            ).withValidatedDates()
        case SupabaseActionSubtypeID.bottleBreastMilk:
            return BabyActionSnapshot(
                id: record.id,
                category: .feeding,
                startDate: record.started,
                endDate: record.stopped,
                feedingType: .bottle,
                bottleType: .breastMilk,
                bottleVolume: metadata.volume,
                latitude: metadata.latitude,
                longitude: metadata.longitude,
                placename: metadata.placename,
                updatedAt: baseUpdatedAt
            ).withValidatedDates()
        case SupabaseActionSubtypeID.bottleCowMilk:
            return BabyActionSnapshot(
                id: record.id,
                category: .feeding,
                startDate: record.started,
                endDate: record.stopped,
                feedingType: .bottle,
                bottleType: .cowMilk,
                bottleVolume: metadata.volume,
                latitude: metadata.latitude,
                longitude: metadata.longitude,
                placename: metadata.placename,
                updatedAt: baseUpdatedAt
            ).withValidatedDates()
        case SupabaseActionSubtypeID.meal:
            return BabyActionSnapshot(
                id: record.id,
                category: .feeding,
                startDate: record.started,
                endDate: record.stopped,
                feedingType: .meal,
                latitude: metadata.latitude,
                longitude: metadata.longitude,
                placename: metadata.placename,
                updatedAt: baseUpdatedAt
            ).withValidatedDates()
        case SupabaseActionSubtypeID.leftBreast:
            return BabyActionSnapshot(
                id: record.id,
                category: .feeding,
                startDate: record.started,
                endDate: record.stopped,
                feedingType: .leftBreast,
                latitude: metadata.latitude,
                longitude: metadata.longitude,
                placename: metadata.placename,
                updatedAt: baseUpdatedAt
            ).withValidatedDates()
        case SupabaseActionSubtypeID.rightBreast:
            return BabyActionSnapshot(
                id: record.id,
                category: .feeding,
                startDate: record.started,
                endDate: record.stopped,
                feedingType: .rightBreast,
                latitude: metadata.latitude,
                longitude: metadata.longitude,
                placename: metadata.placename,
                updatedAt: baseUpdatedAt
            ).withValidatedDates()
        default:
            return nil
        }
    }

    nonisolated static func parseMetadata(from note: String?) -> (volume: Int?, placename: String?, latitude: Double?, longitude: Double?) {
        guard let note, note.isEmpty == false else { return (nil, nil, nil, nil) }

        var volume: Int?
        var placename: String?
        var latitude: Double?
        var longitude: Double?

        let components = note.split(separator: ";")

        for component in components {
            let parts = component.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            let key = parts[0]
            let value = parts[1]

            switch key {
            case "volume":
                if let parsed = Int(value) {
                    volume = parsed
                }
            case "place":
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty == false {
                    placename = trimmed
                }
            case "coords":
                let coordinateParts = value.split(separator: ",", maxSplits: 1)
                if coordinateParts.count == 2,
                   let lat = Double(coordinateParts[0]),
                   let lon = Double(coordinateParts[1]) {
                    latitude = lat
                    longitude = lon
                }
            default:
                continue
            }
        }

        return (volume, placename, latitude, longitude)
    }

    private func decodeResponse<T: Decodable>(_ value: Any,
                                              decoder: JSONDecoder,
                                              context: String) throws -> T {
        if let data = value as? Data {
            return try decodePayload(decoder: decoder, data: data, context: context)
        }

        if let typedValue = value as? T {
            return typedValue
        }

        if value is NSNull {
            let empty = Data("[]".utf8)
            return try decodePayload(decoder: decoder, data: empty, context: context)
        }

        guard JSONSerialization.isValidJSONObject(value) else {
            throw SnapshotError.invalidPayload
        }

        if let dictionary = value as? [String: Any] {
            if let nested = dictionary["data"] {
                let data = try JSONSerialization.data(withJSONObject: nested)
                return try decodePayload(decoder: decoder, data: data, context: context)
            } else if dictionary["count"] != nil {
                let empty = Data("[]".utf8)
                return try decodePayload(decoder: decoder, data: empty, context: context)
            }
        }

        let data = try JSONSerialization.data(withJSONObject: value)
        return try decodePayload(decoder: decoder, data: data, context: context)
    }

    private func decodePayload<T: Decodable>(decoder: JSONDecoder,
                                             data: Data,
                                             context: String) throws -> T {
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw error
        }
    }

    private static func decodingErrorDetails(from error: Error) -> String {
        guard let decodingError = error as? DecodingError else { return "n/a" }

        func pathDescription(_ path: [CodingKey]) -> String {
            let components = path.map { key -> String in
                if let intValue = key.intValue {
                    return "[\(intValue)]"
                }
                return key.stringValue
            }
            return components.isEmpty ? "<root>" : components.joined(separator: ".")
        }

        switch decodingError {
        case let .typeMismatch(_, context):
            return "typeMismatch path=\(pathDescription(context.codingPath)) reason=\(context.debugDescription)"
        case let .valueNotFound(_, context):
            return "valueNotFound path=\(pathDescription(context.codingPath)) reason=\(context.debugDescription)"
        case let .keyNotFound(key, context):
            return "keyNotFound missing=\(key.stringValue) path=\(pathDescription(context.codingPath)) reason=\(context.debugDescription)"
        case let .dataCorrupted(context):
            return "dataCorrupted path=\(pathDescription(context.codingPath)) reason=\(context.debugDescription)"
        @unknown default:
            return "unknown decoding error"
        }
    }

}

private extension KeyedDecodingContainer {
    func decode<T: Decodable>(_ type: T.Type, forKeys keys: [Key]) throws -> T {
        for key in keys {
            if let value = try decodeIfPresent(type, forKey: key) {
                return value
            }
        }

        if let firstKey = keys.first {
            throw DecodingError.keyNotFound(firstKey, DecodingError.Context(
                codingPath: codingPath,
                debugDescription: "Missing value for keys: \(keys.map(\.stringValue).joined(separator: ", "))"
            ))
        }

        throw DecodingError.dataCorrupted(DecodingError.Context(
            codingPath: codingPath,
            debugDescription: "No keys provided for decoding"
        ))
    }

    func decodeIfPresent<T: Decodable>(_ type: T.Type, forKeys keys: [Key]) throws -> T? {
        for key in keys {
            if let value = try decodeIfPresent(type, forKey: key) {
                return value
            }
        }
        return nil
    }
}
