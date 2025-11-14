import SwiftUI
import PhotosUI
import UIKit

@MainActor
struct AddProfilePromptView: View {
    let onCreate: (String, Date, Data?) -> Void
    let onCancel: () -> Void

    @State private var name: String
    @State private var birthDate: Date
    @State private var imageData: Data?
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var pendingCrop: PendingCropImage?
    @State private var isProcessingPhoto = false
    @State private var photoLoadingTask: Task<Void, Never>?
    @State private var activePhotoRequestID: UUID?
    @FocusState private var isNameFieldFocused: Bool

    @Environment(\.dismiss) private var dismiss

    init(
        initialName: String = "",
        initialImageData: Data? = nil,
        initialBirthDate: Date = Date(),
        onCreate: @escaping (String, Date, Data?) -> Void,
        onCancel: @escaping () -> Void = {}
    ) {
        self.onCreate = onCreate
        self.onCancel = onCancel
        _name = State(initialValue: initialName)
        _birthDate = State(initialValue: initialBirthDate)
        _imageData = State(initialValue: initialImageData)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.Profiles.addPromptTitle)
                        .font(.title2.bold())
                    Text(L10n.Profiles.addPromptSubtitle)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text(L10n.Profiles.addPromptNameLabel)
                        .font(.footnote)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)

                    TextField(
                        L10n.Profiles.addPromptNamePlaceholder,
                        text: $name
                    )
                    .textFieldStyle(.roundedBorder)
                    .focused($isNameFieldFocused)
                    .submitLabel(.done)
                    .onSubmit(handleCreate)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text(L10n.Profiles.choosePhoto)
                        .font(.footnote)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)

                    HStack(alignment: .center, spacing: 16) {
                        profilePhotoSelector

                        VStack(alignment: .leading, spacing: 4) {
                            Text(L10n.Profiles.birthDate)
                                .font(.footnote)
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)

                            DatePicker(
                                L10n.Profiles.birthDate,
                                selection: $birthDate,
                                in: Date.distantPast...Date(),
                                displayedComponents: .date
                            )
                            .datePickerStyle(.compact)
                            .labelsHidden()
                        }
                    }

                    processingPhotoIndicator
                }

                Spacer()

                Button(action: handleCreate) {
                    Text(L10n.Profiles.addPromptCreate)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(trimmedName.isEmpty)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(.systemBackground))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L10n.Common.cancel) {
                        handleCancel()
                    }
                }
            }
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
        .interactiveDismissDisabled(false)
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

    private func handleCreate() {
        let value = trimmedName
        guard value.isEmpty == false else { return }
        onCreate(value, birthDate, imageData)
        dismiss()
    }

    private func handleCancel() {
        onCancel()
        dismiss()
    }

    @MainActor
    private var profilePhotoSelector: some View {
        let currentImageData = imageData
        let hasImage = currentImageData != nil

        let avatarPreview = ProfileAvatarView(imageData: currentImageData, size: 72)

        return ZStack(alignment: .bottomTrailing) {
            PhotosPicker(selection: $selectedPhoto, matching: .images, photoLibrary: .shared()) {
                avatarPreview
                    .overlay(alignment: .bottomTrailing) {
                        if hasImage == false {
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

            if hasImage {
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
    AddProfilePromptView { _, _, _ in }
}

private extension AddProfilePromptView {
    struct PendingCropImage: Identifiable {
        let id = UUID()
        let image: UIImage
    }
}
