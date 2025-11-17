import Foundation

enum ProfileSharePermission: String, CaseIterable, Identifiable, Codable, Sendable {
    case view
    case edit

    var id: String { rawValue }
}

enum ProfileShareStatus: String, Codable, Sendable {
    case pending
    case accepted
    case revoked
    case rejected
}
