import SwiftUI

/// A sheet prompting the user to name the initial child profile on first launch.
struct InitialProfileNamePromptView: View {
    let onContinue: (String) -> Void
    let allowsDismissal: Bool

    @State private var name: String
    @FocusState private var isNameFieldFocused: Bool

    init(initialName: String, allowsDismissal: Bool, onContinue: @escaping (String) -> Void) {
        self.onContinue = onContinue
        self.allowsDismissal = allowsDismissal
        _name = State(initialValue: initialName)
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
            properties: ["name_length": "\(value.count)"]
        )
        onContinue(value)
    }
}

#Preview {
    InitialProfileNamePromptView(initialName: "", allowsDismissal: true) { _ in }
}
