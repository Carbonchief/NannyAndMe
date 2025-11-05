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
    private let logger = Logger(subsystem: "com.prioritybit.babynanny", category: "supabase-actions")
    private var hasSynchronizedCaregiverDataForCurrentSession = false
    private static let emailVerificationRedirectURL = URL(string: "nannyme://auth/verify")
    private static let iso8601DateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

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
            currentUserID = nil
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

    func prepareCaregiverAccount() async {
        guard let client, isAuthenticated else { return }
        guard hasSynchronizedCaregiverDataForCurrentSession == false else { return }

        do {
            let session = try await client.auth.session
            try await upsertCaregiver(for: session.user)
            hasSynchronizedCaregiverDataForCurrentSession = true
        } catch {
            hasSynchronizedCaregiverDataForCurrentSession = false
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
                    .from("Baby_Action")
                    .upsert(records, onConflict: "id", returning: .minimal)
                    .execute()
            }

            if shouldDelete {
                let identifiers = deletingIDs.map(\.uuidString)
                _ = try await client.database
                    .from("Baby_Action")
                    .delete()
                    .in(column: "id", values: identifiers)
                    .execute()
            }
        } catch {
            logger.error("Failed to synchronize baby actions: \(error.localizedDescription, privacy: .public)")
        }
    }

    func fetchRemoteBabyProfiles() async throws -> [RemoteBabyProfile] {
        guard let client, isAuthenticated, let caregiverID = currentUserID else { return [] }

        let response = try await client.database
            .from("baby_profiles")
            .select()
            .eq("caregiver_id", value: caregiverID.uuidString)
            .execute()

        let data = response.data
        guard data.isEmpty == false else { return [] }

        let decoder = Self.makeJSONDecoder()
        let records = try decoder.decode([BabyProfileRecord].self, from: data)
        return records.filter { $0.caregiverID == caregiverID }.map(RemoteBabyProfile.init)
    }

    func fetchRemoteBabyActions() async throws -> [RemoteBabyAction] {
        guard let client, isAuthenticated, let caregiverID = currentUserID else { return [] }

        let response = try await client.database
            .from("Baby_Action")
            .select()
            .eq("Caregiver_Id", value: caregiverID.uuidString)
            .execute()

        let data = response.data
        guard data.isEmpty == false else { return [] }

        let decoder = Self.makeJSONDecoder()
        let records = try decoder.decode([BabyActionRecord].self, from: data)
        return records
            .filter { $0.caregiverID == caregiverID }
            .compactMap(RemoteBabyAction.init)
    }

    func syncBabyProfiles(upserting profiles: [ChildProfile]) async {
        guard let client, isAuthenticated, let caregiverID = currentUserID else { return }

        let trimmedProfiles = profiles.filter { profile in
            profile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        }

        guard trimmedProfiles.isEmpty == false else { return }

        let records = trimmedProfiles.map { BabyProfileRecord(profile: $0, caregiverID: caregiverID) }

        do {
            _ = try await client.database
                .from("baby_profiles")
                .upsert(records, onConflict: "id", returning: .minimal)
                .execute()
        } catch {
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

        _ = try await client.database
            .from("caregivers")
            .upsert([record], onConflict: "id", returning: .minimal)
            .execute()
    }

    func deleteBabyProfile(withID id: UUID) async {
        guard let client, isAuthenticated else { return }

        do {
            _ = try await client.database
                .from("baby_profiles")
                .delete()
                .eq("id", value: id.uuidString)
                .execute()
        } catch {
            lastErrorMessage = Self.userFriendlyMessage(from: error)
        }
    }

    private func resolvedPasswordHash(from user: User) -> String {
        user.id.uuidString
    }

    static func userFriendlyMessage(from error: Error) -> String {
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

    private static func makeJSONDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            if let date = iso8601DateFormatter.date(from: value) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container,
                                                   debugDescription: "Invalid ISO 8601 date: \(value)")
        }
        return decoder
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
    var editedAt: Date

    init(profile: ChildProfile, caregiverID: UUID) {
        id = profile.id
        self.caregiverID = caregiverID
        name = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
        dateOfBirth = Self.dateFormatter.string(from: profile.birthDate)
        avatarURL = nil
        editedAt = profile.updatedAt
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
        case editedAt = "edited_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        caregiverID = try container.decode(UUID.self, forKey: .caregiverID)
        name = try container.decode(String.self, forKey: .name)
        dateOfBirth = try container.decode(String.self, forKey: .dateOfBirth)
        avatarURL = try container.decodeIfPresent(String.self, forKey: .avatarURL)
        editedAt = try container.decodeIfPresent(Date.self, forKey: .editedAt) ?? Date.distantPast
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(caregiverID, forKey: .caregiverID)
        try container.encode(name, forKey: .name)
        try container.encode(dateOfBirth, forKey: .dateOfBirth)
        try container.encodeIfPresent(avatarURL, forKey: .avatarURL)
        try container.encode(editedAt, forKey: .editedAt)
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
    var editedAt: Date

    init?(action: BabyActionSnapshot, caregiverID: UUID, profileID: UUID) {
        guard let subtypeID = SupabaseAuthManager.resolveSubtypeID(for: action) else { return nil }
        self.id = action.id
        self.caregiverID = caregiverID
        self.subtypeID = subtypeID
        self.started = action.startDate.normalizedToUTC()
        self.stopped = action.endDate?.normalizedToUTC()
        self.note = SupabaseAuthManager.resolveNote(for: action)
        self.note2 = profileID.uuidString
        self.editedAt = action.updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case caregiverID = "Caregiver_Id"
        case subtypeID = "Subtype_Id"
        case started = "Started"
        case stopped = "Stopped"
        case note = "Note"
        case note2 = "Note2"
        case editedAt = "Edited_At"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        caregiverID = try container.decode(UUID.self, forKey: .caregiverID)
        subtypeID = try container.decode(UUID.self, forKey: .subtypeID)
        started = try container.decode(Date.self, forKey: .started)
        stopped = try container.decodeIfPresent(Date.self, forKey: .stopped)
        note = try container.decodeIfPresent(String.self, forKey: .note)
        note2 = try container.decodeIfPresent(String.self, forKey: .note2)
        editedAt = try container.decodeIfPresent(Date.self, forKey: .editedAt) ?? Date.distantPast
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(caregiverID, forKey: .caregiverID)
        try container.encode(subtypeID, forKey: .subtypeID)
        try container.encode(started, forKey: .started)
        try container.encodeIfPresent(stopped, forKey: .stopped)
        try container.encodeIfPresent(note, forKey: .note)
        try container.encodeIfPresent(note2, forKey: .note2)
        try container.encode(editedAt, forKey: .editedAt)
    }
}

