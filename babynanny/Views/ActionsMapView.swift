import MapKit
import SwiftData
import SwiftUI

/// Displays logged baby actions on a map with filtering by action type and date range.
struct ActionsMapView: View {
    @EnvironmentObject private var profileStore: ProfileStore
    @Query(sort: [SortDescriptor(\BabyAction.startDateRawValue, order: .reverse)])
    private var actions: [BabyAction]
    @State private var selectedCategory: BabyActionCategory?
    @State private var startDate: Date = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    @State private var endDate: Date = Date()
    @State private var isShowingDateFilters = false
    @State private var selectedAnnotation: ActionAnnotation?
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.3349, longitude: -122.0090),
        span: MKCoordinateSpan(latitudeDelta: 0.25, longitudeDelta: 0.25)
    )

    private var calendar: Calendar { Calendar.current }

    private var activeProfileID: UUID? {
        profileStore.activeProfileID
    }

    private var dateRangeSummary: String {
        let formatter = ActionsMapView.dateIntervalFormatter
        let summary = formatter.string(from: startDate, to: endDate)
        if summary.isEmpty == false {
            return summary
        }

        let fallbackFormatter = DateFormatter()
        fallbackFormatter.dateStyle = .medium
        fallbackFormatter.timeStyle = .none
        let start = fallbackFormatter.string(from: startDate)
        let end = fallbackFormatter.string(from: endDate)
        return "\(start) – \(end)"
    }

    private var filteredAnnotations: [ActionAnnotation] {
        guard let activeProfileID else { return [] }
        let windowStart = calendar.startOfDay(for: startDate)
        let windowEnd = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: endDate) ?? endDate

        return actions
            .compactMap { action -> ActionAnnotation? in
                guard action.profile?.resolvedProfileID == activeProfileID else { return nil }
                guard let latitude = action.latitude, let longitude = action.longitude else { return nil }
                guard selectedCategory == nil || action.category == selectedCategory else { return nil }
                let timestamp = action.startDate
                guard timestamp >= windowStart && timestamp <= windowEnd else { return nil }
                let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
                guard CLLocationCoordinate2DIsValid(coordinate) else { return nil }
                return ActionAnnotation(action: action, coordinate: coordinate)
            }
    }

    var body: some View {
        VStack(spacing: 0) {
            FilterBar(selectedCategory: $selectedCategory,
                      dateSummary: dateRangeSummary,
                      onShowDateFilters: { isShowingDateFilters = true })
                .padding(.horizontal, 16)
                .padding(.top, 12)

            Map(coordinateRegion: $region, annotationItems: filteredAnnotations) { annotation in
                MapAnnotation(coordinate: annotation.coordinate) {
                    AnnotationView(annotation: annotation,
                                   isSelected: selectedAnnotation?.id == annotation.id)
                        .phOnTapCapture(
                            event: "map_select_annotation",
                            properties: [
                                "action_id": annotation.id.uuidString,
                                "category": annotation.category.rawValue,
                                "has_placename": annotation.placename != nil
                            ]
                        ) {
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                                if selectedAnnotation?.id == annotation.id {
                                    selectedAnnotation = nil
                                } else {
                                    selectedAnnotation = annotation
                                }
                            }
                        }
                        .postHogLabel(annotation.postHogLabel)
                }
            }
            .mapStyle(.standard)
            .postHogLabel("map.canvas")
            .overlay(alignment: .top) {
                if filteredAnnotations.isEmpty {
                    EmptyStateView()
                        .padding(.top, 48)
                }
            }
            .ignoresSafeArea(edges: .bottom)
        }
        .navigationTitle(L10n.Map.title)
        .background(Color(.systemBackground))
        .onChange(of: filteredAnnotations, initial: true) { _, newValue in
            updateRegion(for: newValue)
            if let selection = selectedAnnotation, newValue.contains(selection) == false {
                withAnimation(.easeInOut(duration: 0.2)) {
                    selectedAnnotation = nil
                }
            }
        }
        .onChange(of: startDate) { _, newValue in
            if newValue > endDate {
                endDate = calendar.date(byAdding: .day, value: 1, to: newValue) ?? newValue
            }
        }
        .onChange(of: endDate) { _, newValue in
            if newValue < startDate {
                startDate = calendar.date(byAdding: .day, value: -1, to: newValue) ?? newValue
            }
        }
        .sheet(isPresented: $isShowingDateFilters) {
            DateFilterSheet(startDate: $startDate, endDate: $endDate, isPresented: $isShowingDateFilters)
        }
        .safeAreaInset(edge: .bottom) {
            if let selection = selectedAnnotation {
                AnnotationDetailCard(annotation: selection) {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        selectedAnnotation = nil
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 16)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: selectedAnnotation)
    }

    private func updateRegion(for annotations: [ActionAnnotation]) {
        guard annotations.isEmpty == false else { return }
        let coordinates = annotations.map(\.coordinate)
        let minLatitude = coordinates.map(\.latitude).min() ?? region.center.latitude
        let maxLatitude = coordinates.map(\.latitude).max() ?? region.center.latitude
        let minLongitude = coordinates.map(\.longitude).min() ?? region.center.longitude
        let maxLongitude = coordinates.map(\.longitude).max() ?? region.center.longitude

        let span = MKCoordinateSpan(
            latitudeDelta: max(0.01, (maxLatitude - minLatitude) * 1.4),
            longitudeDelta: max(0.01, (maxLongitude - minLongitude) * 1.4)
        )
        let center = CLLocationCoordinate2D(
            latitude: (minLatitude + maxLatitude) / 2,
            longitude: (minLongitude + maxLongitude) / 2
        )
        if CLLocationCoordinate2DIsValid(center) {
            region = MKCoordinateRegion(center: center, span: span)
        }
    }
}

