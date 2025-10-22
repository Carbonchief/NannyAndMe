import MapKit
import SwiftData
import SwiftUI

/// Displays logged baby actions on a map with filtering by action type and date range.
struct ActionsMapView: View {
    @EnvironmentObject private var profileStore: ProfileStore
    @Query(sort: [SortDescriptor(\.startDateRawValue, order: .reverse)])
    private var actions: [BabyAction]
    @State private var selectedCategory: BabyActionCategory?
    @State private var startDate: Date = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    @State private var endDate: Date = Date()
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.3349, longitude: -122.0090),
        span: MKCoordinateSpan(latitudeDelta: 0.25, longitudeDelta: 0.25)
    )

    private var calendar: Calendar { Calendar.current }

    private var activeProfileID: UUID? {
        profileStore.activeProfileID
    }

    private var filteredAnnotations: [ActionAnnotation] {
        guard let activeProfileID else { return [] }
        let windowStart = calendar.startOfDay(for: startDate)
        let windowEnd = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: endDate) ?? endDate

        return actions
            .filter { action in
                guard action.profile?.resolvedProfileID == activeProfileID else { return false }
                guard let latitude = action.latitude, let longitude = action.longitude else { return false }
                guard selectedCategory == nil || action.category == selectedCategory else { return false }
                let timestamp = action.startDate
                guard timestamp >= windowStart && timestamp <= windowEnd else { return false }
                let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
                guard CLLocationCoordinate2DIsValid(coordinate) else { return false }
                return true
            }
            .map { action in
                ActionAnnotation(action: action)
            }
    }

    var body: some View {
        VStack(spacing: 0) {
            FilterBar(selectedCategory: $selectedCategory,
                      startDate: $startDate,
                      endDate: $endDate)
                .padding(.horizontal, 16)
                .padding(.top, 16)

            Map(coordinateRegion: $region, annotationItems: filteredAnnotations) { annotation in
                MapAnnotation(coordinate: annotation.coordinate) {
                    AnnotationView(annotation: annotation)
                }
            }
            .mapStyle(.standard)
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
        .onAppear(perform: updateRegion)
        .onChange(of: filteredAnnotations) { _ in
            updateRegion()
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
    }

    private func updateRegion() {
        guard filteredAnnotations.isEmpty == false else { return }
        let coordinates = filteredAnnotations.map(\.coordinate)
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
    struct ActionAnnotation: Identifiable {
        let id: UUID
        let coordinate: CLLocationCoordinate2D
        let category: BabyActionCategory
        let placename: String?
        let timestamp: Date

        init(action: BabyAction) {
            id = action.id
            coordinate = CLLocationCoordinate2D(latitude: action.latitude ?? 0, longitude: action.longitude ?? 0)
            category = action.category
            placename = action.placename
            timestamp = action.startDate
        }

        var iconName: String {
            category.icon
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
    }

    struct AnnotationView: View {
        let annotation: ActionAnnotation

        var body: some View {
            VStack(spacing: 6) {
                Image(systemName: annotation.iconName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .padding(10)
                    .background(Circle().fill(Color.accentColor))
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

    struct FilterBar: View {
        @Binding var selectedCategory: BabyActionCategory?
        @Binding var startDate: Date
        @Binding var endDate: Date

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.Map.actionTypeFilter)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Picker(L10n.Map.actionTypeFilter, selection: $selectedCategory) {
                        Text(L10n.Map.allActions)
                            .tag(BabyActionCategory?.none)
                        ForEach(BabyActionCategory.allCases) { category in
                            Text(category.title)
                                .tag(BabyActionCategory?.some(category))
                        }
                    }
                    .pickerStyle(.segmented)
                    .postHogLabel("map.filter.actionType")
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.Map.dateRangeFilter)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    HStack(spacing: 12) {
                        DatePicker(L10n.Map.startDate,
                                   selection: $startDate,
                                   displayedComponents: .date)
                            .datePickerStyle(.compact)
                            .postHogLabel("map.filter.startDate")
                        DatePicker(L10n.Map.endDate,
                                   selection: $endDate,
                                   displayedComponents: .date)
                            .datePickerStyle(.compact)
                            .postHogLabel("map.filter.endDate")
                    }
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )
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

#Preview {
    let container = AppDataStack.makeModelContainer(inMemory: true)
    let context = ModelContext(container)
    let profile = Profile(name: "Luna")
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

    let previewProfile = ChildProfile(id: profile.profileID,
                                      name: "Luna",
                                      birthDate: Date().addingTimeInterval(-120 * 24 * 60 * 60))
    let profileStore = ProfileStore(initialProfiles: [previewProfile],
                                    activeProfileID: profile.profileID,
                                    directory: FileManager.default.temporaryDirectory,
                                    filename: "mapPreviewProfiles.json")
    profileStore.updateActiveProfile { child in
        child.name = "Luna"
    }

    return NavigationStack {
        ActionsMapView()
            .environmentObject(profileStore)
    }
    .modelContainer(container)
}
