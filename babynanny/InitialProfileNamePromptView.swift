import SwiftUI
import PhotosUI
import UIKit

/// A sheet prompting the user to name the initial child profile on first launch.
struct InitialProfileNamePromptView: View {
    let onContinue: (String, Data?) -> Void
    let allowsDismissal: Bool

    @State private var name: String
    @State private var imageData: Data?
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
                    .postHogLabel("onboarding.profileName")
                    .onSubmit(handleContinue)
                }

                InitialProfilePhotoPicker(imageData: $imageData)

                Spacer()

                Button(action: handleContinue) {
                    Text(L10n.Onboarding.profilePromptContinue)
                        .frame(maxWidth: .infinity)
                }
                .postHogLabel("onboarding.continue")
                .phCaptureTap(
                    event: "onboarding_profile_continue_button",
                    properties: ["is_name_empty": trimmedName.isEmpty ? "true" : "false"]
                )
                .buttonStyle(.borderedProminent)
                .disabled(trimmedName.isEmpty)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(.systemBackground))
            .onAppear {
                isNameFieldFocused = true
            }
        }
        .interactiveDismissDisabled(!allowsDismissal)
        .presentationDetents([.medium])
        .presentationDragIndicator(.hidden)
        .phScreen("onboarding_profile_prompt_initialProfileNamePromptView")
    }

    private func handleContinue() {
        let value = trimmedName
        guard value.isEmpty == false else { return }
        Analytics.capture(
            "onboarding_profile_submit_name",
            properties: [
                "name_length": "\(value.count)",
                "has_photo": imageData == nil ? "false" : "true"
            ]
        )
        onContinue(value, imageData)
    }
}

#Preview {
    InitialProfileNamePromptView(initialName: "", allowsDismissal: true) { _, _ in }
}

private struct InitialProfilePhotoPicker: View {
    @Binding var imageData: Data?

    @State private var selectedPhoto: PhotosPickerItem?
    @State private var pendingCrop: PendingCropImage?
    @State private var isProcessingPhoto = false
    @State private var photoLoadingTask: Task<Void, Never>?
    @State private var activePhotoRequestID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.Profiles.choosePhoto)
                .font(.footnote)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            ZStack(alignment: .topTrailing) {
                PhotosPicker(selection: $selectedPhoto, matching: .images, photoLibrary: .shared()) {
                    HStack(spacing: 16) {
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

                        VStack(alignment: .leading, spacing: 4) {
                            Text(L10n.Profiles.choosePhoto)
                                .font(.body.weight(.semibold))
                            Text(
                                imageData == nil
                                    ? L10n.Profiles.choosePhotoDetailAdd
                                    : L10n.Profiles.choosePhotoDetailChange
                            )
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color(.secondarySystemBackground))
                    )
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .postHogLabel("onboarding.profilePhotoPicker")
                .accessibilityLabel(L10n.Profiles.choosePhoto)
                .accessibilityHint(
                    imageData == nil
                        ? L10n.Profiles.choosePhotoDetailAdd
                        : L10n.Profiles.choosePhotoDetailChange
                )
                .onChange(of: selectedPhoto) { newValue in
                    handlePhotoSelectionChange(newValue)
                }

                if imageData != nil {
                    Button {
                        Analytics.capture("onboarding_remove_profile_photo_button")
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
                    .postHogLabel("onboarding.profilePhotoRemove")
                    .phCaptureTap(event: "onboarding_remove_profile_photo_button")
                    .accessibilityLabel(L10n.Profiles.removePhoto)
                    .padding(8)
                }
            }

            if isProcessingPhoto {
                HStack(spacing: 8) {
                    ProgressView()
                    Text(L10n.Profiles.photoProcessing)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .fullScreenCover(item: $pendingCrop) { crop in
            ImageCropperView(image: crop.image) {
                cancelPendingWork()
                pendingCrop = nil
            } onCrop: { croppedImage in
                if let data = croppedImage.compressedData() {
                    imageData = data
                }
                pendingCrop = nil
            }
            .preferredColorScheme(.dark)
        }
        .onDisappear {
            cancelPendingWork()
        }
    }

    private func handlePhotoSelectionChange(_ newValue: PhotosPickerItem?) {
        photoLoadingTask?.cancel()
        guard let newValue else { return }

        Analytics.capture("onboarding_select_profile_photo_picker")

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

    private func cancelPendingWork() {
        photoLoadingTask?.cancel()
        photoLoadingTask = nil
        activePhotoRequestID = nil
        selectedPhoto = nil
        isProcessingPhoto = false
        pendingCrop = nil
    }

    private struct PendingCropImage: Identifiable {
        let id = UUID()
        let image: UIImage
    }
}
