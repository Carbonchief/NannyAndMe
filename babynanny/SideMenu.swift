//
//  SideMenu.swift
//  babynanny
//
//  Created by OpenAI Assistant on 2024/10/07.
//

import SwiftUI

struct SideMenu: View {
    let isCloudSharingAvailable: Bool
    let onSelectAllLogs: () -> Void
    let onSelectShareProfile: () -> Void
    let onSelectSettings: () -> Void
    let onSelectShareData: () -> Void

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

            Button(action: {
                Analytics.capture("menu_select_allLogs_drawer", properties: ["source": "side_menu"])
                onSelectAllLogs()
            }) {
                Label(L10n.Menu.allLogs, systemImage: "list.bullet.rectangle")
                    .font(.headline)
            }
            .postHogLabel("menu.allLogs")

            if isCloudSharingAvailable {
                Button(action: {
                    Analytics.capture("menu_select_shareProfile_drawer", properties: ["source": "side_menu"])
                    onSelectShareProfile()
                }) {
                    Label(L10n.Menu.shareProfile, systemImage: "person.2.fill")
                        .font(.headline)
                }
                .postHogLabel("menu.shareProfile")
            }

            Button(action: {
                Analytics.capture("menu_select_shareData_drawer", properties: ["source": "side_menu"])
                onSelectShareData()
            }) {
                Label(L10n.Menu.shareData, systemImage: "arrow.up.arrow.down.circle.fill")
                    .font(.headline)
            }
            .postHogLabel("menu.shareData")

            Button(action: {
                Analytics.capture("menu_select_settings_drawer", properties: ["source": "side_menu"])
                onSelectSettings()
            }) {
                Label(L10n.Menu.settings, systemImage: "gearshape.fill")
                    .font(.headline)
            }
            .postHogLabel("menu.settings")

            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 32)
        .frame(maxWidth: 260, alignment: .leading)
        .frame(maxHeight: .infinity)
        .background(.ultraThinMaterial)
        .ignoresSafeArea()
    }
}

#Preview {
    SideMenu(isCloudSharingAvailable: true,
             onSelectAllLogs: {},
             onSelectShareProfile: {},
             onSelectSettings: {},
             onSelectShareData: {})
}
