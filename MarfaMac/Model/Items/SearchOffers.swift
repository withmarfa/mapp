import Foundation

extension Tier {
    /// The word a filter holds the tier as, which is also what Marfa's `tier` field says.
    nonisolated var word: String {
        switch self {
        case .library: "library"
        case .feed: "feed"
        }
    }

    nonisolated init?(word: String) {
        switch word {
        case "library": self = .library
        case "feed": self = .feed
        default: return nil
        }
    }

    nonisolated var title: String {
        switch self {
        case .library: String(localized: "Library")
        case .feed: String(localized: "Feed")
        }
    }
}

/// One thing the list's search offers under its field while text is typed: a token it can make from what was typed, or the
/// text itself as the search.
nonisolated struct SearchOffer: Identifiable, Hashable, Sendable {
    nonisolated enum Kind: Hashable, Sendable {
        /// A filter on a field, which Return makes a token of.
        case token(FilterClause)
        /// The typed words as the text search.
        case text
    }

    let id: String
    let kind: Kind
    /// What it filters on: "Status". Empty for the text search.
    let field: String
    /// What it says after the field: "Not Started", or the words typed.
    let value: String
    /// The symbol of the field's kind.
    let symbol: String

    /// The row as it reads and as VoiceOver reads it: "Status Not Started", "Search for “zine”".
    var title: String {
        switch kind {
        case .token: [field, value].filter { !$0.isEmpty }.joined(separator: " ")
        case .text: String(localized: "Search for “\(value)”")
        }
    }

    var clause: FilterClause? {
        if case .token(let clause) = kind { clause } else { nil }
    }
}

