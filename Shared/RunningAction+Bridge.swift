import Foundation

@available(iOS 17.0, *)
extension RunningActionDTO {
    init(_ source: DurationActivityAttributes.ContentState.RunningAction) {
        self.id = source.id
        self.category = source.category.rawValue
        self.title = source.title
        self.subtitle = source.subtitle
        self.subtypeWord = source.subtypeWord
        self.startDate = source.startDate
        self.iconSystemName = source.iconSystemName
    }
}

@available(iOS 17.0, *)
extension DurationActivityAttributes.ContentState.RunningAction {
    init(_ dto: RunningActionDTO) {
        self.id = dto.id
        self.category = DurationActivityCategory(rawValue: dto.category) ?? .feeding
        self.title = dto.title
        self.subtitle = dto.subtitle
        self.subtypeWord = dto.subtypeWord
        self.startDate = dto.startDate
        self.iconSystemName = dto.iconSystemName
    }
}
