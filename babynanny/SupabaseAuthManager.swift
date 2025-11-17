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

    private let client: SupabaseClient?
    private let supabaseAnonKey: String?
    private let supabaseBaseURL: URL?
    private let logger = Logger(subsystem: "com.prioritybit.babynanny", category: "supabase-actions")
    fileprivate static let snapshotLogger = Logger(
        subsystem: "com.prioritybit.babynanny",
        category: "supabase-snapshot"
    )
    private var hasSynchronizedCaregiverDataForCurrentSession = false
    private var currentAppleNonce: String?
    private var currentAccessToken: String?
    private static let emailVerificationRedirectURL = URL(string: "nannyme://auth/verify")
    private static let profilePhotosBucketName = "ProfilePhotos"

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
        do {
            let session = try await client.auth.session(from: url)
            apply(session: session)
        } catch {
            lastErrorMessage = Self.userFriendlyMessage(from: error)
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
                logger.log("Resolved caregiver ID from Supabase session during snapshot fetch.")
            }

            let snapshot = try await fetchCaregiverSnapshotFromSupabase()
            return snapshot
        } catch {
            lastErrorMessage = Self.userFriendlyMessage(from: error)
            let detail = Self.decodingErrorDetails(from: error)
            if detail == "n/a" {
                logger.error("Failed to fetch caregiver snapshot: \(error.localizedDescription, privacy: .public)")
            } else {
                logger.error("Failed to fetch caregiver snapshot: \(error.localizedDescription, privacy: .public) detail=\(detail, privacy: .public)")
            }
            return nil
        }
    }

    func upsertBabyProfiles(_ profiles: [ChildProfile]) async {
        guard let client, isAuthenticated, let caregiverID = currentUserID else { return }
        guard profiles.isEmpty == false else { return }

        do {
            let records = try await makeBabyProfileRecords(from: profiles,
                                                            caregiverID: caregiverID,
                                                            client: client)

            guard records.isEmpty == false else { return }

            _ = try await client.database
                .from("baby_profiles")
                .upsert(records, onConflict: "id", returning: .minimal)
                .execute()
        } catch {
            lastErrorMessage = Self.userFriendlyMessage(from: error)
        }
    }

    func syncBabyActions(upserting actions: [BabyActionSnapshot],
                         deletingIDs: [UUID],
                         profileID: UUID) async {
        guard let client, isAuthenticated, let caregiverID = currentUserID else { return }

        let sanitizedActions = actions.map { $0.withValidatedDates() }
        let records = sanitizedActions.compactMap { action in
            BabyActionRecord(action: action, caregiverID: caregiverID, profileID: profileID)
        }

        let shouldUpsert = records.isEmpty == false
        let shouldDelete = deletingIDs.isEmpty == false

        guard shouldUpsert || shouldDelete else { return }

        if records.count < sanitizedActions.count {
            logger.warning("Skipping \(sanitizedActions.count - records.count, privacy: .public) actions without a Supabase subtype mapping")
        }

        do {
            if shouldUpsert {
                _ = try await client.database
                    .from("baby_action")
                    .upsert(records, onConflict: "id", returning: .minimal)
                    .execute()
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
            logger.error("Failed to synchronize baby actions: \(error.localizedDescription, privacy: .public)")
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

        _ = try await client.database
            .from("caregivers")
            .upsert([record], onConflict: "id", returning: .minimal)
            .execute()
    }

    private func upsertBabyProfiles(_ profiles: [ChildProfile], caregiverID: UUID) async throws {
        guard let client else { return }

        let records = try await makeBabyProfileRecords(from: profiles,
                                                       caregiverID: caregiverID,
                                                       client: client)
        guard records.isEmpty == false else { return }

        _ = try await client.database
            .from("baby_profiles")
            .upsert(records, onConflict: "id", returning: .minimal)
            .execute()
    }

    private func makeBabyProfileRecords(from profiles: [ChildProfile],
                                        caregiverID: UUID,
                                        client: SupabaseClient) async throws -> [BabyProfileRecord] {
        guard profiles.isEmpty == false else { return [] }

        var records: [BabyProfileRecord] = []
        records.reserveCapacity(profiles.count)

        for profile in profiles {
            let avatarURL = try await resolveAvatarURL(for: profile,
                                                       caregiverID: caregiverID,
                                                       client: client)
            let shouldClearAvatar = profile.imageData == nil && profile.avatarURL == nil
            let record = BabyProfileRecord(profile: profile,
                                           caregiverID: caregiverID,
                                           avatarURL: avatarURL,
                                           shouldClearAvatar: shouldClearAvatar)
            records.append(record)
        }

        return records
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
            logger.error("Failed to upload profile avatar: \(error.localizedDescription, privacy: .public)")
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

        Self.snapshotLogger.log("Fetching caregiver snapshot using RLS policies")

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
        logRawSupabaseResponse(profilesResponse.value, context: "profiles")

        let actionsResponse: PostgrestResponse<[BabyActionRecord]> = try await client.database
            .from("baby_action")
            .select()
            .execute()
        logRawSupabaseResponse(actionsResponse.value, context: "actions")

        let profileRecords: [BabyProfileRecord] = try decodeResponse(profilesResponse.value,
                                                                     decoder: decoder,
                                                                     context: "profiles")
        let actionRecords: [BabyActionRecord] = try decodeResponse(actionsResponse.value,
                                                                   decoder: decoder,
                                                                   context: "actions")

        let shareStates = try await fetchShareStates(for: caregiverID, client: client)

        Self.snapshotLogger.log("Decoded snapshot successfully. profiles=\(profileRecords.count, privacy: .public) actions=\(actionRecords.count, privacy: .public)")
        for record in profileRecords {
            if let avatarURL = record.avatarURL, avatarURL.isEmpty == false {
                Self.snapshotLogger.log("Profile \(record.id.uuidString, privacy: .public) avatar_url=\(avatarURL, privacy: .public)")
            } else {
                Self.snapshotLogger.log("Profile \(record.id.uuidString, privacy: .public) missing avatar_url")
            }
        }

        return CaregiverSnapshot(caregiverID: caregiverID,
                                 profiles: profileRecords,
                                 actions: actionRecords,
                                 shareStates: shareStates)
    }

    private func fetchShareStates(for caregiverID: UUID,
                                  client: SupabaseClient) async throws -> [UUID: CaregiverSnapshot.ProfileShareState] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom(SupabaseDateDecoder.decode)

        let response: PostgrestResponse<[BabyProfileSharePermissionRecord]> = try await client.database
            .from("baby_profile_shares")
            .select("id, baby_profile_id, permission, status")
            .eq("recipient_caregiver_id", value: caregiverID.uuidString.lowercased())
            .execute()

        let records: [BabyProfileSharePermissionRecord] = try decodeResponse(response.value,
                                                                             decoder: decoder,
                                                                             context: "profile-share-permissions")

        var states: [UUID: CaregiverSnapshot.ProfileShareState] = [:]

        for record in records {
            let permission = record.permission.flatMap { ProfileSharePermission(rawValue: $0.lowercased()) } ?? .view
            let rawStatus = record.status?.lowercased()
            let status = rawStatus.flatMap { ProfileShareStatus(rawValue: $0) } ?? .pending
            let state = CaregiverSnapshot.ProfileShareState(permission: permission,
                                                            status: status,
                                                            invitationID: record.id)
            states[record.babyProfileID] = state
        }

        return states
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
            logger.error("Supabase delete failure for profile \(identifier, privacy: .public): \(error.localizedDescription, privacy: .public)")
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

        logger.log("Deleting baby_action entries by profile_id for profile \(identifier, privacy: .public)")
        do {
            let response: PostgrestResponse<Void> = try await client.database
                .from("baby_action")
                .delete()
                .eq("profile_id", value: normalizedIdentifier)
                .execute(options: .init(count: .exact))

            let deletedCount = response.count ?? 0
            logger.log("Supabase delete baby_action response for profile \(identifier, privacy: .public): status=\(response.response.statusCode, privacy: .public) deleted_rows=\(deletedCount, privacy: .public)")
            logger.log("Deleted baby_action entries for profile \(identifier, privacy: .public)")
        } catch {
            recordError(error)
        }


        guard recordedError == nil else {
            lastErrorMessage = Self.userFriendlyMessage(from: recordedError!)
            return
        }

        logger.log("Deleting baby_profile_shares entries for profile \(identifier, privacy: .public)")
        do {
            _ = try await client.database
                .from("baby_profile_shares")
                .delete()
                .eq("baby_profile_id", value: identifier)
                .execute()
            logger.log("Deleted baby_profile_shares entries for profile \(identifier, privacy: .public)")
        } catch {
            recordError(error)
        }

        guard recordedError == nil else {
            lastErrorMessage = Self.userFriendlyMessage(from: recordedError!)
            return
        }

        logger.log("Deleting baby_profiles entry for profile \(identifier, privacy: .public)")
        do {
            _ = try await client.database
                .from("baby_profiles")
                .delete()
                .eq("id", value: identifier)
                .execute()
            logger.log("Deleted baby_profiles entry for profile \(identifier, privacy: .public)")
        } catch {
            recordError(error)
        }

        if let recordedError {
            lastErrorMessage = Self.userFriendlyMessage(from: recordedError)
        }
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
                status: nil
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

    func respondToShareInvitation(shareID: UUID,
                                  status: ProfileShareStatus) async -> Result<Void, ProfileShareOperationError> {
        guard let client else {
            let message = configurationError ?? L10n.ShareData.Supabase.failureConfiguration
            return .failure(ProfileShareOperationError(message: message))
        }

        guard isAuthenticated, let recipientID = currentUserID else {
            return .failure(ProfileShareOperationError(message: L10n.ShareData.Supabase.notAuthenticated))
        }

        do {
            let update = BabyProfileShareStatusUpdate(status: status.rawValue)
            _ = try await client.database
                .from("baby_profile_shares")
                .update(update)
                .eq("id", value: shareID.uuidString)
                .eq("recipient_caregiver_id", value: recipientID.uuidString)
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
    var dateOfBirth: String?
    var avatarURL: String?
    var createdAt: Date?
    var editedAt: Date?
    private var shouldClearAvatarOnUpload = false

    init(profile: ChildProfile,
         caregiverID: UUID,
         avatarURL: String?,
         shouldClearAvatar: Bool) {
        id = profile.id
        self.caregiverID = caregiverID
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
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(caregiverID, forKey: .caregiverID)
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
    var id: UUID
    var babyProfileID: UUID
    var permission: String?
    var status: String?

    enum CodingKeys: String, CodingKey {
        case id
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
    private static let decodingLogger = Logger(subsystem: "com.prioritybit.babynanny", category: "supabase-actions-decoding")

    init?(action: BabyActionSnapshot, caregiverID: UUID, profileID: UUID) {
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
                let identifier = id.uuidString
                let rawValue = normalizedProfileIdentifier
                Self.decodingLogger.warning("Dropping non-UUID profile identifier for baby_action id=\(identifier, privacy: .public). rawValue=\(rawValue, privacy: .public)")
            }
        } else {
            profileReferenceID = nil
        }

        if profileReferenceID == nil, let rawNote2 = note2 {
            profileReferenceID = UUID(uuidString: rawNote2)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(caregiverID, forKey: .caregiverIDLower)
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
    }
}

private enum SupabaseActionSubtypeID {
    static let sleep = UUID(uuidString: "f0c1dc20-19b2-4fbd-865a-238548df3744")!
    static let pee = UUID(uuidString: "28a7600c-e58a-4806-a46a-b9732a4d2db6")!
    static let poo = UUID(uuidString: "171b6d76-4eaa-405d-a328-0a5f7dddb169")!
    static let peeAndPoo = UUID(uuidString: "bf8ae717-96ab-4814-8d8f-b0d5670fe0ee")!
    static let bottleFormula = UUID(uuidString: "50fda70f-6828-4364-b030-dfc4f5c7f98a")!
    static let bottleBreastMilk = UUID(uuidString: "173128c8-1b16-4e36-be6a-892ad0e021ec")!
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
        struct ProfileShareState: Sendable {
            let permission: ProfileSharePermission
            let status: ProfileShareStatus
            let invitationID: UUID?
        }

        private let shareStates: [UUID: ProfileShareState]

        fileprivate init(caregiverID: UUID,
                         profiles: [BabyProfileRecord],
                         actions: [BabyActionRecord],
                         shareStates: [UUID: ProfileShareState] = [:],
                         explicitProfileIdentifiers: Set<UUID> = []) {
            self.caregiverID = caregiverID
            self.profiles = profiles
            self.actions = actions
            self.shareStates = shareStates
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
                      shareStates: [:],
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
            Set(shareStates.compactMap { identifier, state in
                switch state.status {
                case .revoked, .rejected:
                    return nil
                default:
                    return identifier
                }
            })
        }

        var profilePermissions: [UUID: ProfileSharePermission] {
            var permissions = shareStates.reduce(into: [UUID: ProfileSharePermission]()) { partialResult, element in
                partialResult[element.key] = element.value.permission
            }

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

        var profileShareStatuses: [UUID: ProfileShareStatus] {
            var statuses = shareStates.reduce(into: [UUID: ProfileShareStatus]()) { partialResult, element in
                partialResult[element.key] = element.value.status
            }

            for profile in profiles where statuses[profile.id] == nil {
                statuses[profile.id] = .accepted
            }

            for identifier in profileIdentifiers where statuses[identifier] == nil {
                statuses[identifier] = .accepted
            }

            return statuses
        }

        var profileShareInvitationIDs: [UUID: UUID] {
            shareStates.reduce(into: [UUID: UUID]()) { partialResult, element in
                if let invitationID = element.value.invitationID {
                    partialResult[element.key] = invitationID
                }
            }
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
        Self.snapshotLogger.log("Decoding \(context, privacy: .public) payload. incomingType=\(String(describing: type(of: value)), privacy: .public)")
        if let data = value as? Data {
            Self.snapshotLogger.log("\(context, privacy: .public) payload is raw Data with length \(data.count, privacy: .public)")
            logPayloadData(data, context: context)
            return try decodePayload(decoder: decoder, data: data, context: context)
        }

        if let typedValue = value as? T {
            Self.snapshotLogger.log("\(context, privacy: .public) payload already matches \(String(describing: T.self), privacy: .public); returning directly.")
            return typedValue
        }

        if value is NSNull {
            let empty = Data("[]".utf8)
            Self.snapshotLogger.log("\(context, privacy: .public) payload is NSNull; using empty array.")
            logPayloadData(empty, context: context)
            return try decodePayload(decoder: decoder, data: empty, context: context)
        }

        guard JSONSerialization.isValidJSONObject(value) else {
            Self.snapshotLogger.error("\(context, privacy: .public) payload is not valid JSON. value=\(String(describing: value), privacy: .private)")
            throw SnapshotError.invalidPayload
        }

        if let dictionary = value as? [String: Any] {
            if let nested = dictionary["data"] {
                let data = try JSONSerialization.data(withJSONObject: nested)
                logPayloadData(data, context: context)
                return try decodePayload(decoder: decoder, data: data, context: context)
            } else if dictionary["count"] != nil {
                let empty = Data("[]".utf8)
                Self.snapshotLogger.log("\(context, privacy: .public) payload contains only count; using empty array.")
                logPayloadData(empty, context: context)
                return try decodePayload(decoder: decoder, data: empty, context: context)
            }
        }

        let verboseDescription: String
        if let value = value as? CustomDebugStringConvertible {
            verboseDescription = value.debugDescription
        } else {
            verboseDescription = String(describing: value)
        }
        Self.snapshotLogger.log("\(context, privacy: .public) payload detail: \(verboseDescription, privacy: .public)")
        logger.log("Snapshot \(context, privacy: .public) payload detail: \(verboseDescription, privacy: .public)")
        let data = try JSONSerialization.data(withJSONObject: value)
        Self.snapshotLogger.log("\(context, privacy: .public) payload decoded from JSONObject of size \(data.count, privacy: .public)")
        logPayloadData(data, context: context)
        return try decodePayload(decoder: decoder, data: data, context: context)
    }

    private func decodePayload<T: Decodable>(decoder: JSONDecoder,
                                             data: Data,
                                             context: String) throws -> T {
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            let preview = payloadPreview(from: data)
            let detail = Self.decodingErrorDetails(from: error)
            Self.snapshotLogger.error("Decoding \(context, privacy: .public) failed: \(error.localizedDescription, privacy: .public). detail=\(detail, privacy: .public). payloadPreview=\(preview, privacy: .public)")
            logger.error("Decoding \(context, privacy: .public) failed: \(error.localizedDescription, privacy: .public). detail=\(detail, privacy: .public). payloadPreview=\(preview, privacy: .public)")
            throw error
        }
    }

    private func logPayloadData(_ data: Data, context: String) {
        let preview = payloadPreview(from: data)
        Self.snapshotLogger.log("\(context, privacy: .public) payload preview: \(preview, privacy: .public)")
        logger.log("Snapshot \(context, privacy: .public) payload preview: \(preview, privacy: .public)")
    }

    private func payloadPreview(from data: Data) -> String {
        if let string = String(data: data, encoding: .utf8) {
            let singleLine = string.replacingOccurrences(of: "\n", with: " ")
            if singleLine.count > 2000 {
                let prefix = singleLine.prefix(2000)
                return "\(prefix)… (truncated)"
            }
            return singleLine
        }

        let prefix = data.prefix(1024)
        return prefix.map { String(format: "%02hhx", $0) }.joined()
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

    private func logRawSupabaseResponse(_ value: Any?, context: String) {
        guard let value else {
            Self.snapshotLogger.log("Raw \(context, privacy: .public) response value is nil.")
            return
        }

        if let data = value as? Data {
            let preview = payloadPreview(from: data)
            Self.snapshotLogger.log("Raw \(context, privacy: .public) response data preview: \(preview, privacy: .public)")
            return
        }

        if JSONSerialization.isValidJSONObject(value),
           let jsonData = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted]) {
            let preview = payloadPreview(from: jsonData)
            Self.snapshotLogger.log("Raw \(context, privacy: .public) response JSON preview: \(preview, privacy: .public)")
            return
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
