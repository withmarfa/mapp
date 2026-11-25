import Foundation
import Marfa

/// What the new-item line reads in the words typed: a tag, a parent or a property being asked for, a pasted web
/// address, and a day. Pure, so every rule is tested with a locale and a time zone set.
nonisolated enum NewItemText {
    /// The character that starts each kind of word the line acts on.
    enum Mark: Character, Sendable {
        case tag = "#"
        case parent = "@"
        case property = "/"
    }

    /// A marked word being typed at the end of the text, and what follows its mark.
    struct Typing: Equatable, Sendable {
        let mark: Mark
        let query: String
        /// The text before the word, which stays when a match is chosen.
        let before: String
    }

    /// The marked word the text ends in, while it is being typed. A mark starts a word only at the start of the text
    /// or after a space, so `C#`, `and/or` and `a@b` are text. A tag's word starts with a letter, so `#12` is text.
    static func typing(in text: String) -> Typing? {
        guard let last = text.last, !last.isWhitespace else { return nil }
        let start = text.lastIndex(where: \.isWhitespace).map(text.index(after:)) ?? text.startIndex
        let word = text[start...]
        guard let first = word.first, let mark = Mark(rawValue: first) else { return nil }
        let query = String(word.dropFirst())
        if mark == .tag, let lead = query.first, !lead.isLetter { return nil }
        return Typing(mark: mark, query: query, before: String(text[..<start]))
    }

    // MARK: Tags

    /// Takes the finished tags out of the text, in the order typed, and gives the text without them. A tag is `#`
    /// at the start of the text or after a space, then a letter, then letters, digits, `-`, `_`, `/` or `.`; it is
    /// finished by the space after it, or by `finishing` (Add) at the end of the text. A full stop that ends it is
    /// the sentence's, not the tag's. `Issue #12`, `C#` and `#1st` stay text, as does any word the library would
    /// refuse as a tag (`refuses`).
    static func takeTags(from text: String, finishing: Bool, refuses: (String) -> Bool = { _ in false }) -> (tags: [String], text: String) {
        var tags: [String] = []
        var kept = ""
        var index = text.startIndex
        while index < text.endIndex {
            let atWordStart = index == text.startIndex || text[text.index(before: index)].isWhitespace
            guard atWordStart, text[index] == "#" else {
                kept.append(text[index])
                index = text.index(after: index)
                continue
            }
            let wordStart = text.index(after: index)
            let wordEnd = text[wordStart...].firstIndex(where: \.isWhitespace) ?? text.endIndex
            var word = String(text[wordStart..<wordEnd])
            while word.hasSuffix(".") { word.removeLast() }
            let ended = wordEnd < text.endIndex || finishing
            if ended, Self.isTag(word), !refuses(word) {
                if !tags.contains(word) { tags.append(word) }
                // The space after the tag goes with it, so no double space is left.
                index = wordEnd < text.endIndex ? text.index(after: wordEnd) : wordEnd
                if text[wordStart..<wordEnd].hasSuffix(".") {
                    while kept.last == " " { kept.removeLast() }
                    kept.append(".")
                    if wordEnd < text.endIndex { kept.append(" ") }
                }
            } else {
                kept += text[index..<wordEnd]
                index = wordEnd
            }
        }
        return (tags, kept)
    }

    private static func isTag(_ word: String) -> Bool {
        guard let first = word.first, first.isLetter else { return false }
        return word.allSatisfy { $0.isLetter || $0.isNumber || "-_/.".contains($0) } && ItemTag.refusal(of: word) == nil
    }

    // MARK: Web addresses

    /// The web address the text is, whole: `http` or `https` with a host, as a paste gives it.
    static func webAddress(_ text: String) -> URL? {
        let typed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.contains(where: \.isWhitespace), let url = URL(string: typed),
              let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme), url.host() != nil
        else { return nil }
        return url
    }

    // MARK: Days

    /// A day found in the words, and the words that named it.
    struct FoundDay: Equatable, Sendable {
        /// The words as typed, which leave the title when the item is added.
        let phrase: String
        let date: Date
        let hasTime: Bool
    }

    /// The first day the text names, in `locale`'s words and order, in `calendar`'s time zone; nil where it names
    /// none. In order: a numeric day ordered as the locale writes one (`27/11` in Britain, `11/27` in the United
    /// States), then the locale's month and weekday names (`Fri 27 Nov`, `27 November`, `Friday`), each with an
    /// optional time (`14:00`, `2pm`); then the system's date reader for words such as `tomorrow`. A day with no year
    /// is the next one from `now`. A month name alone, such as `May`, names no day.
    static func day(in text: String, now: Date, calendar: Calendar, locale: Locale) -> FoundDay? {
        var calendar = calendar
        calendar.locale = locale
        let words = Self.words(of: text)
        for start in words.indices {
            if let found = numericDay(words, from: start, in: text, now: now, calendar: calendar, locale: locale)
                ?? namedDay(words, from: start, in: text, now: now, calendar: calendar) {
                return found
            }
        }
        return detectedDay(in: text, calendar: calendar)
    }

    /// The text with the words that named a day taken out, and the spaces around them made one.
    static func removing(_ phrase: String, from text: String) -> String {
        guard let range = text.range(of: phrase) else { return text }
        var kept = text
        kept.replaceSubrange(range, with: " ")
        return kept.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// The value a day is written as in `field`: an instant where the field and the words hold a time, else the day.
    static func value(of day: FoundDay, in field: ItemTypeInfo.Field, calendar: Calendar) -> PropertyValue {
        if case .date(includesTime: true) = field.kind, day.hasTime { return .string(ItemDate.instant(day.date)) }
        return .string(ItemDate.day(day.date, calendar: calendar))
    }

    private struct Word {
        let text: String
        let range: Range<String.Index>
        /// Lowercased, without diacritics and without a full stop or comma after it, as the locale's names are compared.
        let folded: String
    }

    private static func words(of text: String) -> [Word] {
        var words: [Word] = []
        var index = text.startIndex
        while index < text.endIndex {
            guard !text[index].isWhitespace else {
                index = text.index(after: index)
                continue
            }
            let end = text[index...].firstIndex(where: \.isWhitespace) ?? text.endIndex
            var trimmedEnd = end
            while trimmedEnd > index, ",;".contains(text[text.index(before: trimmedEnd)]) { trimmedEnd = text.index(before: trimmedEnd) }
            let word = String(text[index..<trimmedEnd])
            if !word.isEmpty { words.append(Word(text: word, range: index..<trimmedEnd, folded: fold(word))) }
            index = end
        }
        return words
    }

    private static func fold(_ text: String) -> String {
        var folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        while folded.hasSuffix(".") { folded.removeLast() }
        return folded
    }

    /// `27/11`, `27/11/26` or `27/11/2026`, read in the order `locale` writes a day and a month. A slash is always
    /// taken, and the locale's own separator besides, such as the dot in Germany.
    private static func numericDay(_ words: [Word], from start: Int, in text: String, now: Date, calendar: Calendar, locale: Locale) -> FoundDay? {
        let pattern = DateFormatter.dateFormat(fromTemplate: "dM", options: 0, locale: locale) ?? "d/M"
        let dayFirst = (pattern.firstIndex(of: "d") ?? pattern.startIndex) < (pattern.firstIndex(of: "M") ?? pattern.endIndex)
        let separators = Set(["/"] + pattern.filter { !$0.isLetter && !$0.isWhitespace && $0 != "'" }.map(String.init))
        var word = words[start].text
        if let last = word.last, separators.contains(String(last)), last != "/" { word.removeLast() }
        let parts = word.split(omittingEmptySubsequences: false) { separators.contains(String($0)) }
        guard (2...3).contains(parts.count), parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) }),
              parts[0].count <= 2, parts[1].count <= 2,
              let first = Int(parts[0]), let second = Int(parts[1])
        else { return nil }
        let (day, month) = dayFirst ? (first, second) : (second, first)
        var year: Int?
        if parts.count == 3 {
            guard [2, 4].contains(parts[2].count), let typed = Int(parts[2]) else { return nil }
            year = parts[2].count == 2 ? 2000 + typed : typed
        }
        return found(day: day, month: month, year: year, words: words, span: start...start, in: text, now: now, calendar: calendar)
    }

    /// The locale's names: a weekday, a day and a month in either order, with a year after them, or a weekday alone.
    private static func namedDay(_ words: [Word], from start: Int, in text: String, now: Date, calendar: Calendar) -> FoundDay? {
        var index = start
        let weekday = weekdayNumber(words[index], calendar: calendar, alone: false)
        if weekday != nil { index += 1 }
        var day: Int?
        var month: Int?
        if index < words.count, let number = dayNumber(words[index]), index + 1 < words.count, let named = monthNumber(words[index + 1], calendar: calendar) {
            (day, month) = (number, named)
            index += 2
        } else if index < words.count, let named = monthNumber(words[index], calendar: calendar), index + 1 < words.count, let number = dayNumber(words[index + 1]) {
            (day, month) = (number, named)
            index += 2
        }
        if let day, let month {
            var year: Int?
            if index < words.count, words[index].text.count == 4, let typed = Int(words[index].folded) {
                year = typed
                index += 1
            }
            return found(day: day, month: month, year: year, words: words, span: start...(index - 1), in: text, now: now, calendar: calendar)
        }
        guard weekdayNumber(words[start], calendar: calendar, alone: true) != nil, let weekday else { return nil }
        let today = calendar.startOfDay(for: now)
        guard let date = calendar.nextDate(after: today, matching: DateComponents(weekday: weekday), matchingPolicy: .nextTime, direction: .forward)
        else { return nil }
        let next = calendar.component(.weekday, from: today) == weekday ? today : date
        return timed(next, words: words, span: start...start, in: text, calendar: calendar)
    }

    private static func found(
        day: Int, month: Int, year: Int?, words: [Word], span: ClosedRange<Int>, in text: String, now: Date, calendar: Calendar
    ) -> FoundDay? {
        guard (1...12).contains(month), (1...31).contains(day) else { return nil }
        let today = calendar.startOfDay(for: now)
        var parts = DateComponents(year: year ?? calendar.component(.year, from: today), month: month, day: day)
        guard var date = calendar.date(from: parts), calendar.component(.day, from: date) == day else { return nil }
        if year == nil, date < today {
            parts.year = (parts.year ?? 0) + 1
            guard let next = calendar.date(from: parts) else { return nil }
            date = next
        }
        return timed(date, words: words, span: span, in: text, calendar: calendar)
    }

    /// The day with a time that follows its words, as `14:00`, `2pm` or `2 pm`. A bare number is not a time, since
    /// `Fri 27 Nov 3 copies` names no hour.
    private static func timed(_ day: Date, words: [Word], span: ClosedRange<Int>, in text: String, calendar: Calendar) -> FoundDay {
        let next = span.upperBound + 1
        func phrase(to last: Int) -> String { String(text[words[span.lowerBound].range.lowerBound..<words[last].range.upperBound]) }
        for length in [2, 1] where next + length - 1 < words.count {
            let typed = words[next...(next + length - 1)].map(\.text).joined(separator: " ")
            guard typed.contains(where: { ":.".contains($0) }) || typed.lowercased().hasSuffix("m"),
                  let time = TimeOfDay.parse(typed),
                  let moment = TimeOfDay.moment(hour: time.hour, minute: time.minute, on: day, calendar: calendar)
            else { continue }
            return FoundDay(phrase: phrase(to: next + length - 1), date: moment, hasTime: true)
        }
        return FoundDay(phrase: phrase(to: span.upperBound), date: day, hasTime: false)
    }

    private static func dayNumber(_ word: Word) -> Int? {
        let digits = word.folded.prefix { $0.isASCII && $0.isNumber }
        let rest = word.folded.dropFirst(digits.count)
        guard (1...2).contains(digits.count), rest.isEmpty || ["st", "nd", "rd", "th", "er", "e"].contains(String(rest)) else { return nil }
        return Int(digits)
    }

    private static func monthNumber(_ word: Word, calendar: Calendar) -> Int? {
        let names = [calendar.monthSymbols, calendar.shortMonthSymbols, calendar.standaloneMonthSymbols, calendar.shortStandaloneMonthSymbols]
        for list in names {
            if let index = list.firstIndex(where: { fold($0) == word.folded }) { return index + 1 }
        }
        return nil
    }

    /// A weekday by its name. Standing alone, a short name counts only as the locale writes it, so `sat` in a
    /// sentence is not Saturday but `Sat` is.
    private static func weekdayNumber(_ word: Word, calendar: Calendar, alone: Bool) -> Int? {
        if let index = calendar.weekdaySymbols.firstIndex(where: { fold($0) == word.folded }) { return index + 1 }
        let short = calendar.shortWeekdaySymbols
        if alone {
            return short.firstIndex { $0 == word.text || $0 + "." == word.text }.map { $0 + 1 }
        }
        return short.firstIndex { fold($0) == word.folded }.map { $0 + 1 }
    }

    /// The system's date reader, for words such as `tomorrow` or `next Tuesday`. It reads digits in an order of its
    /// own, so a match with a numeric day in it is passed over: those are read above, in the locale's order.
    private static func detectedDay(in text: String, calendar: Calendar) -> FoundDay? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else { return nil }
        let whole = NSRange(text.startIndex..., in: text)
        guard let match = detector.firstMatch(in: text, options: [], range: whole), let date = match.date,
              let range = Range(match.range, in: text)
        else { return nil }
        let phrase = String(text[range])
        guard phrase.contains(where: \.isLetter), phrase.wholeMatch(of: /.*\d+\s*[\/.\-]\s*\d+.*/) == nil else { return nil }
        let hasTime = phrase.firstMatch(of: /\d{1,2}(?::\d{2})?\s*(?:[ap]\.?m\.?)|\d{1,2}:\d{2}/.ignoresCase()) != nil
        // The reader places the moment in the system's zone; the day and clock time are what the words named.
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let day = DateComponents(year: parts.year, month: parts.month, day: parts.day)
        guard let start = calendar.date(from: day) else { return nil }
        if hasTime, let hour = parts.hour, let minute = parts.minute,
           let moment = TimeOfDay.moment(hour: hour, minute: minute, on: start, calendar: calendar) {
            return FoundDay(phrase: phrase, date: moment, hasTime: true)
        }
        return FoundDay(phrase: phrase, date: calendar.startOfDay(for: start), hasTime: false)
    }
}
