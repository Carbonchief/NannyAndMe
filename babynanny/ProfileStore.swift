import Foundation
import SwiftUI

struct ChildProfile: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var birthDate: Date
    var imageData: Data?

    init(id: UUID = UUID(), name: String, birthDate: Date, imageData: Data? = nil) {
        self.id = id
        self.name = name
        self.birthDate = birthDate
        self.imageData = imageData
    }

    var displayName: String {
        name.isEmpty ? "New Profile" : name
    }
}

@MainActor
final class ProfileStore: ObservableObject {
    var profiles: [ChildProfile] {
        state.profiles
    }

    var activeProfileID: UUID? {
        state.activeProfileID
    }

    var activeProfile: ChildProfile {
        if let profile = state.activeProfile {
            return profile
        }

        ensureValidState()
        return state.activeProfile ?? ChildProfile(name: "", birthDate: Date())
    }

    private let saveURL: URL
    @Published private var state: ProfileState {
        didSet {
            persistState()
        }
    }

    init(
        fileManager: FileManager = .default,
        directory: URL? = nil,
        filename: String = "childProfiles.json"
    ) {
        self.saveURL = Self.resolveSaveURL(fileManager: fileManager, directory: directory, filename: filename)

        if let data = try? Data(contentsOf: saveURL) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            if let decoded = try? decoder.decode(ProfileState.self, from: data) {
                self.state = Self.sanitized(state: decoded)
            } else {
                self.state = Self.defaultState()
            }
        } else {
            self.state = Self.defaultState()
        }

        persistState()
    }

    init(
        initialProfiles: [ChildProfile],
        activeProfileID: UUID? = nil,
        fileManager: FileManager = .default,
        directory: URL? = nil,
        filename: String = "childProfiles.json"
    ) {
        self.saveURL = Self.resolveSaveURL(fileManager: fileManager, directory: directory, filename: filename)
        let state = ProfileState(profiles: initialProfiles, activeProfileID: activeProfileID)
        self.state = Self.sanitized(state: state)
        persistState()
    }

    func setActiveProfile(_ profile: ChildProfile) {
        guard state.profiles.contains(where: { $0.id == profile.id }) else { return }
        var newState = state
        newState.activeProfileID = profile.id
        state = Self.sanitized(state: newState)
    }

    func addProfile() {
        var newState = state
        let profile = ChildProfile(name: "", birthDate: Date())
        newState.profiles.append(profile)
        newState.activeProfileID = profile.id
        state = Self.sanitized(state: newState)
    }

    func updateActiveProfile(_ updates: (inout ChildProfile) -> Void) {
        guard let activeID = state.activeProfileID,
              let index = state.profiles.firstIndex(where: { $0.id == activeID }) else { return }

        var newState = state
        updates(&newState.profiles[index])
        state = Self.sanitized(state: newState)
    }

    private func ensureValidState() {
        let sanitized = Self.sanitized(state: state)
        if sanitized != state {
            state = sanitized
        }
    }

    private func persistState() {
        let stateSnapshot = state
        let url = saveURL

        Task.detached(priority: .background) {
            do {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                let data = try encoder.encode(stateSnapshot)
                try data.write(to: url, options: .atomic)
            } catch {
                #if DEBUG
                print("Failed to save child profiles: \(error.localizedDescription)")
                #endif
            }
        }
    }

    private static func sanitized(state: ProfileState?) -> ProfileState {
        var state = state ?? ProfileState(profiles: [], activeProfileID: nil)

        if state.profiles.isEmpty {
            let defaultProfile = ChildProfile(name: "", birthDate: Date())
            state.profiles = [defaultProfile]
            state.activeProfileID = defaultProfile.id
        } else if let activeID = state.activeProfileID,
                  state.profiles.contains(where: { $0.id == activeID }) == false {
            state.activeProfileID = state.profiles.first?.id
        } else if state.activeProfileID == nil {
            state.activeProfileID = state.profiles.first?.id
        }

        return state
    }

    private static func defaultState() -> ProfileState {
        sanitized(state: nil)
    }

    private static func resolveSaveURL(fileManager: FileManager, directory: URL?, filename: String) -> URL {
        if let directory {
            return directory.appendingPathComponent(filename)
        }

        if let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
            return documentsURL.appendingPathComponent(filename)
        }

        return fileManager.temporaryDirectory.appendingPathComponent(filename)
    }
}

private struct ProfileState: Codable, Equatable {
    var profiles: [ChildProfile]
    var activeProfileID: UUID?

    var activeProfile: ChildProfile? {
        guard let activeProfileID else { return nil }
        return profiles.first(where: { $0.id == activeProfileID })
    }
}

extension ProfileStore {
    static var preview: ProfileStore {
        let profiles = [
            ChildProfile(name: "Aria", birthDate: Date(timeIntervalSince1970: 1_600_000_000)),
            ChildProfile(name: "Luca", birthDate: Date(timeIntervalSince1970: 1_650_000_000))
        ]

        return ProfileStore(
            initialProfiles: profiles,
            activeProfileID: profiles.first?.id,
            directory: FileManager.default.temporaryDirectory,
            filename: "previewChildProfiles.json"
        )
    }
}
