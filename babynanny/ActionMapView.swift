import CoreLocation
import MapKit
import SwiftUI

struct ActionMapView: View {
    @EnvironmentObject private var profileStore: ProfileStore
    @EnvironmentObject private var actionStore: ActionLogStore
    @State private var selectedCategory: BabyActionCategory?
    @State private var dateFilter: ActionMapDateFilter = .sevenDays
    @State private var selectedCluster: ActionCluster?
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var hasInitializedCamera = false

    private let clusterRadius: CLLocationDistance = 150
    private let tabResetID: UUID

    init(tabResetID: UUID) {
        self.tabResetID = tabResetID
    }

    var body: some View {
        let clusters = filteredClusters

        ZStack(alignment: .top) {
            mapContent(for: clusters)
                .ignoresSafeArea(edges: .bottom)

            filterBar
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .zIndex(1)

            if let activeCluster = selectedCluster,
               let latestCluster = clusters.first(where: { $0.id == activeCluster.id }) {
                clusterDetail(for: latestCluster)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(3)
            }

            if selectedCluster != nil {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedCluster = nil
                    }
                } label: {
                    Color.black.opacity(0.2)
                        .ignoresSafeArea()
                }
                .buttonStyle(.plain)
                .postHogLabel("actionMap_dismiss_overlay")
                .transition(.opacity)
                .zIndex(2)
            }
        }
        .navigationTitle(L10n.Map.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if hasInitializedCamera == false {
                initializeCameraIfNeeded(for: clusters)
            }
        }
        .onChange(of: clusters) { _, newClusters in
            synchronizeSelection(with: newClusters)
            if hasInitializedCamera == false {
                initializeCameraIfNeeded(for: newClusters)
            }
            if newClusters.isEmpty {
                hasInitializedCamera = false
                cameraPosition = .automatic
            }
        }
        .onChange(of: selectedCluster) { _, newValue in
            guard let cluster = newValue else { return }
            centerCamera(on: cluster)
        }
        .onChange(of: tabResetID) { _, _ in
            withAnimation(.easeInOut(duration: 0.25)) {
                selectedCluster = nil
                selectedCategory = nil
                dateFilter = .sevenDays
                cameraPosition = .automatic
            }
            hasInitializedCamera = false
            initializeCameraIfNeeded(for: clusters)
        }
    }
}

private extension ActionMapView {
    var filteredClusters: [ActionCluster] {
        let locations = filteredLocations
        guard locations.isEmpty == false else { return [] }
        return cluster(locations: locations)
    }

    var filteredLocations: [ActionLocation] {
        guard let profileID = profileStore.activeProfileID else { return [] }
        let state = actionStore.state(for: profileID)
        let calendar = Calendar.current
        let startDate = dateFilter.startDate(in: calendar)

        return state.history.compactMap { action in
            guard let latitude = action.latitude, let longitude = action.longitude else { return nil }
            let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            guard CLLocationCoordinate2DIsValid(coordinate) else { return nil }

            if let selectedCategory, action.category != selectedCategory {
                return nil
            }

            if let startDate {
                let actionDate = action.endDate ?? action.startDate
                if actionDate < startDate {
                    return nil
                }
            }

            return ActionLocation(
                id: action.id,
                snapshot: action,
                coordinate: coordinate,
                locationName: action.placename,
                timestamp: action.endDate ?? action.startDate
            )
        }
    }

