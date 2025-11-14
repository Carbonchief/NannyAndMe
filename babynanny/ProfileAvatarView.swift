import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct ProfileAvatarView: View {
    let imageData: Data?
    var size: CGFloat

    var body: some View {
        avatarImage
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(
                Circle()
                    .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
            )
            .shadow(radius: 2)
    }

    private var avatarImage: Image {
#if canImport(UIKit)
        if let imageData,
           let uiImage = UIImage(data: imageData) {
            return Image(uiImage: uiImage)
        }
#endif
        return Image(systemName: "person.crop.circle.fill")
    }
}

#Preview {
    VStack(spacing: 16) {
        ProfileAvatarView(imageData: nil, size: 60)
        ProfileAvatarView(imageData: nil, size: 36)
    }
    .padding()
}
