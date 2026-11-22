import Foundation

/// What a timeline row says, as boards V5 and V6 draw it, made from the row's content: the title and, on its line at the
/// trailing edge, the chips with a person's initials last; then a second line of the type's name where the list mixes types
/// and the look's Secondary line. The type is no chip on the timeline, since its name leads the second line.
nonisolated struct TimelineRowFace: Hashable, Sendable {
    var title: String
    var chips: [RowContent.Chip]
    var more: Int
    /// The type's name where the list mixes types.
    var typeName: String?
    var secondary: String?

    init(_ content: RowContent) {
        title = content.title
        let others = content.chips.filter { if case .type = $0 { false } else { true } }
        func isPerson(_ chip: RowContent.Chip) -> Bool { if case .person = chip { true } else { false } }
        chips = others.filter { !isPerson($0) } + others.filter(isPerson)
        more = content.more
        typeName = content.mixesTypes ? content.typeLabel : nil
        secondary = content.secondary
    }

    /// Whether the second line has anything to say. A row without still keeps the line, so every row is one height.
    var hasSecondLine: Bool { typeName != nil || secondary != nil }
}