    @ViewBuilder
    func mapContent(for clusters: [ActionCluster]) -> some View {
        if clusters.isEmpty {
            Color(.systemGroupedBackground)
                .overlay {
                    VStack(spacing: 12) {
                        Image(systemName: "map")
                            .font(.system(size: 40, weight: .semibold))
                            .foregroundStyle(.secondary)

                        Text(L10n.Map.emptyState)
                            .font(.headline)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 24)
                    }
                }
        } else {
            Map(position: $cameraPosition) {
                ForEach(clusters) { cluster in
                    Annotation("", coordinate: cluster.coordinate) {
                        Button {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                selectedCluster = cluster
                            }
                        } label: {
                            ActionMapAnnotationView(cluster: cluster)
                        }
                        .buttonStyle(.plain)
                        .postHogLabel("actionMap_select_clusterAnnotation")
                        .accessibilityLabel(cluster.accessibilityLabel)
                    }
                }
            }
            .mapControls {
                MapUserLocationButton()
            }
        }
    }

    var filterBar: some View {
        HStack(spacing: 12) {
            Picker(L10n.Map.actionTypeFilter, selection: $selectedCategory) {
                Text(L10n.Map.allActions)
                    .tag(BabyActionCategory?.none)
                ForEach(BabyActionCategory.allCases, id: \.self) { category in
                    Text(category.title)
                        .tag(BabyActionCategory?.some(category))
                }
            }
            .pickerStyle(.menu)
            .postHogLabel("actionMap_change_actionTypeFilter")

            Picker(L10n.Map.dateRangeFilter, selection: $dateFilter) {
                Text(L10n.Map.allDates)
                    .tag(ActionMapDateFilter.all)
                Text(L10n.Map.dateRangeToday)
                    .tag(ActionMapDateFilter.today)
                Text(L10n.Map.dateRangeSevenDays)
                    .tag(ActionMapDateFilter.sevenDays)
                Text(L10n.Map.dateRangeThirtyDays)
                    .tag(ActionMapDateFilter.thirtyDays)
            }
            .pickerStyle(.menu)
            .postHogLabel("actionMap_change_dateFilter")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
    }

    func clusterDetail(for cluster: ActionCluster) -> some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(alignment: .leading, spacing: 16) {
                Capsule()
                    .fill(Color.secondary.opacity(0.3))
                    .frame(width: 48, height: 4)
                    .frame(maxWidth: .infinity)

                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(cluster.headerTitle)
                            .font(.headline)
                        Text(clusterSecondaryDescription(for: cluster))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedCluster = nil
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .postHogLabel("actionMap_dismiss_clusterDetail")
                }

                VStack(spacing: 12) {
                    ForEach(cluster.locations.sorted(by: { $0.timestamp > $1.timestamp })) { location in
                        clusterRow(for: location)
                    }
                }
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(.systemBackground))
                    .shadow(color: Color.black.opacity(0.12), radius: 20, x: 0, y: 8)
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
    }

    func clusterRow(for location: ActionLocation) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(location.category.accentColor.gradient)
                    .frame(width: 36, height: 36)

                Image(systemName: location.symbolName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(location.title)
                    .font(.body.weight(.semibold))
                Text(location.category.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(L10n.Map.annotationLoggedAt(location.loggedAtDescription))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    func clusterSecondaryDescription(for cluster: ActionCluster) -> String {
        if cluster.locations.count == 1, let location = cluster.locations.first {
            return L10n.Map.annotationLoggedAt(location.loggedAtDescription)
        }
        return L10n.Map.clusterDetailTitle(cluster.locations.count)
    }

    func initializeCameraIfNeeded(for clusters: [ActionCluster]) {
        guard clusters.isEmpty == false else { return }
        guard let region = region(for: clusters) else { return }
        cameraPosition = .region(region)
        hasInitializedCamera = true
    }

    func centerCamera(on cluster: ActionCluster) {
        let span = MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        let region = MKCoordinateRegion(center: cluster.coordinate, span: span)
        cameraPosition = .region(region)
    }

    func synchronizeSelection(with clusters: [ActionCluster]) {
        guard let selectedCluster else { return }
        if let updated = clusters.first(where: { $0.id == selectedCluster.id }) {
            self.selectedCluster = updated
        } else {
            withAnimation(.easeInOut(duration: 0.2)) {
                self.selectedCluster = nil
            }
        }
    }

    func region(for clusters: [ActionCluster]) -> MKCoordinateRegion? {
        guard let first = clusters.first else { return nil }
        var minLat = first.coordinate.latitude
        var maxLat = first.coordinate.latitude
        var minLon = first.coordinate.longitude
        var maxLon = first.coordinate.longitude

        for cluster in clusters.dropFirst() {
            minLat = min(minLat, cluster.coordinate.latitude)
            maxLat = max(maxLat, cluster.coordinate.latitude)
            minLon = min(minLon, cluster.coordinate.longitude)
            maxLon = max(maxLon, cluster.coordinate.longitude)
        }

        let latitudeDelta = max((maxLat - minLat) * 1.4, 0.02)
        let longitudeDelta = max((maxLon - minLon) * 1.4, 0.02)
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )

        return MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: latitudeDelta, longitudeDelta: longitudeDelta)
        )
    }

    func cluster(locations: [ActionLocation]) -> [ActionCluster] {
        var clusters: [ActionCluster] = []

        for location in locations {
            if let index = clusters.firstIndex(where: { $0.contains(location.coordinate, radius: clusterRadius) }) {
                clusters[index].add(location)
            } else {
                clusters.append(ActionCluster(location: location))
            }
        }

        return clusters
    }
}

private struct ActionLocation: Identifiable, Hashable {
    let id: UUID
    let snapshot: BabyActionSnapshot
    let coordinate: CLLocationCoordinate2D
    let locationName: String?
    let timestamp: Date

    var category: BabyActionCategory { snapshot.category }

    var title: String {
        snapshot.subtypeWord ?? snapshot.category.title
    }

    var symbolName: String {
        snapshot.icon
    }

    @MainActor
    var loggedAtDescription: String {
        snapshot.loggedTimestampDescription()
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: ActionLocation, rhs: ActionLocation) -> Bool {
        lhs.id == rhs.id
    }
}

private struct ActionCluster: Identifiable, Equatable {
    var locations: [ActionLocation]
    var coordinate: CLLocationCoordinate2D

    init(location: ActionLocation) {
        self.locations = [location]
        self.coordinate = location.coordinate
    }

    var id: String {
        locations.map(\.id.uuidString).sorted().joined(separator: "-")
    }

