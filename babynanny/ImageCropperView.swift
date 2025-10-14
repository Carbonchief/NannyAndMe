import SwiftUI
import UIKit

struct ImageCropperView: View {

    let image: UIImage
    var onCancel: () -> Void
    var onCrop: (UIImage) -> Void

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var isInitialScaleApplied = false

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let size = geometry.size
                let horizontalPadding: CGFloat = 32
                let availableWidth = max(size.width - horizontalPadding, 0)
                let cropLength = max(min(availableWidth, size.height), 1)
                let cropSize = CGSize(width: cropLength, height: cropLength)
                let imageWidth = max(image.size.width, 1)
                let imageHeight = max(image.size.height, 1)
                let baseScale = min(cropSize.width / imageWidth, cropSize.height / imageHeight)
                let widthScale = cropSize.width / (imageWidth * baseScale)
                let heightScale = cropSize.height / (imageHeight * baseScale)
                let minScale = max(1, widthScale, heightScale)

                ZStack {
                    Color.black
                        .ignoresSafeArea()

                    VStack(spacing: 24) {
                        Spacer()

                        CroppingCanvas(
                            image: image,
                            cropSize: cropSize,
                            scale: scale,
                            offset: offset,
                            showsOverlay: true
                        )
                        .gesture(
                            SimultaneousGesture(
                                DragGesture()
                                    .onChanged { value in
                                        let translation = CGSize(
                                            width: lastOffset.width + value.translation.width,
                                            height: lastOffset.height + value.translation.height
                                        )
                                        offset = clampOffset(
                                            translation,
                                            cropSize: cropSize,
                                            scale: scale,
                                            baseScale: baseScale
                                        )
                                    }
                                    .onEnded { _ in
                                        lastOffset = offset
                                    },
                                MagnificationGesture()
                                    .onChanged { value in
                                        let updatedScale = clampScale(
                                            lastScale * value,
                                            minScale: minScale
                                        )
                                        scale = updatedScale
                                        offset = clampOffset(
                                            offset,
                                            cropSize: cropSize,
                                            scale: updatedScale,
                                            baseScale: baseScale
                                        )
                                    }
                                    .onEnded { value in
                                        let updatedScale = clampScale(
                                            lastScale * value,
                                            minScale: minScale
                                        )
                                        scale = updatedScale
                                        lastScale = updatedScale
                                        offset = clampOffset(
                                            offset,
                                            cropSize: cropSize,
                                            scale: updatedScale,
                                            baseScale: baseScale
                                        )
                                        lastOffset = offset
                                    }
                            )
                        )

                        Text(L10n.Profiles.cropPhotoInstruction)
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.85))

                        Spacer()
                    }
                    .padding()
                }
                .task {
                    guard isInitialScaleApplied == false else { return }
                    isInitialScaleApplied = true
                    scale = minScale
                    lastScale = minScale
                    offset = .zero
                    lastOffset = .zero
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(L10n.Common.cancel) {
                            onCancel()
                        }
                        .postHogLabel("imageCropper.cancel")
                        .tint(.white)
                    }
                    ToolbarItem(placement: .principal) {
                        Text(L10n.Profiles.cropPhotoTitle)
                            .font(.headline)
                            .foregroundStyle(.white)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(L10n.Common.done) {
                            cropImage(cropSize: cropSize)
                        }
                        .postHogLabel("imageCropper.confirm")
                        .tint(.white)
                        .fontWeight(.semibold)
                    }
                }
            }
            .background(Color.black.ignoresSafeArea())
        }
    }
}

private extension ImageCropperView {
    func clampScale(_ value: CGFloat, minScale: CGFloat) -> CGFloat {
        let maximumScale: CGFloat = 6
        return min(max(value, minScale), maximumScale)
    }

    func clampOffset(
        _ offset: CGSize,
        cropSize: CGSize,
        scale: CGFloat,
        baseScale: CGFloat
    ) -> CGSize {
        let imageWidth = max(image.size.width, 1)
        let imageHeight = max(image.size.height, 1)
        let scaledWidth = imageWidth * baseScale * scale
        let scaledHeight = imageHeight * baseScale * scale

        let horizontalLimit = max((scaledWidth - cropSize.width) / 2, 0)
        let verticalLimit = max((scaledHeight - cropSize.height) / 2, 0)

        let clampedX: CGFloat
        if horizontalLimit == 0 {
            clampedX = 0
        } else {
            clampedX = min(max(offset.width, -horizontalLimit), horizontalLimit)
        }

        let clampedY: CGFloat
        if verticalLimit == 0 {
            clampedY = 0
        } else {
            clampedY = min(max(offset.height, -verticalLimit), verticalLimit)
        }

        return CGSize(width: clampedX, height: clampedY)
    }

    func cropImage(cropSize: CGSize) {
        let renderer = ImageRenderer(content: CroppingCanvas(
            image: image,
            cropSize: cropSize,
            scale: scale,
            offset: offset,
            showsOverlay: false
        ))
        renderer.scale = UIScreen.main.scale

        if let cropped = renderer.uiImage {
            onCrop(cropped)
        }
    }
}

private struct CroppingCanvas: View {
    let image: UIImage
    let cropSize: CGSize
    let scale: CGFloat
    let offset: CGSize
    let showsOverlay: Bool

    var body: some View {
        ZStack {
            transformedImage

            if showsOverlay {
                ZStack {
                    transformedImage
                        .blur(radius: 12)
                        .mask(
                            CircularHoleShape(cropSize: cropSize)
                                .fill(.white, style: FillStyle(eoFill: true))
                        )

                    CircularHoleShape(cropSize: cropSize)
                        .fill(Color.black.opacity(0.55), style: FillStyle(eoFill: true))

                    Circle()
                        .strokeBorder(Color.white.opacity(0.85), lineWidth: 2)
                        .frame(width: cropSize.width, height: cropSize.height)
                }
                .allowsHitTesting(false)
            }
        }
        .frame(width: cropSize.width, height: cropSize.height)
        .clipped()
        .mask {
            if showsOverlay {
                Rectangle()
            } else {
                Circle()
                    .frame(width: cropSize.width, height: cropSize.height)
            }
        }
    }
}

private extension CroppingCanvas {
    var transformedImage: some View {
        Image(uiImage: image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .scaleEffect(scale)
            .offset(offset)
            .frame(width: cropSize.width, height: cropSize.height)
            .clipped()
    }
}

private struct CircularHoleShape: Shape {
    let cropSize: CGSize

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(rect)

        let circleRect = CGRect(
            x: (rect.width - cropSize.width) / 2,
            y: (rect.height - cropSize.height) / 2,
            width: cropSize.width,
            height: cropSize.height
        )

        path.addEllipse(in: circleRect)
        return path
    }
}

#Preview {
    let sampleImage = UIImage(systemName: "person.crop.circle") ?? UIImage()
    return ImageCropperView(image: sampleImage, onCancel: {}, onCrop: { _ in })
}
