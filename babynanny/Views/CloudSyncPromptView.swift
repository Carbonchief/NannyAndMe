import SwiftUI
import UIKit

struct CloudSyncPromptView: View {
    @EnvironmentObject private var cloudStatusController: CloudAccountStatusController
    @EnvironmentObject private var appDataStack: AppDataStack
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "icloud")
                    .font(.system(size: 56, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                Text(L10n.CloudPrompt.title)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)
                Text(L10n.CloudPrompt.message)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                VStack(spacing: 16) {
                    Button {
                        Analytics.capture("cloudPrompt_open_settings_button")
                        openSystemSettings()
                    } label: {
                        Text(L10n.CloudPrompt.openSettings)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .postHogLabel("cloudPrompt.openSettings")

                    Button {
                        Analytics.capture("cloudPrompt_stay_local_button")
                        cloudStatusController.selectLocalOnly()
                        appDataStack.setCloudSyncEnabled(false)
                        dismiss()
                    } label: {
                        Text(L10n.CloudPrompt.keepLocal)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .postHogLabel("cloudPrompt.keepLocal")
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 32)
            .navigationTitle(L10n.CloudPrompt.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.Common.close) {
                        Analytics.capture("cloudPrompt_dismiss_toolbar")
                        dismiss()
                    }
                    .postHogLabel("cloudPrompt.dismiss")
                }
            }
        }
    }

    private func openSystemSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            openURL(url)
            return
        }
        if let appleIDURL = URL(string: "App-Prefs:root=APPLE_ACCOUNT") {
            openURL(appleIDURL)
        }
    }
}
*** End of File
