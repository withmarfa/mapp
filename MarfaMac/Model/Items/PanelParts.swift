import Foundation

/// A part of the panel beside an item's page, drawn as a pill. Marfa has a link named About, so Info is not About.
nonisolated enum PanelPart: String, CaseIterable, Sendable {
    case outline, links, info

    var title: String {
        switch self {
        case .outline: String(localized: "Outline")
        case .links: String(localized: "Links")
        case .info: String(localized: "Info")
        }
    }
}

/// The part of the panel each type last showed, so a person who stays on Links stays there for every item of the type.
/// Kept in the app's settings as one value (`PreferencesMap`), one row for each type.
nonisolated struct PanelParts: Equatable, Sendable {
    static let key = "panelParts"
    /// Each entry is stored text that could not be read, in the order it was found.
    static let setAsideKey = "panelPartsSetAside"

    /// What one type keeps. A member is optional so a copy saved before it existed still reads.
    struct Choice: Codable, Equatable, Sendable {
        var part: String?
    }

    private(set) var choices: [String: Choice]

    init(_ choices: [String: Choice] = [:]) {
        self.choices = choices.filter { $0.value.part != nil }
    }

    /// The part `type` last showed. A word this version does not know is no choice.
    func part(of type: TypeID) -> PanelPart? {
        choices[type.rawValue]?.part.flatMap(PanelPart.init(rawValue:))
    }

    mutating func choose(_ part: PanelPart, for type: TypeID) {
        choices[type.rawValue] = Choice(part: part.rawValue)
    }

    /// The part to show among those the item has: the one the type last showed, else the first.
    func shown(of type: TypeID, among available: [PanelPart]) -> PanelPart? {
        if let chosen = part(of: type), available.contains(chosen) { return chosen }
        return available.first
    }
}

/// The settings as `@AppStorage` keeps them: JSON with sorted keys, so the same choice is the same text.
nonisolated extension PanelParts: RawRepresentable {
    var rawValue: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(choices)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }

    init?(rawValue: String) {
        guard let choices = try? JSONDecoder().decode([String: Choice].self, from: Data(rawValue.utf8)) else { return nil }
        self.init(choices)
    }
}

/// The two facts the Outline works out from an item's text, which Marfa does not store on the item.
nonisolated struct PanelTextFacts: Equatable, Sendable {
    let words: Int
    /// Whole minutes at an adult's silent reading pace, never less than one for text that has words.
    let readingMinutes: Int

    static let wordsPerMinute = 238

    /// A word is a stretch between spaces that holds a letter or a digit, so the marks of Markdown count for nothing.
    static func count(_ text: String) -> PanelTextFacts {
        var words = 0
        for piece in text.split(whereSeparator: \.isWhitespace) where piece.contains(where: { $0.isLetter || $0.isNumber }) {
            words += 1
        }
        let minutes = words == 0 ? 0 : max(1, Int((Double(words) / Double(wordsPerMinute)).rounded()))
        return PanelTextFacts(words: words, readingMinutes: minutes)
    }
}

/// One item in a group of the panel's Links.
nonisolated struct PanelLink: Identifiable, Equatable, Sendable {
    let item: ItemID
    let title: String
    /// The icon of the item's type, an Iconify ID. A task is drawn with its status instead.
    let icon: String?
    let status: StatusGroup?
    /// When the item last changed, or the size of a file.
    let detail: String
    /// The item the panel is showing, drawn in semibold where a group lists it among its fellows.
    let isCurrent: Bool
    var id: ItemID { item }
}

/// A group of the panel's Links: what links to the item, and what it links to.
nonisolated struct PanelLinkGroup: Identifiable, Equatable, Sendable {
    enum Kind: String, Sendable {
        case inCollection, referencedBy, linksInText, excerpts, moreFromBook, thread, attachments
    }

    let kind: Kind
    let links: [PanelLink]
    var id: String { kind.rawValue }

    var title: String {
        switch kind {
        case .inCollection: String(localized: "In Collection")
        case .referencedBy: String(localized: "Referenced By")
        case .linksInText: String(localized: "Links in the Text")
        case .excerpts: String(localized: "Excerpts")
        case .moreFromBook: String(localized: "More From This Book")
        case .thread: String(localized: "Thread")
        case .attachments: String(localized: "Attachments")
        }
    }

    /// How many links show before the rest wait behind Show All: the board draws six of a book's excerpts.
    var shownFirst: Int { kind == .moreFromBook ? 6 : LinkLimit.limit }
}
