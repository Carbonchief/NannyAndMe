import Foundation

@available(iOS 17.0, *)
struct RunningActionDTO: Codable, Identifiable, Hashable {
    var id: UUID
    var category: String
    var title: String
    var subtitle: String?
    var subtypeWord: String?
    var startDate: Date
    var iconSystemName: String
}

@available(iOS 17.0, *)
enum RunningActionStore {
    static let appGroupID = "group.com.prioritybit.babynanny"
    static let fileName = "running-actions.json"

    private static var url: URL {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
        else { fatalError("Missing App Group container. Update appGroupID and enable App Groups.") }
        return container.appendingPathComponent(fileName)
    }

    static func load() -> [RunningActionDTO] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([RunningActionDTO].self, from: data)) ?? []
    }

    static func save(_ items: [RunningActionDTO]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        if let data = try? encoder.encode(items) {
            try? data.write(to: url, options: [.atomic])
        }
    }
}
