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
    }

    private func handleContinue() {
        let value = trimmedName
        guard value.isEmpty == false else { return }
        onContinue(value)
    }
}

#Preview {
    InitialProfileNamePromptView(initialName: "", allowsDismissal: true) { _ in }
}