extension SupabaseAuthManager {
    struct RemoteBabyProfile: Sendable {
        var id: UUID
        var caregiverID: UUID
        var name: String
        var birthDate: Date?
        var editedAt: Date

        init(record: BabyProfileRecord) {
            id = record.id
            caregiverID = record.caregiverID
            name = record.name
            birthDate = BabyProfileRecord.dateFormatter.date(from: record.dateOfBirth)
            editedAt = record.editedAt
        }
    }

    struct RemoteBabyAction: Sendable {
        var id: UUID
        var profileID: UUID
        var snapshot: BabyActionSnapshot

        init?(record: BabyActionRecord) {
            guard let result = SupabaseAuthManager.makeSnapshot(from: record) else { return nil }
            id = record.id
            profileID = result.profileID
            snapshot = result.snapshot
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

private extension SupabaseAuthManager {
    static func resolveSubtypeID(for action: BabyActionSnapshot) -> UUID? {
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

    static func resolveNote(for action: BabyActionSnapshot) -> String? {
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

    private struct ActionComponents {
        var category: BabyActionCategory
        var diaperType: BabyActionSnapshot.DiaperType?
        var feedingType: BabyActionSnapshot.FeedingType?
        var bottleType: BabyActionSnapshot.BottleType?
    }

    static func resolveActionComponents(for subtypeID: UUID) -> ActionComponents? {
        switch subtypeID {
        case SupabaseActionSubtypeID.sleep:
            return ActionComponents(category: .sleep, diaperType: nil, feedingType: nil, bottleType: nil)
        case SupabaseActionSubtypeID.pee:
            return ActionComponents(category: .diaper, diaperType: .pee, feedingType: nil, bottleType: nil)
        case SupabaseActionSubtypeID.poo:
            return ActionComponents(category: .diaper, diaperType: .poo, feedingType: nil, bottleType: nil)
        case SupabaseActionSubtypeID.peeAndPoo:
            return ActionComponents(category: .diaper, diaperType: .both, feedingType: nil, bottleType: nil)
        case SupabaseActionSubtypeID.bottleFormula:
            return ActionComponents(category: .feeding, diaperType: nil, feedingType: .bottle, bottleType: .formula)
        case SupabaseActionSubtypeID.bottleBreastMilk:
            return ActionComponents(category: .feeding, diaperType: nil, feedingType: .bottle, bottleType: .breastMilk)
        case SupabaseActionSubtypeID.meal:
            return ActionComponents(category: .feeding, diaperType: nil, feedingType: .meal, bottleType: nil)
        case SupabaseActionSubtypeID.leftBreast:
            return ActionComponents(category: .feeding, diaperType: nil, feedingType: .leftBreast, bottleType: nil)
        case SupabaseActionSubtypeID.rightBreast:
            return ActionComponents(category: .feeding, diaperType: nil, feedingType: .rightBreast, bottleType: nil)
        default:
            return nil
        }
    }

    static func parseNote(_ note: String?) -> (volume: Int?, placename: String?, latitude: Double?, longitude: Double?) {
        guard let note, note.isEmpty == false else {
            return (nil, nil, nil, nil)
        }

        var volume: Int?
        var placename: String?
        var latitude: Double?
        var longitude: Double?

        let components = note.split(separator: ";")
        for component in components {
            let parts = component.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)

            switch key.lowercased() {
            case "volume":
                if let parsed = Int(value) {
                    volume = parsed
                }
            case "place":
                placename = value
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

    static func makeSnapshot(from record: BabyActionRecord) -> (profileID: UUID, snapshot: BabyActionSnapshot)? {
        guard let profileIdentifier = record.note2,
              let profileID = UUID(uuidString: profileIdentifier) else { return nil }
        guard let components = resolveActionComponents(for: record.subtypeID) else { return nil }

        let metadata = parseNote(record.note)

        let snapshot = BabyActionSnapshot(id: record.id,
                                           category: components.category,
                                           startDate: record.started,
                                           endDate: record.stopped,
                                           diaperType: components.diaperType,
                                           feedingType: components.feedingType,
                                           bottleType: components.bottleType,
                                           bottleVolume: metadata.volume,
                                           latitude: metadata.latitude,
                                           longitude: metadata.longitude,
                                           placename: metadata.placename,
                                           updatedAt: record.editedAt)
        return (profileID, snapshot)
    }
}
