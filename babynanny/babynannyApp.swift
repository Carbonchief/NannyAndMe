//
//  babynannyApp.swift
//  babynanny
//
//  Created by Luan van der Walt on 2025/10/06.
//

import CloudKit
import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

@main
struct babynannyApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var shareDataCoordinator = ShareDataCoordinator()
    @StateObject private var appDataStack: AppDataStack
    @StateObject private var profileStore: ProfileStore
    @StateObject private var actionStore: ActionLogStore
    @State private var isShowingSplashScreen = true
    @State private var pendingShareMetadata: CKShare.Metadata?
    @State private var shareAcceptanceAlert: ShareAcceptanceAlert?

    init() {

        let stack = AppDataStack()
        let scheduler = UserNotificationReminderScheduler()
        let profileStore = ProfileStore(reminderScheduler: scheduler)
        let actionStore = ActionLogStore(modelContext: stack.mainContext,
                                         reminderScheduler: scheduler,
                                         dataStack: stack)
        profileStore.registerActionStore(actionStore)
        actionStore.registerProfileStore(profileStore)

        _appDataStack = StateObject(wrappedValue: stack)
        _profileStore = StateObject(wrappedValue: profileStore)
        _actionStore = StateObject(wrappedValue: actionStore)
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView()
                    .environmentObject(appDataStack)
                    .environmentObject(profileStore)
                    .environmentObject(actionStore)
                    .environmentObject(shareDataCoordinator)
                    .environmentObject(LocationManager.shared)
                    .onOpenURL { url in
                        if handleDurationActivityURL(url) {
                            return
                        }
                        if #available(iOS 17.0, *), let metadata = try? CKShare.Metadata(from: url) {
                            pendingShareMetadata = metadata
                            if scenePhase == .active {
                                let metadataToProcess = metadata
                                pendingShareMetadata = nil
                                handleShareAcceptance(for: metadataToProcess)
                            }
                            return
                        }
                        guard shouldHandle(url: url) else { return }
                        shareDataCoordinator.handleIncomingFile(url: url)
                    }

                if shareDataCoordinator.isProcessingShareAcceptance {
                    Color.black.opacity(0.25)
                        .ignoresSafeArea()
                    ProgressView(L10n.ShareData.CloudKit.acceptingShare)
                        .padding(24)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .shadow(radius: 12)
                }

                if isShowingSplashScreen {
                    SplashScreenView()
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            .task {
                try? await Task.sleep(for: .seconds(1.2))
                await MainActor.run {
                    withAnimation(.easeOut(duration: 0.35)) {
                        isShowingSplashScreen = false
                    }
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                guard newPhase == .active else { return }
                guard #available(iOS 17.0, *), let metadata = pendingShareMetadata else { return }
                pendingShareMetadata = nil
                handleShareAcceptance(for: metadata)
            }
            .alert(item: $shareAcceptanceAlert) { alert in
                Alert(
                    title: Text(alert.title),
                    message: Text(alert.message),
                    dismissButton: .default(Text(L10n.Common.done))
                )
            }
            .modelContainer(appDataStack.modelContainer)
        }
    }
}

private extension babynannyApp {
    @available(iOS 17.0, *)
    func handleShareAcceptance(for metadata: CKShare.Metadata) {
        Task { @MainActor in
            shareDataCoordinator.beginShareAcceptance()
            defer { shareDataCoordinator.completeShareAcceptance() }
            do {
                try await acceptShare(metadata: metadata)
            } catch {
                shareAcceptanceAlert = ShareAcceptanceAlert(
                    title: L10n.ShareData.Alert.cloudShareFailureTitle,
                    message: L10n.ShareData.Alert.cloudShareFailureMessage(error.localizedDescription)
                )
            }
        }
    }

    @available(iOS 17.0, *)
    @MainActor
    func acceptShare(metadata: CKShare.Metadata) async throws {
        guard let scene = activeWindowScene() else {
            throw ShareAcceptanceError.missingScene
        }
        try await appDataStack.modelContainer.acceptShare(metadata, from: scene)
        await actionStore.performUserInitiatedRefresh()
    }

    func activeWindowScene() -> UIWindowScene? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
    }

    func shouldHandle(url: URL) -> Bool {
        if let contentType = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType {
            return contentType.conforms(to: .json)
        }
        return url.pathExtension.lowercased() == "json"
    }

    func handleDurationActivityURL(_ url: URL) -> Bool {
        guard url.scheme == "nannyme", url.host == "activity" else { return false }

        let pathComponents = url.pathComponents.dropFirst()
        guard let identifierComponent = pathComponents.first,
              let actionID = UUID(uuidString: identifierComponent) else { return false }

        if pathComponents.dropFirst().first == "stop" {
            actionStore.stopAction(withID: actionID)
            return true
        }

        return false
    }
}

private enum ShareAcceptanceError: LocalizedError {
    case missingScene

    var errorDescription: String? {
        switch self {
        case .missingScene:
            return L10n.ShareData.Alert.cloudShareFailureMessage("")
        }
    }
}

private struct ShareAcceptanceAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}
