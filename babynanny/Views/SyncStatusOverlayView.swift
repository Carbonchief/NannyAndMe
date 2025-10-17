import SwiftUI

struct SyncStatusOverlayView: View {
    let state: SyncStatusViewModel.State
    let lastError: String?

    var body: some View {
        VStack(spacing: 16) {
            switch state {
            case .idle, .waiting:
                ProgressView(L10n.Sync.loadingInitialData)
                    .progressViewStyle(.circular)
                    .tint(.accentColor)
                    .font(.headline)
            case .importing(let progress):
                VStack(spacing: 12) {
                    ProgressView(value: progress ?? 0.0, total: 1.0) {
                        Text(L10n.Sync.loadingInitialData)
                            .font(.headline)
                    }
                    .progressViewStyle(.linear)
                    .tint(.accentColor)
                    if let progress {
                        Text(L10n.Sync.progressPercentage(progress * 100))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            case .exporting:
                ProgressView(L10n.Sync.preparingUpdates)
                    .progressViewStyle(.circular)
                    .tint(.accentColor)
                    .font(.headline)
            case .failed:
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(Color.orange)
                    Text(L10n.Sync.initialSyncFailed)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                    if let message = lastError, message.isEmpty == false {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
            case .finished:
                EmptyView()
            }
        }
        .padding(32)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.2).ignoresSafeArea())
    }
}

#Preview {
    SyncStatusOverlayView(state: .importing(progress: 0.4), lastError: nil)
}
