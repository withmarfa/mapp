import SwiftUI

/// The row styles other than Standard. Each draws only the facts its item has, so a missing one leaves no gap. A row's
/// facts are made in `ListLineRow` from its item and what the list resolved once for its type (`ListRowType`); the
/// views here look nothing up.

/// One line: the type's mark, the title and the date.
struct CompactRow: View {
    let item: Item
    let dateLabel: String
    let typeIcon: String?

    var body: some View {
        HStack(spacing: 8) {
            TypeMark(icon: typeIcon)
            Text(item.displayTitle)
                .interfaceFont(.body)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(dateLabel)
                .interfaceFont(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .layoutPriority(1)
        }
    }
}

/// The status mark and title, then a line of the due date, priority, people and repeat.
struct TaskRow: View {
    let item: Item
    let task: TaskRowFacts
    let meta: ItemMeta

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            StatusMark(group: task.statusGroup, size: 14)
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 5 }
            VStack(alignment: .leading, spacing: 4) {
                Text(item.displayTitle)
                    .interfaceFont(.body.weight(.semibold))
                    .lineLimit(1)
                if task.hasLine || !meta.isEmpty {
                    HStack(spacing: 10) {
                        if let due = task.due { dueChip(due) }
                        if let finish = task.finish { Text(finish).foregroundStyle(.secondary) }
                        if let priority = task.priority {
                            PageChip(text: ItemTypeInfo.Field.label(ofOption: priority), kind: .option(task.priorityTone ?? .neutral), size: .row)
                        }
                        if let people = task.people {
                            PagePerson(name: people.label, initials: people.initials, size: .row)
                                .help(people.label)
                        }
                        if let repeats = task.repeats {
                            Label(repeats, systemImage: "repeat").foregroundStyle(.secondary)
                        }
                        if !meta.isEmpty { ItemMetaLine(meta: meta) }
                    }
                    .interfaceFont(.caption)
                    .lineLimit(1)
                }
            }
        }
    }

    private func dueChip(_ due: TaskRowFacts.Due) -> some View {
        Text(due.label)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .foregroundStyle(due.isPressing ? Color.red : Color.secondary)
            .background(
                (due.isPressing ? Color.red.opacity(0.14) : Color.secondary.opacity(0.14)),
                in: Capsule())
    }

}

/// The passage first, with a rule in the highlight's color, then its source and place and the date.
struct HighlightRow: View {
    let item: Item
    let facts: HighlightRowFacts
    let dateLabel: String
    let meta: ItemMeta

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Self.rule(facts.color))
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.preview.isEmpty ? item.displayTitle : item.preview)
                    .interfaceFont(.body)
                    .lineLimit(3)
                HStack(spacing: 8) {
                    if let line = facts.line {
                        Text(line).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    Text(dateLabel).lineLimit(1).layoutPriority(1)
                    if !meta.isEmpty { ItemMetaLine(meta: meta) }
                }
                .interfaceFont(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    /// Marfa's six highlight colors; any other is the accent.
    static func rule(_ name: String?) -> Color {
        switch name?.lowercased() {
        case "yellow": .yellow
        case "blue": .blue
        case "green": .green
        case "pink": .pink
        case "orange": .orange
        case "purple": .purple
        default: .accentColor
        }
    }
}

/// Initials in a circle, the name, one line saying who the person is, and the date.
struct PersonRow: View {
    let item: Item
    let facts: PersonRowFacts
    let dateLabel: String
    let meta: ItemMeta

    var body: some View {
        HStack(spacing: 10) {
            PersonCircle(initials: facts.initials, size: .row)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayTitle)
                    .interfaceFont(.body.weight(.semibold))
                    .lineLimit(1)
                if let line = facts.line {
                    Text(line)
                        .interfaceFont(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if !meta.isEmpty { ItemMetaLine(meta: meta) }
            }
            Spacer(minLength: 8)
            Text(dateLabel)
                .interfaceFont(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .layoutPriority(1)
        }
    }
}