/// What the list's search offers for the words typed in it: the fields and values that match, then a date where the words
/// name one, then the words as a text search. The fields are the place's own (`FilterOffer`), and each offer is one clause of
/// the filter model, so a token is worked out as a filter is (`FilterMatching`, `ViewDraft`).
nonisolated enum SearchOffers {
    /// One value a field can take, by the identifier a clause holds and the words a person says it by.
    struct Option: Hashable, Sendable {
        var id: String
        var title: String
    }

    /// What the library holds that a field's values come from.
    struct Values: Sendable {
        var types: [Option] = []
        var sources: [Option] = []
        var tags: [String] = []
        var collections: [Option] = []
    }

    /// Everything an offer is worked out from, so it needs no library and its test no machine.
    struct Context: Sendable {
        /// The fields offered, in order: the place's own, then what every item has.
        var targets: [FilterTarget]
        var values = Values()
        /// Whether the place lists several types, which puts a status's groups beside its words.
        var hasSeveralTypes = false
        var calendar: Calendar = .current
        var now = Date.now
    }

    /// The most token offers under the field, so the list stays a menu and not a page.
    static let limit = 7
    /// The most values one field offers for a match on the field's name alone.
    private static let perField = 3

    static func make(text: String, in context: Context, existing: [FilterClause] = []) -> [SearchOffer] {
        let typed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty else { return [] }
        let query = folded(typed)
        var offers: [SearchOffer] = []
        var seen = Set(existing)
        func add(_ target: FilterTarget, _ clause: FilterClause, value: String) {
            guard offers.count < limit, seen.insert(clause).inserted else { return }
            offers.append(SearchOffer(
                id: "\(clause.field)|\(clause.op.rawValue)|\(clause.values.joined(separator: ","))", kind: .token(clause),
                field: target.label, value: value, symbol: symbol(of: target.kind)))
        }

        let named = context.targets.filter { target in
            let label = folded(target.label)
            return query == label || query.hasPrefix(label + " ")
        }.max { $0.label.count < $1.label.count }
        let rest = named.map { String(query.dropFirst(folded($0.label).count)).trimmingCharacters(in: .whitespaces) }

        // A field named in full gives its values first, narrowed by the words after the name.
        if let named, let rest {
            for option in matches(of: rest, in: options(of: named, context), allowingAll: true, limit: nil) {
                add(named, clause(for: named, option), value: option.title)
            }
        }
        // Then every field's values that the words match.
        var fieldsMatched: [FilterTarget] = []
        for target in context.targets where target.id != named?.id {
            let label = folded(target.label)
            let all = options(of: target, context)
            let byValue = matches(of: query, in: all, allowingAll: false, limit: nil)
            if !byValue.isEmpty {
                for option in byValue { add(target, clause(for: target, option), value: option.title) }
            } else if label.hasPrefix(query) {
                fieldsMatched.append(target)
            }
        }
        // A field whose name the words begin gives a few of its values, after those the words name themselves.
        for target in fieldsMatched {
            for option in options(of: target, context).prefix(perField) { add(target, clause(for: target, option), value: option.title) }
        }

        for offer in dates(of: typed, named: named, in: context) where offers.count < limit {
            if let clause = offer.clause, seen.insert(clause).inserted { offers.append(offer) }
        }
        offers.append(SearchOffer(id: "text", kind: .text, field: "", value: typed, symbol: "magnifyingglass"))
        return offers
    }

    // MARK: Values

    private static func options(of target: FilterTarget, _ context: Context) -> [Option] {
        switch target.kind {
        case .status:
            var options: [Option] = []
            if context.hasSeveralTypes {
                options += StatusGroup.allCases.map { Option(id: FilterClause.groupValue($0), title: StatusBucket.group($0).title) }
            }
            return options + target.declared.filter { !$0.isEmpty }.map { Option(id: $0, title: ItemTypeInfo.Field.label(ofOption: $0)) }
        case .choice:
            return target.declared.filter { !$0.isEmpty }.map { Option(id: $0, title: ItemTypeInfo.Field.label(ofOption: $0)) }
        case .boolean:
            return [Option(id: "true", title: String(localized: "Yes")), Option(id: "false", title: String(localized: "No"))]
        case .type: return context.values.types
        case .collection: return context.values.collections
        case .tags: return context.values.tags.map { Option(id: $0, title: $0) }
        case .source:
            if target.isTier { return Tier.allCases.reversed().map { Option(id: $0.word, title: $0.title) } }
            return context.values.sources
        default: return []
        }
    }

    private static func clause(for target: FilterTarget, _ option: Option) -> FilterClause {
        FilterClause(field: target.id, op: target.kind.startingOperator, values: [option.id])
    }

    /// The options whose words the typed words begin, then those that hold them at the start of a word, then anywhere.
    private static func matches(of query: String, in options: [Option], allowingAll: Bool, limit: Int?) -> [Option] {
        if query.isEmpty { return allowingAll ? options : [] }
        let words = options.map { ($0, folded($0.title)) }
        let prefix = words.filter { $0.1.hasPrefix(query) }
        let atWord = words.filter { !$0.1.hasPrefix(query) && $0.1.split(separator: " ").contains { $0.hasPrefix(query) } }
        let inside = words.filter { entry in !prefix.contains { $0.0 == entry.0 } && !atWord.contains { $0.0 == entry.0 } && entry.1.contains(query) }
        let found = (prefix + atWord + inside).map(\.0)
        return limit.map { Array(found.prefix($0)) } ?? found
    }

    static func folded(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    private static func symbol(of kind: FilterKind) -> String {
        switch kind {
        case .status: "circle.dashed"
        case .choice: "list.bullet"
        case .boolean: "checkmark.circle"
        case .date, .moment: "calendar"
        case .tags: "tag"
        case .type: "square.grid.2x2"
        case .collection: "rectangle.stack"
        case .source: "antenna.radiowaves.left.and.right"
        default: "line.3.horizontal.decrease"
        }
    }

    // MARK: Dates

    /// A date field's word for how a day is asked about: before, after or on it.
    private static var dateOps: [(op: FilterOp, word: String)] {
        [(.before, String(localized: "before", comment: "Typed in the list's search: a date field is before a day")),
         (.after, String(localized: "after", comment: "Typed in the list's search: a date field is after a day")),
         (.on, String(localized: "on", comment: "Typed in the list's search: a date field is on a day"))]
    }

    /// The offers a day or a month typed in the words makes, on the date field named or else the first two the place has.
    private static func dates(of typed: String, named: FilterTarget?, in context: Context) -> [SearchOffer] {
        var words = typed
        if let named {
            // The field's name leads: drop it, with the same fold the match used.
            let label = folded(named.label)
            if let range = words.range(of: label, options: [.caseInsensitive, .diacriticInsensitive, .anchored]) { words.removeSubrange(range) }
        }
        words = words.trimmingCharacters(in: .whitespaces)
        var chosen: FilterOp?
        for entry in dateOps {
            let lead = folded(entry.word)
            let hold = folded(words)
            if hold.hasPrefix(lead + " ") {
                chosen = entry.op
                words = String(words.dropFirst(lead.count)).trimmingCharacters(in: .whitespaces)
                break
            }
        }
        guard let span = SearchDates.parse(words, calendar: context.calendar, now: context.now) else { return [] }
        let fields = named.map { [$0] } ?? Array(context.targets.filter { $0.kind.isDated }.prefix(2))
        guard !fields.isEmpty, fields.allSatisfy({ $0.kind.isDated }) else { return [] }
        let calendar = context.calendar
        var offers: [SearchOffer] = []
        for target in fields {
            let first = FilterDays.text(of: span.start, calendar: calendar)
            let last = FilterDays.text(of: span.end, calendar: calendar)
            let clause: FilterClause = switch chosen ?? .on {
            case .before: FilterClause(field: target.id, op: .before, values: [first])
            case .after: FilterClause(field: target.id, op: .after, values: [last])
            default: first == last
                ? FilterClause(field: target.id, op: .on, values: [first])
                : FilterClause(field: target.id, op: .between, values: [first, last])
            }
            let parts = FilterWording.parts(of: clause, target: target, calendar: calendar)
            offers.append(SearchOffer(
                id: "\(clause.field)|\(clause.op.rawValue)|\(clause.values.joined(separator: ","))", kind: .token(clause), field: target.label,
                value: [parts.relation, parts.values].joined(separator: " "), symbol: symbol(of: target.kind)))
        }
        return offers
    }
}

/// A day, or a run of days such as a month, typed in the words of the person's own locale and calendar.
nonisolated enum SearchDates {
    struct Span: Hashable, Sendable {
        var start: Date
        var end: Date
    }

    /// The templates a day or a month is written by, from the fullest to the barest. A template is put in order and
    /// punctuated by the locale (`DateFormatter.dateFormat(fromTemplate:options:locale:)`), so "30 Nov 2026" and
    /// "11/30/2026" each read in the locale that writes them so.
    private static let dayTemplates = ["yMMMMd", "yMMMd", "yMd", "yyMd", "MMMMd", "MMMd", "Md"]
    private static let monthTemplates = ["yMMMM", "yMMM", "MMMM", "MMM"]

    /// Reads `text` as a day or a month, or nil where it is neither. A date without a year is of the year `now` falls in.
    static func parse(_ text: String, calendar: Calendar, now: Date) -> Span? {
        let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty, words.count <= 40, words.contains(where: \.isNumber) || words.contains(where: \.isLetter) else { return nil }
        let locale = calendar.locale ?? .current
        for template in dayTemplates {
            if let day = read(words, template: template, calendar: calendar, locale: locale, now: now) {
                return Span(start: day, end: day)
            }
        }
        for template in monthTemplates {
            guard let first = read(words, template: template, calendar: calendar, locale: locale, now: now),
                  let range = calendar.range(of: .day, in: .month, for: first),
                  let last = calendar.date(byAdding: .day, value: range.count - 1, to: first) else { continue }
            return Span(start: first, end: last)
        }
        return nil
    }

    private static func read(_ text: String, template: String, calendar: Calendar, locale: Locale, now: Date) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.timeZone = calendar.timeZone
        formatter.isLenient = false
        formatter.dateFormat = DateFormatter.dateFormat(fromTemplate: template, options: 0, locale: locale)
        guard let format = formatter.dateFormat, let date = formatter.date(from: text) else { return nil }
        // A format with no year reads as the reference year, so it is moved into the year of `now`.
        let hasYear = format.contains("y") || format.contains("Y")
        var parts = calendar.dateComponents([.year, .month, .day], from: date)
        if !hasYear { parts.year = calendar.component(.year, from: now) }
        if !format.contains("d") { parts.day = 1 }
        guard let result = calendar.date(from: parts), calendar.component(.month, from: result) == parts.month else { return nil }
        return calendar.startOfDay(for: result)
    }
}

