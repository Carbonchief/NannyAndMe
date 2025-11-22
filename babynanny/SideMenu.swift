//
//  SideMenu.swift
//  babynanny
//
//  Created by OpenAI Assistant on 2024/10/07.
//

import SwiftUI

struct SideMenu: View {
    @EnvironmentObject private var authManager: SupabaseAuthManager

    let onSelectAllLogs: () -> Void
    let onSelectSettings: () -> Void
    let onSelectShareData: () -> Void
    let onSelectManageAccount: () -> Void
    let onSelectAuthentication: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            header

            if let configurationError = authManager.configurationError {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.Menu.authUnavailable)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text(configurationError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            } else if authManager.isAuthenticated == false {
                Button(action: {
                    AnalyticsTracker.capture("login_prompt_opened")
                    onSelectAuthentication()
                }) {
                    Label(L10n.Menu.login, systemImage: "person.crop.circle.badge.plus")
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 10)
                }
            }

            VStack(alignment: .leading, spacing: 16) {
                Button(action: {
                    AnalyticsTracker.capture("menu_all_logs_tap")
                    onSelectAllLogs()
                }) {
                    Label(L10n.Menu.allLogs, systemImage: "list.bullet.rectangle")
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 10)
                }

                Button(action: {
                    AnalyticsTracker.capture("menu_share_data_tap")
                    onSelectShareData()
                }) {
                    Label(L10n.Menu.shareData, systemImage: "arrow.up.arrow.down.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 10)
                }

                Button(action: {
                    AnalyticsTracker.capture("menu_settings_tap")
                    onSelectSettings()
                }) {
                    Label(L10n.Menu.settings, systemImage: "gearshape.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 10)
                }

                if authManager.isAuthenticated {
                    Button(action: {
                        AnalyticsTracker.capture("menu_manage_account_tap")
                        onSelectManageAccount()
                    }) {
                        Label(L10n.Menu.manageAccount, systemImage: "person.crop.circle.badge.minus")
                            .font(.headline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 10)
                    }
                }
            }

            Spacer()

            VStack(alignment: .leading, spacing: 16) {
                if authManager.isAuthenticated, let email = authManager.currentUserEmail {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.Menu.signedInAccount)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(email)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                if authManager.isAuthenticated {
                    Button(role: .destructive) {
                        AnalyticsTracker.capture("logout_tap")
                        Task { await authManager.signOut() }
                    } label: {
                        Label(L10n.Menu.logout, systemImage: "rectangle.portrait.and.arrow.right")
                            .font(.headline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 10)
                    }
                }

                if let versionText {
                    Text(versionText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 32)
        .frame(maxWidth: 260, alignment: .leading)
        .frame(maxHeight: .infinity)
        .background(.ultraThinMaterial)
        .ignoresSafeArea()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.Menu.title)
                .font(.largeTitle)
                .fontWeight(.bold)
            Text(L10n.Menu.subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 48)
    }

    private var versionText: String? {
        guard let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String else {
            return nil
        }

        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String

        let displayVersion: String
        if let build, build != version {
            displayVersion = "\(version) (\(build))"
        } else {
            displayVersion = version
        }

        return L10n.Menu.version(displayVersion)
    }
}

#Preview {
    SideMenu(onSelectAllLogs: {},
             onSelectSettings: {},
             onSelectShareData: {},
             onSelectManageAccount: {},
             onSelectAuthentication: {})
        .environmentObject(SupabaseAuthManager())
}
