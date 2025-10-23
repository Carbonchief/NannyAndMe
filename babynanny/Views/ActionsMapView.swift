import MapKit
import SwiftData
import SwiftUI

/// Displays logged baby actions on a map with filtering by action type and date range.
struct ActionsMapView: View {
    @EnvironmentObject private var profileStore: ProfileStore
    @Query(sort: [SortDescriptor(\BabyAction.startDateRawValue, order: .reverse)])
    private var actions: [BabyAction]
    @State private var selectedCategory: BabyActionCategory?
    @State private var startDate: Date = Calendar.current.startOfDay(for: Date())
    @State private var endDate: Date = Calendar.current.startOfDay(for: Date())
    @State private var isDateFilterEnabled = true
    @State private var isShowingDateFilters = false
    @State private var selection: AnnotationSelection?
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.3349, longitude: -122.0090),
        span: MKCoordinateSpan(latitudeDelta: 0.25, longitudeDelta: 0.25)
    )

    private var calendar: Calendar { Calendar.current }

    private var activeProfileID: UUID? {
        profileStore.activeProfileID
    }

    private var selectedAnnotationID: UUID? {
        if case let .single(annotation) = selection {
            return annotation.id
        }
        return nil
    }

    private var selectedClusterID: String? {
        if case let .cluster(cluster) = selection {
            return cluster.id
        }
        return nil
    }

    private var dateRangeSummary: String {
        guard isDateFilterEnabled else {
            return L10n.Map.allDates
        }

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
        if start == end {
            return start
        }
        return "\(start) – \(end)"
    }

    private var filteredActionAnnotations: [ActionAnnotation] {
        guard let activeProfileID else { return [] }
        let windowStart = calendar.startOfDay(for: startDate)
        let windowEnd = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: endDate) ?? endDate

        return actions
            .compactMap { action -> ActionAnnotation? in
                guard action.profile?.resolvedProfileID == activeProfileID else { return nil }
                guard let latitude = action.latitude, let longitude = action.longitude else { return nil }
                guard selectedCategory == nil || action.category == selectedCategory else { return nil }
                if isDateFilterEnabled {
                    let timestamp = action.startDate
                    guard timestamp >= windowStart && timestamp <= windowEnd else { return nil }
                }
                let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
                guard CLLocationCoordinate2DIsValid(coordinate) else { return nil }
                return ActionAnnotation(action: action, coordinate: coordinate)
            }
    }

    private var clusteredAnnotations: [ClusteredActionAnnotation] {
        clusterAnnotations(from: filteredActionAnnotations)
    }

    var body: some View {
        VStack(spacing: 0) {
            FilterBar(selectedCategory: $selectedCategory,
                      dateSummary: dateRangeSummary,
                      isDateFilterEnabled: isDateFilterEnabled,
                      onShowDateFilters: { isShowingDateFilters = true })
                .padding(.horizontal, 16)
                .padding(.top, 12)

            Map(coordinateRegion: $region, annotationItems: clusteredAnnotations) { cluster in
                MapAnnotation(coordinate: cluster.coordinate) {
                    annotationContent(for: cluster)
                }
            }
            .mapStyle(.standard)
            .postHogLabel("map.canvas")
            .overlay(alignment: .top) {
                if filteredActionAnnotations.isEmpty {
                    EmptyStateView()
                        .padding(.top, 48)
                }
            }
            .ignoresSafeArea(edges: .bottom)
        }
        .navigationTitle(L10n.Map.title)
        .background(Color(.systemBackground))
        .onChange(of: filteredActionAnnotations, initial: true) { _, newValue in
            updateRegion(for: newValue)
            let updatedClusters = clusterAnnotations(from: newValue)
            syncSelection(with: updatedClusters, annotations: newValue)
        }
        .onChange(of: startDate) { _, newValue in
            guard isDateFilterEnabled else { return }
            if newValue > endDate {
                endDate = calendar.date(byAdding: .day, value: 1, to: newValue) ?? newValue
            }
        }
        .onChange(of: endDate) { _, newValue in
            guard isDateFilterEnabled else { return }
            if newValue < startDate {
                startDate = calendar.date(byAdding: .day, value: -1, to: newValue) ?? newValue
            }
        }
        .onChange(of: isDateFilterEnabled) { _, isEnabled in
            if isEnabled == false {
                selection = nil
            }
        }
        .sheet(isPresented: $isShowingDateFilters) {
            DateFilterSheet(startDate: $startDate,
                            endDate: $endDate,
                            isFilterEnabled: $isDateFilterEnabled,
                            isPresented: $isShowingDateFilters)
        }
        .safeAreaInset(edge: .bottom) {
            if let currentSelection = selection {
                switch currentSelection {
                case let .single(annotation):
                    AnnotationDetailCard(annotation: annotation) {
                        selection = nil
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 16)
                case let .cluster(cluster):
                    ClusterDetailCard(cluster: cluster,
                                      onSelectAction: { action in
                                          selection = .single(action)
                                      },
                                      onClose: {
                                          selection = nil
                                      })
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 16)
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: selection)
    }

    @ViewBuilder
    private func annotationContent(for cluster: ClusteredActionAnnotation) -> some View {
        if let annotation = cluster.singleAnnotation {
            singleAnnotationContent(for: annotation)
        } else {
            clusteredAnnotationContent(for: cluster)
        }
    }

    @ViewBuilder
    private func singleAnnotationContent(for annotation: ActionAnnotation) -> some View {
        AnnotationView(
            annotation: annotation,
            isSelected: selectedAnnotationID == annotation.id
        )
            .phOnTapCapture(
                event: "map_select_annotation",
                properties: [
                    "action_id": annotation.id.uuidString,
                    "category": annotation.category.rawValue,
                    "has_placename": annotation.placename != nil
                ]
            ) {
                handleSingleSelection(annotation)
            }
            .postHogLabel(annotation.postHogLabel)
    }

    @ViewBuilder
    private func clusteredAnnotationContent(for cluster: ClusteredActionAnnotation) -> some View {
        ClusterAnnotationView(
            cluster: cluster,
            isSelected: selectedClusterID == cluster.id
        )
            .phOnTapCapture(
                event: "map_select_cluster",
                properties: [
                    "action_ids": cluster.actionIDs.map(\.uuidString),
                    "count": cluster.count,
                    "categories": cluster.categoryIdentifiers
                ]
            ) {
                handleClusterSelection(cluster)
            }
            .postHogLabel(cluster.postHogLabel)
    }

    private func handleSingleSelection(_ annotation: ActionAnnotation) {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            if selectedAnnotationID == annotation.id {
                selection = nil
            } else {
                selection = .single(annotation)
            }
        }
    }

    private func handleClusterSelection(_ cluster: ClusteredActionAnnotation) {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            if selectedClusterID == cluster.id {
                selection = nil
            } else if cluster.count == 1, let annotation = cluster.singleAnnotation {
                selection = .single(annotation)
            } else {
                selection = .cluster(cluster)
            }
        }
    }

    private func syncSelection(with clusters: [ClusteredActionAnnotation], annotations: [ActionAnnotation]) {
        guard let currentSelection = selection else { return }
        switch currentSelection {
        case let .single(annotation):
            if annotations.contains(annotation) == false {
                withAnimation(.easeInOut(duration: 0.2)) {
                    selection = nil
                }
            }
        case let .cluster(cluster):
            guard let updatedCluster = clusters.first(where: { $0.actionIDs == cluster.actionIDs }) else {
                withAnimation(.easeInOut(duration: 0.2)) {
                    selection = nil
                }
                return
            }

            if updatedCluster.count == 1, let single = updatedCluster.singleAnnotation {
                selection = .single(single)
            } else if updatedCluster != cluster {
                selection = .cluster(updatedCluster)
            }
        }
    }

    private func clusterAnnotations(from annotations: [ActionAnnotation]) -> [ClusteredActionAnnotation] {
        guard annotations.isEmpty == false else { return [] }

        var clusters: [ClusteredActionAnnotation] = []
        var visited = Set<UUID>()

        for annotation in annotations {
            guard visited.contains(annotation.id) == false else { continue }

            var group: [ActionAnnotation] = [annotation]
            visited.insert(annotation.id)

            var index = 0
            while index < group.count {
                let baseAnnotation = group[index]
                let basePoint = MKMapPoint(baseAnnotation.coordinate)

                for other in annotations where visited.contains(other.id) == false {
                    let otherPoint = MKMapPoint(other.coordinate)
                    if basePoint.distance(to: otherPoint) <= ActionsMapView.clusterDistanceThreshold {
                        group.append(other)
                        visited.insert(other.id)
                    }
                }

                index += 1
            }

            clusters.append(ClusteredActionAnnotation(actions: group))
        }

        return clusters
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

    private static let clusterDistanceThreshold: CLLocationDistance = 50

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
            if let subtype = subtypeTitle, subtype.isEmpty == false {
                return subtype
            }
            return category.title
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

    struct ClusteredActionAnnotation: Identifiable, Equatable {
        let id: String
        let coordinate: CLLocationCoordinate2D
        let actions: [ActionAnnotation]
        let actionIDs: [UUID]

        init(actions: [ActionAnnotation]) {
            let ordered = actions.sorted { $0.timestamp > $1.timestamp }
            self.actions = ordered
            actionIDs = ordered.map(\.id).sorted { $0.uuidString < $1.uuidString }

            let latitudeSum = ordered.reduce(0.0) { partial, annotation in
                partial + annotation.coordinate.latitude
            }
            let longitudeSum = ordered.reduce(0.0) { partial, annotation in
                partial + annotation.coordinate.longitude
            }
            let latitude = latitudeSum / Double(max(ordered.count, 1))
            let longitude = longitudeSum / Double(max(ordered.count, 1))
            coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            id = actionIDs.map(\.uuidString).joined(separator: "-")
        }

        var count: Int { actions.count }

        var singleAnnotation: ActionAnnotation? {
            count == 1 ? actions.first : nil
        }

        var primaryAnnotation: ActionAnnotation? {
            actions.first
        }

        var representativeTitle: String {
            if let placename = primaryAnnotation?.placename, placename.isEmpty == false {
                return placename
            }
            return L10n.Map.allActions
        }

        var accentColor: Color {
            primaryAnnotation?.accentColor ?? .accentColor
        }

        var categoryIdentifiers: [String] {
            actions.map { $0.category.rawValue }
        }

        var accessibilityLabel: String {
            L10n.Map.clusterAccessibility(count, representativeTitle)
        }

        var postHogLabel: String {
            "map.annotation.cluster"
        }

        func contains(actionID: UUID) -> Bool {
            actionIDs.contains(actionID)
        }

        static func == (lhs: ClusteredActionAnnotation, rhs: ClusteredActionAnnotation) -> Bool {
            lhs.id == rhs.id &&
                lhs.coordinate.latitude == rhs.coordinate.latitude &&
                lhs.coordinate.longitude == rhs.coordinate.longitude
        }
    }

    enum AnnotationSelection: Equatable {
        case single(ActionAnnotation)
        case cluster(ClusteredActionAnnotation)
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

    struct ClusterAnnotationView: View {
        let cluster: ClusteredActionAnnotation
        let isSelected: Bool

        var body: some View {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(cluster.accentColor.gradient)
                        .frame(width: 44, height: 44)
                        .overlay {
                            Circle()
                                .strokeBorder(
                                    Color.white.opacity(isSelected ? 0.9 : 0.85),
                                    lineWidth: isSelected ? 3 : 2
                                )
                        }

                    Text("\(cluster.count)")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.white)
                }
                .shadow(
                    color: cluster.accentColor.opacity(isSelected ? 0.35 : 0.2),
                    radius: isSelected ? 10 : 6,
                    y: 3
                )
                .scaleEffect(isSelected ? 1.08 : 1.0)

                let title = cluster.representativeTitle
                if title.isEmpty == false {
                    Text(title)
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.thinMaterial, in: Capsule())
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(cluster.accessibilityLabel)
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

    struct ClusterDetailCard: View {
        let cluster: ClusteredActionAnnotation
        let onSelectAction: (ActionAnnotation) -> Void
        let onClose: () -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    ClusterAnnotationView(cluster: cluster, isSelected: false)
                        .allowsHitTesting(false)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(cluster.representativeTitle)
                            .font(.headline)
                            .lineLimit(2)

                        Text(L10n.Map.clusterDetailTitle(cluster.count))
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
                    .postHogLabel("map.clusterDetail.close")
                    .phCaptureTap(
                        event: "map_close_cluster_detail",
                        properties: [
                            "count": cluster.count,
                            "action_ids": cluster.actionIDs.map(\.uuidString)
                        ]
                    )
                    .accessibilityLabel(L10n.Common.close)
                }

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(cluster.actions) { action in
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                onSelectAction(action)
                            }
                        }) {
                            ClusterActionRow(annotation: action)
                        }
                        .buttonStyle(.plain)
                        .postHogLabel("map.clusterDetail.action.\(action.category.rawValue)")
                        .phCaptureTap(
                            event: "map_select_cluster_action",
                            properties: [
                                "action_id": action.id.uuidString,
                                "category": action.category.rawValue
                            ]
                        )
                        .accessibilityLabel(action.accessibilityLabel)
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

        private struct ClusterActionRow: View {
            let annotation: ActionAnnotation

            var body: some View {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(annotation.accentColor.gradient)
                            .frame(width: 36, height: 36)

                        Image(systemName: annotation.iconName)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.white)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(annotation.title)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .lineLimit(2)

                        Text(annotation.timestampSummary)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 8)

                    Image(systemName: "chevron.forward")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(.systemBackground).opacity(0.85))
                )
            }
        }
    }

    struct FilterBar: View {
        @Binding var selectedCategory: BabyActionCategory?
        let dateSummary: String
        let isDateFilterEnabled: Bool
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
                               accessory: .chevronForward,
                               isActive: isDateFilterEnabled)
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
            var isActive: Bool = true

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
                            .foregroundStyle(isActive ? .primary : .secondary)
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
        @Binding var isFilterEnabled: Bool
        @Binding var isPresented: Bool

        private var calendar: Calendar { Calendar.current }

        var body: some View {
            NavigationStack {
                Form {
                    Section {
                        Toggle(L10n.Map.dateRangeFilterToggle,
                               isOn: $isFilterEnabled.animation())
                            .postHogLabel("map.filterSheet.toggle")
                    }

                    Section(L10n.Map.dateRangeFilter) {
                        DatePicker(L10n.Map.startDate,
                                   selection: $startDate,
                                   displayedComponents: .date)
                            .datePickerStyle(.graphical)
                            .postHogLabel("map.filterSheet.startDate")
                            .disabled(isFilterEnabled == false)

                        DatePicker(L10n.Map.endDate,
                                   selection: $endDate,
                                   in: startDate...,
                                   displayedComponents: .date)
                            .datePickerStyle(.graphical)
                            .postHogLabel("map.filterSheet.endDate")
                            .disabled(isFilterEnabled == false)
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
                            if isFilterEnabled && endDate < startDate {
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
