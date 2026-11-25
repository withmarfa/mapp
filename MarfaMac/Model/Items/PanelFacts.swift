import Foundation
import PDFKit
import UniformTypeIdentifiers

/// A fact of the panel: a small label over its value.
nonisolated struct PanelFact: Identifiable, Equatable, Sendable {
    let name: String
    let value: String
    var id: String { name }
}

/// A heading of a PDF's own contents and the page it goes to.
nonisolated struct PanelContentsRow: Identifiable, Equatable, Sendable {
    let level: Int
    let title: String
    /// From 1.
    let page: Int
    let index: Int
    var id: Int { index }
}

/// What a PDF holds that the Outline shows: how many pages, and the contents the file gives.
nonisolated struct PanelPDFFacts: Equatable, Sendable {
    let pages: Int
    let contents: [PanelContentsRow]

    /// The deepest contents level drawn, as the page's headings go to three.
    static let deepest = 3

    /// Read away from the main actor, since a long document takes a moment to open.
    static func read(_ url: URL) -> PanelPDFFacts? {
        guard let document = PDFDocument(url: url) else { return nil }
        var rows: [PanelContentsRow] = []
        func walk(_ outline: PDFOutline, level: Int) {
            for index in 0..<outline.numberOfChildren {
                guard let child = outline.child(at: index) else { continue }
                if let title = child.label?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty,
                   let page = child.destination?.page, level <= deepest {
                    rows.append(PanelContentsRow(level: level, title: title, page: document.index(for: page) + 1, index: rows.count))
                }
                walk(child, level: level + 1)
            }
        }
        if let root = document.outlineRoot { walk(root, level: 1) }
        return PanelPDFFacts(pages: document.pageCount, contents: rows)
    }
}

/// The facts Info lists for an item, in order: where it came from, its version and times, then the file's own.
nonisolated enum PanelInfo {
    /// `pages` is a PDF's page count once read. Dates read as `format` says, with their time (`stamp`).
    static func facts(of item: Item, source: String?, version: ItemVersion, pages: Int?, format: DateFormat) -> [PanelFact] {
        var facts: [PanelFact] = []
        if let source { facts.append(PanelFact(name: String(localized: "Source"), value: source)) }
        facts.append(PanelFact(name: String(localized: "Version"), value: version.rawValue.formatted()))
        facts.append(PanelFact(name: String(localized: "Created"), value: stamp(item.created, format: format)))
        facts.append(PanelFact(name: String(localized: "Edited"), value: stamp(item.modified, format: format)))
        guard case .file(let type, let bytes) = item.content else { return facts }
        facts.append(PanelFact(name: String(localized: "Kind"), value: type.localizedDescription ?? String(localized: "File")))
        // The server gives a file's size once it holds the bytes, so a file not yet sent has none.
        if bytes > 0 {
            facts.append(PanelFact(name: String(localized: "Size"), value: ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)))
        }
        if let width = number(item, MarfaMapping.widthField), let height = number(item, MarfaMapping.heightField) {
            facts.append(PanelFact(
                name: String(localized: "Dimensions"),
                value: String(localized: "\(Int(width).formatted()) × \(Int(height).formatted())", comment: "A picture's width and height in pixels.")))
        }
        if let seconds = number(item, MarfaMapping.durationField), seconds > 0 {
            facts.append(PanelFact(name: String(localized: "Length"), value: length(seconds)))
        }
        if let pages {
            facts.append(PanelFact(name: String(localized: "Pages"), value: pages.formatted()))
        }
        return facts
    }

    /// A moment as Info writes it: "Today, 07:02" or "Yesterday, 18:04" for these days, else the date with its year and the
    /// time, "2 Sep 2026, 09:12". A person's choice of dates and times is kept.
    static func stamp(
        _ date: Date, format: DateFormat, now: Date = .now, calendar: Calendar = .current, locale: Locale = .current
    ) -> String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0
        let place = format.usesWords && (-1...1).contains(days) ? DateDisplay.Place.table : .value
        let day = DateDisplay.text(of: date, hasTime: false, place: place, format: format, now: now, calendar: calendar, locale: locale)
        let time = DateDisplay.timeOfDay(of: date, format: format, calendar: calendar, locale: locale)
        return String(localized: "\(day), \(time)")
    }

    private static func number(_ item: Item, _ key: String) -> Double? {
        switch item.value(of: key) {
        case .number(let value)?: (value as NSDecimalNumber).doubleValue
        case .double(let value)?: value
        default: nil
        }
    }

    static func length(_ seconds: Double) -> String {
        let whole = Int(seconds.rounded())
        let (hours, minutes, rest) = (whole / 3600, whole / 60 % 60, whole % 60)
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, rest)
            : String(format: "%d:%02d", minutes, rest)
    }
}

/// The line Info says once at the top of an item a connector keeps: its symbol and its words.
nonisolated struct PanelKeptLine: Equatable, Sendable {
    let symbol: String
    let text: String
}

/// Who keeps an item, said once at the top of Info. A connector that only reads in makes the item Read Only, and one that
/// carries changes both ways says the item is Synced With it. Where the server's connectors are not known (not read yet, or
/// offline), the line is the item's own allowances alone (`Item.obstacle(to:)`), so the page, the commands and this line
/// never disagree about what is locked; only the read-only case has one then.
nonisolated enum PanelKeptBy {
    /// `direction` is how the connector that wrote the item moves items of its type, where the server has said.
    static func line(of item: Item, source: String?, direction: ConnectorDirection?) -> PanelKeptLine? {
        switch direction {
        case .into?: readOnly(source)
        case .both?: source.map { PanelKeptLine(symbol: "arrow.triangle.2.circlepath", text: String(localized: "Synced With \($0).")) }
        case .out?, nil: item.obstacle(to: .fields) == .readOnly ? readOnly(source) : nil
        }
    }

    private static func readOnly(_ source: String?) -> PanelKeptLine {
        let text = source.map { String(localized: "Read only. \($0) keeps this item, so an edit here would be overwritten.") }
            ?? String(localized: "Read only. A connector keeps this item, so an edit here would be overwritten.")
        return PanelKeptLine(symbol: "lock", text: text)
    }
}
