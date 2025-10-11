import Foundation

@available(iOS 17.0, *)
extension RunningActionDTO {
    init(_ source: DurationActivityAttributes.ContentState.RunningAction) {
        id = source.id
        category = source.category.rawValue
        title = source.title
        subtitle = source.subtitle
        subtypeWord = source.subtypeWord
        startDate = source.startDate
        iconSystemName = source.iconSystemName
    }
}

@available(iOS 17.0, *)
extension DurationActivityAttributes.ContentState.RunningAction {
    init(_ dto: RunningActionDTO) {
        id = dto.id
        category = DurationActivityCategory(rawValue: dto.category) ?? .feeding
        title = dto.title
        subtitle = dto.subtitle
        subtypeWord = dto.subtypeWord
        startDate = dto.startDate
        iconSystemName = dto.iconSystemName
    }
}
