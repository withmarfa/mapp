import SwiftUI

/// The calendar's No Date pill: how many items have no date to stand on, with a list that opens one. It sits at the foot of
/// the calendar, in the middle where there is room beside the corner and at the leading edge where there is not.
struct CalendarNoDatePill: View {
    @CurrentLibrary private var library
    let ids: [ItemID]
    let open: (ItemID) -> Void
    @State private var isOpen = false

    var body: some View {
        Button { isOpen.toggle() } label: {
            HStack(spacing: 6) {
                Image(systemName: "list.bullet")
                Text("No Date")
                Text(ids.count, format: .number).foregroundStyle(.secondary).monospacedDigit()
            }
        }
        .buttonStyle(CornerButtonStyle(isOn: isOpen))
        .popover(isPresented: $isOpen, arrowEdge: .top) { list }
        .accessibilityLabel("No Date, \(ids.count)")
        .accessibilityIdentifier("CalendarNoDate")
    }

    /// Built lazily, so a place with thousands of undated items draws only those in view.
    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(ids, id: \.self) { id in
                    Button {
                        isOpen = false
                        open(id)
                    } label: {
                        Text(verbatim: library.item(id)?.displayTitle ?? "")
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 6)
        }
        .frame(width: 280, height: min(CGFloat(ids.count) * 28 + 12, 320))
    }
}

/// The note under a week that hides its weekend, for the items that fall only on it. It opens the month, which keeps
/// the weekend.
struct CalendarWeekendNote: View {
    let count: Int
    let showMonth: () -> Void

    var body: some View {
        Button(action: showMonth) {
            Text("\(count) on the weekend")
        }
        .buttonStyle(CornerButtonStyle())
        .help("Show the Month")
        .accessibilityIdentifier("CalendarWeekendNote")
    }
}
