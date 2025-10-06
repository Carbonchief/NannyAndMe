//
//  StatsView.swift
//  babynanny
//
//  Created by OpenAI Assistant on 2024/10/07.
//

import SwiftUI

struct StatsView: View {
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "chart.bar.fill")
                .font(.system(size: 52))
                .foregroundStyle(Color.accentColor)

            VStack(spacing: 8) {
                Text("Stats Overview")
                    .font(.title)
                    .fontWeight(.semibold)

                Text("Track daily progress, sleep schedules, and feeding stats in one glance.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .background(Color(.systemGroupedBackground))
    }
}

#Preview {
    StatsView()
}
