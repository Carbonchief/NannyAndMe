import SwiftUI

struct LaunchScreenView: View {
    var body: some View {
        ZStack {
            Color("LaunchBackground")
                .ignoresSafeArea()

            VStack(spacing: 12) {
                Image("AppLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 180)

                Text(LocalizedStringKey("menu.title"))
                    .font(.title)
                    .bold()
                    .foregroundColor(.accentColor)
            }
        }
    }
}

#Preview {
    LaunchScreenView()
}