nonisolated extension FilterWording {
    /// A token as its chip says it: the field, the relation unless it is the field's usual one (a tag is simply there, a type
    /// simply is), and the values.
    static func tokenParts(of clause: FilterClause, target: FilterTarget, calendar: Calendar, titles: (String) -> String?) -> Parts {
        var parts = parts(of: clause, target: target, calendar: calendar, titles: titles)
        if clause.op == target.kind.startingOperator || (clause.op == .includes && target.kind == .tags) { parts.relation = "" }
        return parts
    }
}

extension ItemLibrary {
    /// The values a token can name here: the types, the sources, the tags and the collections.
    var searchOfferValues: SearchOffers.Values {
        var values = SearchOffers.Values()
        values.types = itemTypeCounts.map { SearchOffers.Option(id: $0.id.rawValue, title: $0.label) }
        values.sources = sources.infos.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            .map { SearchOffers.Option(id: $0.code, title: $0.name) }
        values.tags = knownTags
        values.collections = collections.map { SearchOffers.Option(id: $0.id.rawValue, title: $0.displayTitle) }
        return values
    }

    /// The name a token's value goes by where it is an identifier: a type's, or a collection's title.
    func title(ofValue id: String) -> String? {
        if let type = itemTypeCounts.first(where: { $0.id.rawValue == id }) { return type.label }
        return item(ItemID(rawValue: id))?.displayTitle
    }
}
