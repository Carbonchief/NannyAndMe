import SwiftUI
import UIKit
import CoreImage.CIFilterBuiltins

struct ShareDataQRCodeView: View {
    let email: String

    @Environment(\.dismiss) private var dismiss
    private let generator = ShareDataQRCodeGenerator()

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                qrCodeImage
                    .frame(width: 240, height: 240)

                VStack(spacing: 4) {
                    Text(L10n.ShareData.QRCode.emailLabel)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text(email)
                        .font(.title3)
                        .multilineTextAlignment(.center)
                        .textSelection(.enabled)
                }

                Text(L10n.ShareData.QRCode.description)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Spacer()
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGroupedBackground))
            .navigationTitle(L10n.ShareData.QRCode.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.Common.done) { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private var qrCodeImage: some View {
        if let image = generator.makeImage(from: email) {
            Image(uiImage: image)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .shadow(radius: 4)
        } else {
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.secondarySystemGroupedBackground))
                .overlay {
                    ProgressView()
                }
        }
    }
}

struct ShareDataQRCodeGenerator {
    private let context = CIContext()

    func makeImage(from value: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        let data = Data(value.utf8)
        filter.setValue(data, forKey: "inputMessage")
        filter.correctionLevel = "Q"

        guard let outputImage = filter.outputImage else { return nil }
        let transform = CGAffineTransform(scaleX: 12, y: 12)
        let scaled = outputImage.transformed(by: transform)

        if let cgImage = context.createCGImage(scaled, from: scaled.extent) {
            return UIImage(cgImage: cgImage)
        }
        return nil
    }
}
