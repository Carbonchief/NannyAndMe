//
//  SideMenu.swift
//  babynanny
//
//  Created by OpenAI Assistant on 2024/10/07.
//

import SwiftUI

struct SideMenu: View {
    let onSelectSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Nanny & Me")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Text("Quick actions")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 48)

            Button(action: onSelectSettings) {
                Label("Settings", systemImage: "gearshape.fill")
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
    SideMenu(onSelectSettings: {})
}
