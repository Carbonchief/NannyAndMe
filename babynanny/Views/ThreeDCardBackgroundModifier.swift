import SwiftUI

private struct ThreeDCardBackgroundModifier: ViewModifier {
    let baseColor: Color
    let borderColor: Color
    let borderLineWidth: CGFloat
    let cornerRadius: CGFloat
    let highlightTint: Color
    let highlightOpacity: Double
    let highlightShadowOpacity: Double
    let highlightShadowRadius: CGFloat
    let highlightShadowOffset: CGSize
    let dropShadowOpacity: Double
    let dropShadowRadius: CGFloat
    let dropShadowOffset: CGSize

    func body(content: Content) -> some View {
        content
            .background(
                ThreeDCardBackground(
                    baseColor: baseColor,
                    borderColor: borderColor,
                    borderLineWidth: borderLineWidth,
                    cornerRadius: cornerRadius,
                    highlightTint: highlightTint,
                    highlightOpacity: highlightOpacity,
                    highlightShadowOpacity: highlightShadowOpacity,
                    highlightShadowRadius: highlightShadowRadius,
                    highlightShadowOffset: highlightShadowOffset,
                    dropShadowOpacity: dropShadowOpacity,
                    dropShadowRadius: dropShadowRadius,
                    dropShadowOffset: dropShadowOffset
                )
            )
    }
}

private struct ThreeDCardBackground: View {
    let baseColor: Color
    let borderColor: Color
    let borderLineWidth: CGFloat
    let cornerRadius: CGFloat
    let highlightTint: Color
    let highlightOpacity: Double
    let highlightShadowOpacity: Double
    let highlightShadowRadius: CGFloat
    let highlightShadowOffset: CGSize
    let dropShadowOpacity: Double
    let dropShadowRadius: CGFloat
    let dropShadowOffset: CGSize

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        return shape
            .fill(baseColor)
            .overlay(
                shape
                    .fill(
                        LinearGradient(colors: [
                            highlightTint.opacity(highlightOpacity),
                            highlightTint.opacity(0.02)
                        ], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
            )
            .overlay(
                shape
                    .stroke(borderColor, lineWidth: borderLineWidth)
            )
            .shadow(color: highlightTint.opacity(highlightShadowOpacity),
                    radius: highlightShadowRadius,
                    x: highlightShadowOffset.width,
                    y: highlightShadowOffset.height)
            .shadow(color: Color.black.opacity(dropShadowOpacity),
                    radius: dropShadowRadius,
                    x: dropShadowOffset.width,
                    y: dropShadowOffset.height)
            .compositingGroup()
    }
}

extension View {
    func threeDCardBackground(baseColor: Color,
                              borderColor: Color = Color.black.opacity(0.06),
                              borderLineWidth: CGFloat = 1,
                              cornerRadius: CGFloat = 18,
                              highlightTint: Color = .white,
                              highlightOpacity: Double = 0.18,
                              highlightShadowOpacity: Double = 0.4,
                              highlightShadowRadius: CGFloat = 6,
                              highlightShadowOffset: CGSize = CGSize(width: -4, height: -4),
                              dropShadowOpacity: Double = 0.16,
                              dropShadowRadius: CGFloat = 12,
                              dropShadowOffset: CGSize = CGSize(width: 8, height: 10)) -> some View {
        modifier(
            ThreeDCardBackgroundModifier(
                baseColor: baseColor,
                borderColor: borderColor,
                borderLineWidth: borderLineWidth,
                cornerRadius: cornerRadius,
                highlightTint: highlightTint,
                highlightOpacity: highlightOpacity,
                highlightShadowOpacity: highlightShadowOpacity,
                highlightShadowRadius: highlightShadowRadius,
                highlightShadowOffset: highlightShadowOffset,
                dropShadowOpacity: dropShadowOpacity,
                dropShadowRadius: dropShadowRadius,
                dropShadowOffset: dropShadowOffset
            )
        )
    }
}
