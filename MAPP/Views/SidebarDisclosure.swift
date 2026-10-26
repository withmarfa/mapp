import SwiftUI

/// The chevron of a sidebar row that folds rows under it: pointing right when they are hidden, down when they show,
/// turning as they come and go. It fills one slot of a fixed width, so every row's chevron lands in one place.
///
/// A row that opens a list of its own (`isButton`) has this as a button of its own, since a click on the row selects.
/// A row that only folds is one button already, and this is its picture.
struct SidebarDisclosure: View {
    @Environment(\.interfaceTextSize) private var textSize
    let title: String
    let id: String
    let isExpanded: Bool
    let isButton: Bool
    let toggle: () -> Void

    var body: some View {
        if isButton {
            Button(action: toggle) { chevron }
                .buttonStyle(.plain)
                .accessibilityLabel(isExpanded ? Text("Collapse \(title)") : Text("Expand \(title)"))
                .accessibilityValue(isExpanded ? Text("Expanded") : Text("Collapsed"))
                .accessibilityIdentifier("SidebarDisclosure-\(id)")
        } else {
            chevron.accessibilityHidden(true)
        }
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .interfaceFont(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .rotationEffect(.degrees(isExpanded ? 90 : 0))
            .frame(width: 16 * InterfaceStyle.scale(for: textSize), height: 22 * InterfaceStyle.scale(for: textSize))
            .contentShape(.rect)
    }
}

#if DEBUG
#Preview("Sidebar Disclosure") {
    VStack {
        SidebarDisclosure(title: "Ticket", id: "aic.ticket", isExpanded: false, isButton: true) {}
        SidebarDisclosure(title: "Ticket", id: "aic.ticket", isExpanded: true, isButton: true) {}
    }
    .padding()
}
#endif
