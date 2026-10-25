import SwiftUI

/// What a view says when it has nothing to show: a short title and at most one short line, with no icon.
struct EmptyState<Actions: View>: View {
    let title: Text
    var detail: Text?
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(spacing: 6) {
            title
                .font(.title2.weight(.semibold))
                .foregroundStyle(.secondary)
            if let detail {
                detail
                    .foregroundStyle(.secondary)
            }
            actions
        }
        .multilineTextAlignment(.center)
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
    }
}

extension EmptyState where Actions == EmptyView {
    init(_ title: LocalizedStringKey, detail: LocalizedStringKey? = nil) {
        self.init(title: Text(title), detail: detail.map { Text($0) }, actions: { EmptyView() })
    }

    /// The answer to a search with no results.
    static func search(_ text: String) -> EmptyState {
        EmptyState(title: Text("No Results"), detail: Text("Nothing matches “\(text)”."), actions: { EmptyView() })
    }
}
