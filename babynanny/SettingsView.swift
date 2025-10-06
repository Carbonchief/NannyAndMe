//
//  SettingsView.swift
//  babynanny
//
//  Created by OpenAI Assistant on 2024/10/07.
//

import SwiftUI

struct SettingsView: View {
    var body: some View {
        Form {
            Section(header: Text("Profile")) {
                HStack {
                    Image(systemName: "person.circle.fill")
                        .font(.largeTitle)
                        .foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading) {
                        Text("Caregiver Name")
                            .font(.headline)
                        Text("Edit your profile details")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section(header: Text("Notifications")) {
                Toggle(isOn: .constant(true)) {
                    Text("Enable reminders")
                }
                .disabled(true)
                .foregroundStyle(.secondary)
            }

            Section(header: Text("About")) {
                HStack {
                    Text("App Version")
                    Spacer()
                    Text("1.0")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Settings")
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}
