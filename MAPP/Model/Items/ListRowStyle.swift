import Foundation

/// How a row of a list is drawn. Standard, Compact and With Pictures can be the style of every list; Task, Highlight and
/// Person read the fields of the items they suit, so they are chosen for a type or a view, or come from a type's fields.
nonisolated enum ListRowStyle: String, CaseIterable, Identifiable, Hashable, Sendable {
    case standard, compact, withPictures, task, highlight, person

    var id: Self { self }

    /// The styles Settings offers for every list.
    static let forEveryList: [ListRowStyle] = [.standard, .compact, .withPictures]

    var title: String {
        switch self {
        case .standard: String(localized: "Standard")
        case .compact: String(localized: "Compact")
        case .withPictures: String(localized: "With Pictures")
        case .task: String(localized: "Task")
        case .highlight: String(localized: "Highlight")
        case .person: String(localized: "Person")
        }
    }

    /// The one style a list's rows take: the view's choice, else the type's own choice, else the style the type's
    /// fields suggest, else the Row Style of Settings. Row Style names a style for every list, so another one stored
    /// there reads as Standard.
    static func resolve(
        view: ListRowStyle? = nil, type: ListRowStyle? = nil, fields: ListRowStyle? = nil, rowStyle: ListRowStyle
    ) -> ListRowStyle {
        view ?? type ?? fields ?? (forEveryList.contains(rowStyle) ? rowStyle : .standard)
    }

    /// The style each of `types` takes in a list, resolved once for the list so a row only looks its type up. A
    /// view's choice names every row's style.
    static func styles(
        of types: some Collection<TypeID>, view: ListRowStyle? = nil, choices: ListTypeStyles, rowStyle: ListRowStyle,
        in catalogue: Catalogue
    ) -> [TypeID: ListRowStyle] {
        Dictionary(
            types.map { type in
                (type, resolve(view: view, type: choices[type], fields: fromFields(of: type, in: catalogue), rowStyle: rowStyle))
            }, uniquingKeysWith: { first, _ in first })
    }

    /// What a type's fields suggest: a person (`PageHeaderKind`), a Marfa highlight or a picture file, by the built-in
    /// type the type is or builds on, else Task for a type with a status. The app names no type that a person or an app
    /// made.
    static func fromFields(of type: TypeID, in catalogue: Catalogue) -> ListRowStyle? {
        if PageHeaderKind.of(type, in: catalogue) == .person { return .person }
        var visited: Set<TypeID> = []
        var current: TypeID? = type
        while let id = current, visited.insert(id).inserted {
            if let style = builtIn[id] { return style }
            current = catalogue.itemTypes[id]?.parent
        }
        return catalogue.itemTypes[type]?.statusField == nil ? nil : .task
    }

    private static let builtIn: [TypeID: ListRowStyle] = [
        TypeID("core.highlight"): .highlight,
        TypeID("core.file.image"): .withPictures,
    ]

    /// Whether rows of this style may show a picture.
    var showsPictures: Bool { self == .withPictures }
}

/// The style each type was given in Settings, kept as one setting. A type with no entry takes the style its fields
/// suggest.
nonisolated struct ListTypeStyles: RawRepresentable, Hashable, Sendable {
    private var styles: [TypeID: ListRowStyle]

    init() { styles = [:] }

    /// Reads the stored JSON, an object of style names by type identifier. Anything unreadable, and a style that is no
    /// longer one, is dropped, so a stale setting never stops a list from drawing.
    init?(rawValue: String) {
        guard let data = rawValue.data(using: .utf8),
              let stored = try? JSONDecoder().decode([String: String].self, from: data) else {
            styles = [:]
            return
        }
        styles = Dictionary(
            stored.compactMap { key, name in ListRowStyle(rawValue: name).map { (TypeID(key), $0) } },
            uniquingKeysWith: { first, _ in first })
    }

    var rawValue: String {
        let stored = Dictionary(styles.map { ($0.key.rawValue, $0.value.rawValue) }, uniquingKeysWith: { first, _ in first })
        guard let data = try? JSONEncoder().encode(stored), let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }

    subscript(type: TypeID) -> ListRowStyle? {
        get { styles[type] }
        set { styles[type] = newValue }
    }
}
