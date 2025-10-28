import SwiftUI
import PhotosUI
import UIKit

/// A sheet prompting the user to name the initial child profile on first launch.
@MainActor
struct InitialProfileNamePromptView: View {
    let onContinue: (String, Data?) -> Void
    let allowsDismissal: Bool

    @State private var name: String
    @State private var imageData: Data?
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var pendingCrop: PendingCropImage?
    @State private var isProcessingPhoto = false
    @State private var photoLoadingTask: Task<Void, Never>?
    @State private var activePhotoRequestID: UUID?
    @FocusState private var isNameFieldFocused: Bool

    init(
        initialName: String,
        initialImageData: Data? = nil,
        allowsDismissal: Bool,
        onContinue: @escaping (String, Data?) -> Void
    ) {
        self.onContinue = onContinue
        self.allowsDismissal = allowsDismissal
        _name = State(initialValue: initialName)
        _imageData = State(initialValue: initialImageData)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.Onboarding.profilePromptTitle)
                        .font(.title2.bold())
                    Text(L10n.Onboarding.profilePromptSubtitle)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text(L10n.Onboarding.profilePromptNameLabel)
                        .font(.footnote)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)

                    TextField(
                        L10n.Onboarding.profilePromptNamePlaceholder,
                        text: $name
                    )
                    .textFieldStyle(.roundedBorder)
                    .focused($isNameFieldFocused)
                    .submitLabel(.done)
                    .onSubmit(handleContinue)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text(L10n.Profiles.choosePhoto)
                        .font(.footnote)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)

                    profilePhotoSelector
                    processingPhotoIndicator
                }

                Spacer()

                Button(action: handleContinue) {
                    Text(L10n.Onboarding.profilePromptContinue)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(trimmedName.isEmpty)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(.systemBackground))
            .onAppear {
                isNameFieldFocused = true
            }
            .onDisappear {
                photoLoadingTask?.cancel()
                photoLoadingTask = nil
                activePhotoRequestID = nil
                selectedPhoto = nil
                isProcessingPhoto = false
            }
        }
        .interactiveDismissDisabled(!allowsDismissal)
        .presentationDetents([.medium])
        .presentationDragIndicator(.hidden)
        .fullScreenCover(item: $pendingCrop) { crop in
            ImageCropperView(image: crop.image) {
                pendingCrop = nil
            } onCrop: { croppedImage in
                if let data = croppedImage.compressedData() {
                    imageData = data
                }
                pendingCrop = nil
            }
            .preferredColorScheme(.dark)
        }
    }

    private func handleContinue() {
        let value = trimmedName
        guard value.isEmpty == false else { return }
        onContinue(value, imageData)
    }

    private var profilePhotoSelector: some View {
        ZStack(alignment: .bottomTrailing) {
            PhotosPicker(selection: $selectedPhoto, matching: .images, photoLibrary: .shared()) {
                ProfileAvatarView(imageData: imageData, size: 72)
                    .overlay(alignment: .bottomTrailing) {
                        if imageData == nil {
                            Image(systemName: "plus.circle.fill")
                                .symbolRenderingMode(.multicolor)
                                .font(.system(size: 20))
                                .shadow(radius: 1)
                                .accessibilityHidden(true)
                        }
                    }
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .accessibilityLabel(L10n.Profiles.choosePhoto)
            .onChange(of: selectedPhoto) { _, newValue in
                handlePhotoSelectionChange(newValue)
            }

            if imageData != nil {
                Button {
                    imageData = nil
                } label: {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(6)
                        .background(Color.red)
                        .clipShape(Circle())
                        .shadow(radius: 2)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.Profiles.removePhoto)
                .padding(4)
            }
        }
    }

    @ViewBuilder
    private var processingPhotoIndicator: some View {
        if isProcessingPhoto {
            HStack(spacing: 8) {
                ProgressView()
                Text(L10n.Profiles.photoProcessing)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func handlePhotoSelectionChange(_ newValue: PhotosPickerItem?) {
        photoLoadingTask?.cancel()
        guard let newValue else { return }


        isProcessingPhoto = true
        let requestID = UUID()
        activePhotoRequestID = requestID
        photoLoadingTask = Task {
            var loadedImage: UIImage?

            do {
                if let data = try await newValue.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    loadedImage = image
                }
            } catch {
                // Ignore errors for now
            }

            if Task.isCancelled == false, let image = loadedImage {
                await MainActor.run {
                    guard activePhotoRequestID == requestID else { return }
                    pendingCrop = PendingCropImage(image: image)
                }
            }

            await MainActor.run {
                guard activePhotoRequestID == requestID else { return }
                selectedPhoto = nil
                isProcessingPhoto = false
                activePhotoRequestID = nil
                photoLoadingTask = nil
            }
        }
    }
}

#Preview {
    InitialProfileNamePromptView(initialName: "", allowsDismissal: true) { _, _ in }
}

private extension InitialProfileNamePromptView {
    struct PendingCropImage: Identifiable {
        let id = UUID()
        let image: UIImage
    }
}
