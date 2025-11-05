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
    let onSelectAuthentication: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.Menu.title)
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Text(L10n.Menu.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 48)

            if let configurationError = authManager.configurationError {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.Menu.authUnavailable)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text(configurationError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            } else if authManager.isAuthenticated {
                VStack(alignment: .leading, spacing: 8) {
                    if let email = authManager.currentUserEmail {
                        Text(L10n.Menu.loggedInAs(email))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        Task { await authManager.signOut() }
                    } label: {
                        Label(L10n.Menu.logout, systemImage: "rectangle.portrait.and.arrow.right")
                            .font(.headline)
                    }
                }
            } else {
                Button(action: {
                    onSelectAuthentication()
                }) {
                    Label(L10n.Menu.login, systemImage: "person.crop.circle.badge.plus")
                        .font(.headline)
                }
            }

            Button(action: {
                onSelectAllLogs()
            }) {
                Label(L10n.Menu.allLogs, systemImage: "list.bullet.rectangle")
                    .font(.headline)
            }

            Button(action: {
                onSelectShareData()
            }) {
                Label(L10n.Menu.shareData, systemImage: "arrow.up.arrow.down.circle.fill")
                    .font(.headline)
            }

            Button(action: {
                onSelectSettings()
            }) {
                Label(L10n.Menu.settings, systemImage: "gearshape.fill")
                    .font(.headline)
            }

            Spacer()

            if let versionText {
                Text(versionText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 32)
        .frame(maxWidth: 260, alignment: .leading)
        .frame(maxHeight: .infinity)
        .background(.ultraThinMaterial)
        .ignoresSafeArea()
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
             onSelectAuthentication: {})
        .environmentObject(SupabaseAuthManager())
}
