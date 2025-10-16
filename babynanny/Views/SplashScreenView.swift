import SwiftUI
import UIKit

struct SplashScreenView: View {
    private let iconSize: CGFloat = 160

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            if let icon = UIImage.appIcon {
                Image(uiImage: icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: iconSize, height: iconSize)
                    .shadow(radius: 16)
                    .accessibilityHidden(true)
            } else {
                ProgressView()
                    .progressViewStyle(.circular)
                    .accessibilityLabel(Text(L10n.Splash.loading))
            }
        }
    }
}

#Preview {
    SplashScreenView()
}
