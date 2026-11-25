import SwiftUI

/// What the right sidebar shows while the chosen item is still being read: nothing, then a progress indicator once the
/// read has taken `delay`, so a read that ends at once shows none.
struct InspectorReadingView: View {
    private static let delay = Duration.milliseconds(500)
    @State private var isShown = false

    var body: some View {
        Group {
            if isShown {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Reading Item")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            try? await Task.sleep(for: Self.delay)
            if !Task.isCancelled { isShown = true }
        }
    }
}
