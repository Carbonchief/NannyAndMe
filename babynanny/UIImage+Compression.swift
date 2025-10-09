import UIKit

extension UIImage {
    func resized(maxPixelSize: CGFloat) -> UIImage {
        let maxDimension = max(size.width, size.height)
        guard maxDimension > maxPixelSize else { return self }

        let scaleRatio = maxPixelSize / maxDimension
        let newSize = CGSize(width: size.width * scaleRatio, height: size.height * scaleRatio)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false

        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    func compressedData(maxPixelSize: CGFloat = 512, compressionQuality: CGFloat = 0.7) -> Data? {
        let resizedImage = resized(maxPixelSize: maxPixelSize)
        if let jpeg = resizedImage.jpegData(compressionQuality: compressionQuality) {
            return jpeg
        }

        return resizedImage.pngData()
    }
}