private extension ActionsMapView {
    private static let dateIntervalFormatter: DateIntervalFormatter = {
        let formatter = DateIntervalFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    private static let annotationTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    struct ActionAnnotation: Identifiable, Equatable {
        let id: UUID
        let coordinate: CLLocationCoordinate2D
        let category: BabyActionCategory
        let placename: String?
        let timestamp: Date
        let subtypeTitle: String?

        init(action: BabyAction, coordinate: CLLocationCoordinate2D) {
            id = action.id
            self.coordinate = coordinate
            category = action.category
            placename = action.placename
            timestamp = action.startDate
            subtypeTitle = action.subtypeWord
        }

        static func == (lhs: ActionAnnotation, rhs: ActionAnnotation) -> Bool {
            lhs.id == rhs.id &&
                lhs.category == rhs.category &&
                lhs.placename == rhs.placename &&
                lhs.subtypeTitle == rhs.subtypeTitle &&
                lhs.timestamp == rhs.timestamp &&
                lhs.coordinate.latitude == rhs.coordinate.latitude &&
                lhs.coordinate.longitude == rhs.coordinate.longitude
        }

        var iconName: String {
            category.icon
        }

        var accentColor: Color {
            category.accentColor
        }

        var categoryTitle: String {
            category.title
        }

        var timestampSummary: String {
            ActionsMapView.annotationTimestampFormatter.string(from: timestamp)
        }

        var title: String {
            placename ?? category.title
        }

        var accessibilityLabel: String {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            let dateString = formatter.string(from: timestamp)
            return L10n.Map.annotationAccessibility(category.title, title, dateString)
        }

        var postHogLabel: String {
            "map.annotation.pin.\(category.rawValue)"
        }
    }

    struct AnnotationView: View {
        let annotation: ActionAnnotation
        let isSelected: Bool

        var body: some View {
            VStack(spacing: 6) {
                Image(systemName: annotation.iconName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .padding(10)
                    .background(
                        Circle()
                            .fill(annotation.accentColor.gradient)
                    )
                    .overlay {
                        Circle()
                            .strokeBorder(Color.white.opacity(isSelected ? 0.85 : 0), lineWidth: isSelected ? 3 : 0)
                    }
                    .shadow(color: annotation.accentColor.opacity(isSelected ? 0.35 : 0.2), radius: isSelected ? 8 : 4, y: 3)
                    .scaleEffect(isSelected ? 1.08 : 1.0)
                Text(annotation.title)
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.thinMaterial, in: Capsule())
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(annotation.accessibilityLabel)
        }
    }

    struct AnnotationDetailCard: View {
        let annotation: ActionAnnotation
        let onClose: () -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(annotation.accentColor.gradient)
                            .frame(width: 44, height: 44)

                        Image(systemName: annotation.iconName)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(Color.white)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(annotation.title)
                            .font(.headline)
                            .lineLimit(2)

                        Text(L10n.Map.annotationLoggedAt(annotation.timestampSummary))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 12)

                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            onClose()
                        }
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(Color.secondary)
                    }
                    .postHogLabel("map.annotationDetail.close")
                    .phCaptureTap(
                        event: "map_close_annotation_detail",
                        properties: [
                            "action_id": annotation.id.uuidString,
                            "category": annotation.category.rawValue
                        ]
                    )
                    .accessibilityLabel(L10n.Common.close)
                }

                VStack(alignment: .leading, spacing: 8) {
                    InfoRow(label: L10n.Map.annotationTypeLabel, value: annotation.categoryTitle)

                    if let subtype = annotation.subtypeTitle, subtype.isEmpty == false {
                        InfoRow(label: L10n.Map.annotationSubtypeLabel, value: subtype)
                    }
                }
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06))
            )
            .shadow(color: Color.black.opacity(0.1), radius: 14, y: 6)
            .accessibilityElement(children: .combine)
        }

        private struct InfoRow: View {
            let label: String
            let value: String

            var body: some View {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label.uppercased())
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text(value)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                }
            }
        }
    }

    struct FilterBar: View {
        @Binding var selectedCategory: BabyActionCategory?
        let dateSummary: String
        let onShowDateFilters: () -> Void

        var body: some View {
            HStack(spacing: 12) {
                Menu {
                    Picker(L10n.Map.actionTypeFilter, selection: $selectedCategory) {
                        Text(L10n.Map.allActions)
                            .tag(BabyActionCategory?.none)
                        ForEach(BabyActionCategory.allCases) { category in
                            Text(category.title)
                                .tag(BabyActionCategory?.some(category))
                        }
                    }
                    .pickerStyle(.inline)
                } label: {
                    FilterChip(iconName: "line.3.horizontal.decrease.circle",
                               title: L10n.Map.actionTypeFilter,
                               detail: selectedCategoryTitle,
                               accessory: .chevronDown)
                }
                .buttonStyle(.plain)
                .postHogLabel("map.filter.actionType")

                Button(action: onShowDateFilters) {
                    FilterChip(iconName: "calendar.badge.clock",
                               title: L10n.Map.dateRangeFilterButton,
                               detail: dateSummary,
                               accessory: .chevronForward)
                }
                .buttonStyle(.plain)
                .postHogLabel("map.filter.dateButton")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )
            .padding(.bottom, 8)
        }

        private var selectedCategoryTitle: String {
            selectedCategory?.title ?? L10n.Map.allActions
        }

        private struct FilterChip: View {
            enum Accessory {
                case chevronDown
                case chevronForward
            }

            let iconName: String
            let title: String
            let detail: String
            let accessory: Accessory

            var body: some View {
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: iconName)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(detail)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Spacer(minLength: 4)

                    Image(systemName: accessorySymbol)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.secondary)
                        .accessibilityHidden(true)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(.tertiarySystemBackground))
                )
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            private var accessorySymbol: String {
                switch accessory {
                case .chevronDown:
                    return "chevron.down"
                case .chevronForward:
                    return "chevron.right"
                }
            }
        }
    }

    struct DateFilterSheet: View {
        @Binding var startDate: Date
        @Binding var endDate: Date
        @Binding var isPresented: Bool

        private var calendar: Calendar { Calendar.current }

        var body: some View {
            NavigationStack {
                Form {
                    Section(L10n.Map.dateRangeFilter) {
                        DatePicker(L10n.Map.startDate,
                                   selection: $startDate,
                                   displayedComponents: .date)
                            .datePickerStyle(.graphical)
                            .postHogLabel("map.filterSheet.startDate")

                        DatePicker(L10n.Map.endDate,
                                   selection: $endDate,
                                   in: startDate...,
                                   displayedComponents: .date)
                            .datePickerStyle(.graphical)
                            .postHogLabel("map.filterSheet.endDate")
                    }
                }
                .navigationTitle(L10n.Map.dateRangeFilterTitle)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(L10n.Common.cancel) {
                            isPresented = false
                        }
                        .postHogLabel("map.filterSheet.cancel")
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(L10n.Common.done) {
                            if endDate < startDate {
                                endDate = calendar.date(byAdding: .day, value: 1, to: startDate) ?? startDate
                            }
                            isPresented = false
                        }
                        .postHogLabel("map.filterSheet.done")
                    }
                }
            }
        }
    }

    struct EmptyStateView: View {
        var body: some View {
            Text(L10n.Map.emptyState)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(12)
                .background(.ultraThinMaterial, in: Capsule())
        }
    }
}