    static func == (lhs: ActionCluster, rhs: ActionCluster) -> Bool {
        lhs.id == rhs.id
    }

    @MainActor
    var accessibilityLabel: String {
        let locationName = headerTitle
        let dateDescription: String
        if let mostRecent = locations.sorted(by: { $0.timestamp > $1.timestamp }).first {
            dateDescription = mostRecent.loggedAtDescription
            return L10n.Map.annotationAccessibility(mostRecent.category.title, locationName, dateDescription)
        }
        return locationName
    }

    var headerTitle: String {
        if locations.count > 1 {
            return preferredLocationName ?? L10n.Map.unknownLocation
        }
        return locations.first?.title ?? L10n.Map.unknownLocation
    }

    var preferredLocationName: String? {
        locations.compactMap(\.locationName).first
    }

    var accentColor: Color {
        dominantCategory.accentColor
    }

    var dominantCategory: BabyActionCategory {
        var counts: [BabyActionCategory: Int] = [:]
        for location in locations {
            counts[location.category, default: 0] += 1
        }
        return counts.max(by: { $0.value < $1.value })?.key ?? locations.first?.category ?? .sleep
    }

    mutating func add(_ location: ActionLocation) {
        locations.append(location)
        coordinate = Self.averageCoordinate(for: locations)
    }

    func contains(_ coordinate: CLLocationCoordinate2D, radius: CLLocationDistance) -> Bool {
        let clusterLocation = CLLocation(latitude: self.coordinate.latitude, longitude: self.coordinate.longitude)
        let candidate = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return clusterLocation.distance(from: candidate) <= radius
    }

    static func averageCoordinate(for locations: [ActionLocation]) -> CLLocationCoordinate2D {
        let latitude = locations.map(\.coordinate.latitude).reduce(0, +) / Double(locations.count)
        let longitude = locations.map(\.coordinate.longitude).reduce(0, +) / Double(locations.count)
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

private struct ActionMapAnnotationView: View {
    let cluster: ActionCluster

    var body: some View {
        VStack(spacing: 4) {
            Text(cluster.headerTitle)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule(style: .circular)
                        .fill(Color(.systemBackground).opacity(0.85))
                )
                .foregroundStyle(.primary)
                .lineLimit(1)

            ZStack {
                Circle()
                    .fill(cluster.accentColor.gradient)
                    .frame(width: 32, height: 32)
                    .shadow(color: Color.black.opacity(0.25), radius: 6, x: 0, y: 4)

                if cluster.locations.count > 1 {
                    Text("\(cluster.locations.count)")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white)
                } else if let symbol = cluster.locations.first?.symbolName {
                    Image(systemName: symbol)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
        }
    }
}

private enum ActionMapDateFilter: Hashable, CaseIterable, Identifiable {
    case all
    case today
    case sevenDays
    case thirtyDays

    var id: Self { self }

    var title: String {
        switch self {
        case .all:
            return L10n.Map.allDates
        case .today:
            return L10n.Map.dateRangeToday
        case .sevenDays:
            return L10n.Map.dateRangeSevenDays
        case .thirtyDays:
            return L10n.Map.dateRangeThirtyDays
        }
    }

    func startDate(in calendar: Calendar) -> Date? {
        switch self {
        case .all:
            return nil
        case .today:
            return calendar.startOfDay(for: Date())
        case .sevenDays:
            guard let anchor = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: Date())) else {
                return nil
            }
            return anchor
        case .thirtyDays:
            guard let anchor = calendar.date(byAdding: .day, value: -29, to: calendar.startOfDay(for: Date())) else {
                return nil
            }
            return anchor
        }
    }
}

#Preview {
    let profileStore = ProfileStore.preview
    let profileID = profileStore.activeProfileID ?? UUID()

    var state = ProfileActionState()
    state.history = [
        BabyActionSnapshot(
            category: .feeding,
            startDate: Date().addingTimeInterval(-3600),
            endDate: Date().addingTimeInterval(-3300),
            feedingType: .bottle,
            bottleType: .formula,
            bottleVolume: 120,
            latitude: 37.776,
            longitude: -122.417,
            placename: "Mission District"
        ),
        BabyActionSnapshot(
            category: .diaper,
            startDate: Date().addingTimeInterval(-7200),
            endDate: Date().addingTimeInterval(-7100),
            diaperType: .both,
            latitude: 37.779,
            longitude: -122.414,
            placename: "Mission District"
        ),
        BabyActionSnapshot(
            category: .sleep,
            startDate: Date().addingTimeInterval(-10_800),
            endDate: Date().addingTimeInterval(-7200),
            latitude: 37.791,
            longitude: -122.405,
            placename: "Embarcadero"
        )
    ]

    let actionStore = ActionLogStore.previewStore(profiles: [profileID: state])

    UserDefaults.standard.set(true, forKey: "trackActionLocations")

    return NavigationStack {
        ActionMapView(tabResetID: UUID())
            .environmentObject(profileStore)
            .environmentObject(actionStore)
    }
    .environmentObject(LocationManager.shared)
}
