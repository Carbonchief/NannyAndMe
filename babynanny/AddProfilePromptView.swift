import SwiftUI

struct AddProfilePromptView: View {
    let analyticsSource: String
    let onCreate: (String) -> Void
    let onCancel: () -> Void

    @State private var name: String
    @FocusState private var isNameFieldFocused: Bool
    @Environment(\.dismiss) private var dismiss

    init(
        initialName: String = "",
        analyticsSource: String,
        onCreate: @escaping (String) -> Void,
        onCancel: @escaping () -> Void = {}
    ) {
        self.analyticsSource = analyticsSource
        self.onCreate = onCreate
        self.onCancel = onCancel
        _name = State(initialValue: initialName)
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
                    .postHogLabel("\(analyticsSource).nameField")
                    .onSubmit(handleCreate)
                }

                Spacer()

                Button(action: handleCreate) {
                    Text(L10n.Profiles.addPromptCreate)
                        .frame(maxWidth: .infinity)
                }
                .postHogLabel("\(analyticsSource).create")
                .phCaptureTap(
                    event: "\(analyticsSource)_create_profile_button",
                    properties: ["is_name_empty": trimmedName.isEmpty ? "true" : "false"]
                )
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
                    .postHogLabel("\(analyticsSource).cancel")
                    .phCaptureTap(event: "\(analyticsSource)_cancel_button")
                }
            }
            .onAppear {
                isNameFieldFocused = true
            }
        }
        .interactiveDismissDisabled(false)
        .presentationDetents([.medium])
        .presentationDragIndicator(.hidden)
        .phScreen("\(analyticsSource)_addProfilePromptView")
    }

    private func handleCreate() {
        let value = trimmedName
        guard value.isEmpty == false else { return }
        Analytics.capture(
            "\(analyticsSource)_submit_profile_name",
            properties: ["name_length": "\(value.count)"]
        )
        onCreate(value)
        dismiss()
    }

    private func handleCancel() {
        Analytics.capture("\(analyticsSource)_cancel_add_profile")
        onCancel()
        dismiss()
    }
}

#Preview {
    AddProfilePromptView(analyticsSource: "preview") { _ in }
}