@MainActor
private enum ActionsMapViewPreviewData {
    static let profile = Profile(name: "Luna")

    static let container: ModelContainer = {
        let container = AppDataStack.makeModelContainer(inMemory: true)
        let context = ModelContext(container)
        seedData(in: context)
        return container
    }()

    static let profileStore: ProfileStore = {
        let previewProfile = ChildProfile(id: profile.profileID,
                                          name: "Luna",
                                          birthDate: Date().addingTimeInterval(-120 * 24 * 60 * 60))
        let store = ProfileStore(initialProfiles: [previewProfile],
                                 activeProfileID: profile.profileID,
                                 directory: FileManager.default.temporaryDirectory,
                                 filename: "mapPreviewProfiles.json")
        store.updateActiveProfile { child in
            child.name = "Luna"
        }
        return store
    }()

    private static func seedData(in context: ModelContext) {
        let action = BabyAction(category: .sleep,
                                startDate: Date().addingTimeInterval(-3600),
                                endDate: Date().addingTimeInterval(-1800),
                                latitude: 37.3349,
                                longitude: -122.0090,
                                placename: "Apple Park",
                                profile: profile)
        context.insert(profile)
        context.insert(action)
        try? context.save()
    }
}

#Preview {
    NavigationStack {
        ActionsMapView()
            .environmentObject(ActionsMapViewPreviewData.profileStore)
    }
    .modelContainer(ActionsMapViewPreviewData.container)
}
