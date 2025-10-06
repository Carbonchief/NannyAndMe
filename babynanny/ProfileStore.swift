import Foundation
import SwiftUI

struct ChildProfile: Codable {
    var name: String
    var birthDate: Date
    var imageData: Data?
}

@MainActor
final class ProfileStore: ObservableObject {
    @Published var profile: ChildProfile {
        didSet {
            persistProfile()
        }
    }

    private let saveURL: URL
    init(fileManager: FileManager = .default, directory: URL? = nil, filename: String = "childProfile.json") {
        if let directory {
            self.saveURL = directory.appendingPathComponent(filename)
        } else if let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
            self.saveURL = documentsURL.appendingPathComponent(filename)
        } else {
            self.saveURL = fileManager.temporaryDirectory.appendingPathComponent(filename)
        }

        if let data = try? Data(contentsOf: saveURL) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            if let decoded = try? decoder.decode(ChildProfile.self, from: data) {
                self.profile = decoded
            } else {
                self.profile = ChildProfile(name: "", birthDate: Date(), imageData: nil)
            }
        } else {
            self.profile = ChildProfile(name: "", birthDate: Date(), imageData: nil)
        }

        persistProfile()
    }

    private func persistProfile() {
        let profileSnapshot = profile
        let url = saveURL

        Task.detached(priority: .background) {
            do {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                let data = try encoder.encode(profileSnapshot)
                try data.write(to: url, options: .atomic)
            } catch {
                #if DEBUG
                print("Failed to save child profile: \(error.localizedDescription)")
                #endif
            }
        }
    }
}

extension ProfileStore {
    static var preview: ProfileStore {
        ProfileStore(directory: FileManager.default.temporaryDirectory, filename: "previewChildProfile.json")
    }
}
