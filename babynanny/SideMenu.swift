//
//  SideMenu.swift
//  babynanny
//
//  Created by OpenAI Assistant on 2024/10/07.
//

import SwiftUI

struct SideMenu: View {
    let onSelectAllLogs: () -> Void
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
    SideMenu(onSelectAllLogs: {},
             onSelectSettings: {},
             onSelectShareData: {})
}
