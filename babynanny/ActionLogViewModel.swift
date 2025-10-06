import SwiftUI

struct BabyAction: Identifiable {
    enum DiaperType: String, CaseIterable, Identifiable {
        case pee
        case poo
        case both

        var id: String { rawValue }

        var title: String {
            switch self {
            case .pee:
                return "Pee"
            case .poo:
                return "Poo"
            case .both:
                return "Pee & Poo"
            }
        }

        var icon: String {
            switch self {
            case .pee:
                return "drop.fill"
            case .poo:
                return "leaf.fill"
            case .both:
                return "drop.circle.fill"
            }
        }
    }

    enum FeedingType: String, CaseIterable, Identifiable {
        case bottle
        case leftBreast
        case rightBreast
        case meal

        var id: String { rawValue }

        var title: String {
            switch self {
            case .bottle:
                return "Bottle"
            case .leftBreast:
                return "Left Breast"
            case .rightBreast:
                return "Right Breast"
            case .meal:
                return "Meal"
            }
        }

        var icon: String {
            switch self {
            case .bottle:
                return "takeoutbag.and.cup.and.straw.fill"
            case .leftBreast:
                return "heart.fill"
            case .rightBreast:
                return "heart.circle.fill"
            case .meal:
                return "fork.knife.circle.fill"
            }
        }

        var requiresVolume: Bool {
            self == .bottle
        }
    }

    let id = UUID()
    let category: BabyActionCategory
    let startDate: Date
    var endDate: Date?
    let diaperType: DiaperType?
    let feedingType: FeedingType?
    let bottleVolume: Int?

    init(category: BabyActionCategory,
         startDate: Date = Date(),
         endDate: Date? = nil,
         diaperType: DiaperType? = nil,
         feedingType: FeedingType? = nil,
         bottleVolume: Int? = nil) {
        self.category = category
        self.startDate = startDate
        self.endDate = endDate
        self.diaperType = diaperType
        self.feedingType = feedingType
        self.bottleVolume = bottleVolume
    }

    var title: String {
        category.title
    }

    var icon: String {
        if let diaperType {
            return diaperType.icon
        }
        if let feedingType {
            return feedingType.icon
        }
        return category.icon
    }

    var detailDescription: String {
        switch category {
        case .sleep:
            return "Nap time"
        case .diaper:
            if let diaperType {
                return "Diaper: \(diaperType.title)"
            }
            return "Diaper change"
        case .feeding:
            if let feedingType {
                if feedingType == .bottle, let bottleVolume {
                    return "Feeding: Bottle (\(bottleVolume) ml)"
                }
                return "Feeding: \(feedingType.title)"
            }
            return "Feeding"
        }
    }

    func durationDescription(asOf referenceDate: Date = Date()) -> String {
        let endReference = endDate ?? referenceDate
        let duration = endReference.timeIntervalSince(startDate)
        return BabyActionFormatter.shared.format(duration: duration)
    }

    func startTimeDescription() -> String {
        BabyActionFormatter.shared.format(time: startDate)
    }

    func startDateTimeDescription() -> String {
        BabyActionFormatter.shared.format(dateTime: startDate)
    }

    func endDateTimeDescription() -> String? {
        guard let endDate else { return nil }
        return BabyActionFormatter.shared.format(dateTime: endDate)
    }
}

enum BabyActionCategory: String, CaseIterable, Identifiable {
    case sleep
    case diaper
    case feeding

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sleep:
            return "Sleep"
        case .diaper:
            return "Diaper"
        case .feeding:
            return "Feeding"
        }
    }

    var icon: String {
        switch self {
        case .sleep:
            return "moon.zzz.fill"
        case .diaper:
            return "sparkles"
        case .feeding:
            return "fork.knife"
        }
    }

    var accentColor: Color {
        switch self {
        case .sleep:
            return Color.indigo
        case .diaper:
            return Color.green
        case .feeding:
            return Color.orange
        }
    }
}

final class ActionLogViewModel: ObservableObject {
    @Published private(set) var activeActions: [BabyActionCategory: BabyAction] = [:]
    @Published private(set) var history: [BabyAction] = []

    func startAction(for category: BabyActionCategory,
                     diaperType: BabyAction.DiaperType? = nil,
                     feedingType: BabyAction.FeedingType? = nil,
                     bottleVolume: Int? = nil) {
        if var existing = activeActions.removeValue(forKey: category) {
            existing.endDate = Date()
            history.insert(existing, at: 0)
        }

        let action = BabyAction(category: category,
                                startDate: Date(),
                                diaperType: diaperType,
                                feedingType: feedingType,
                                bottleVolume: bottleVolume)
        activeActions[category] = action
    }

    func stopAction(for category: BabyActionCategory) {
        guard var action = activeActions.removeValue(forKey: category) else { return }
        action.endDate = Date()
        history.insert(action, at: 0)
    }

    func activeAction(for category: BabyActionCategory) -> BabyAction? {
        activeActions[category]
    }

    func lastCompletedAction(for category: BabyActionCategory) -> BabyAction? {
        history.first(where: { $0.category == category })
    }

    var mostRecentAction: BabyAction? {
        if let running = activeActions.values.sorted(by: { $0.startDate > $1.startDate }).first {
            return running
        }
        return history.first
    }
}

private final class BabyActionFormatter {
    static let shared = BabyActionFormatter()

    private let timeFormatter: DateFormatter
    private let dateTimeFormatter: DateFormatter
    private let durationFormatter: DateComponentsFormatter

    private init() {
        timeFormatter = DateFormatter()
        timeFormatter.timeStyle = .short
        timeFormatter.dateStyle = .none

        dateTimeFormatter = DateFormatter()
        dateTimeFormatter.timeStyle = .short
        dateTimeFormatter.dateStyle = .medium

        durationFormatter = DateComponentsFormatter()
        durationFormatter.allowedUnits = [.hour, .minute, .second]
        durationFormatter.unitsStyle = .abbreviated
        durationFormatter.zeroFormattingBehavior = [.dropLeading, .dropTrailing]
    }

    func format(time: Date) -> String {
        timeFormatter.string(from: time)
    }

    func format(dateTime: Date) -> String {
        dateTimeFormatter.string(from: dateTime)
    }

    func format(duration: TimeInterval) -> String {
        durationFormatter.string(from: duration) ?? "Just now"
    }
}
