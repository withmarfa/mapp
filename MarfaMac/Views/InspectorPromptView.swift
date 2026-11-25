import SwiftUI

/// What the right sidebar says when nothing is chosen: one quiet line in the middle, worded for what the place lists.
struct InspectorPromptView: View {
    let prompt: InspectorPrompt

    var body: some View {
        line
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("InspectorPrompt")
    }

    private var line: Text {
        switch prompt {
        case .item: Text("Choose an item to see its details.")
        case .collection: Text("Choose a collection to see what’s in it.")
        case .source: Text("Choose a source to see what it sends.")
        }
    }
}

/// The sidebar while the item chosen is still being read, as right after launch or during a sync. A system progress
/// indicator shows only once the read has taken `InspectorPrompt.progressDelay`, so a quick read shows nothing.
struct InspectorReadingView: View {
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
            try? await Task.sleep(for: InspectorPrompt.progressDelay)
            if !Task.isCancelled { isShown = true }
        }
    }
}
