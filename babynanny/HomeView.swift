//
//  HomeView.swift
//  babynanny
//
//  Created by OpenAI Assistant on 2024/10/07.
//

import SwiftUI

struct HomeView: View {
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "house.fill")
                .font(.system(size: 52))
                .foregroundStyle(Color.accentColor)

            VStack(spacing: 8) {
                Text("Welcome Home")
                    .font(.title)
                    .fontWeight(.semibold)

                Text("Here you can manage your daily nanny tasks and keep an eye on ongoing activities.")
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
    HomeView()
}
