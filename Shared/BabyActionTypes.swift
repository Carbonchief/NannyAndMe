import Foundation

enum BabyActionCategory: String, CaseIterable, Codable, Sendable {
    case sleep
    case diaper
    case feeding
}

enum BabyActionDiaperType: String, CaseIterable, Codable, Sendable {
    case pee
    case poo
    case both
}

enum BabyActionFeedingType: String, CaseIterable, Codable, Sendable {
    case bottle
    case leftBreast
    case rightBreast
    case meal
}

enum BabyActionBottleType: String, CaseIterable, Codable, Sendable {
    case formula
    case breastMilk
    case cowMilk
}
