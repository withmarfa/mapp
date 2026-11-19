import SwiftUI

/// The Recently Deleted page of Settings, the only place that lists what the library holds in its bin: Restore, Delete
/// Permanently and Empty, which `RecentlyDeletedActions` supplies.
struct RecentlyDeletedSettings: View {
    @Environment(\.library) private var library
    @AppStorage(DateFormat.key) private var dateFormat = DateFormat.standard
    @State private var selection: Set<ItemID> = []

    var body: some View {
        if let library {
            let items = library.deletedItems
            VStack(alignment: .leading, spacing: 0) {
                if items.isEmpty {
                    Text("Nothing is in Recently Deleted.")
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 30)
                        .padding(.vertical, 16)
                } else {
                    List(items, selection: $selection) { item in
                        HStack {
                            Text(item.displayTitle).lineLimit(1)
                            Spacer(minLength: 8)
                            Text(DateDisplay.text(of: item.modified, hasTime: false, place: .value, format: dateFormat))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .softSelection(rows: items.map(\.id), hovers: true) { selection }
                    .frame(minHeight: 320)
                    .padding(.horizontal, 18)
                }
                RecentlyDeletedActions(chosen: items.filter { selection.contains($0.id) })
            }
            .onChange(of: items.map(\.id)) { selection.formIntersection(items.map(\.id)) }
            .accessibilityIdentifier("RecentlyDeletedSettings")
        } else {
            Text("Open a library to see what was deleted from it.")
                .foregroundStyle(.secondary)
                .padding(.horizontal, 30)
                .padding(.vertical, 16)
        }
    }
}
