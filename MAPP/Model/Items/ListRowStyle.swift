import Foundation
import UniformTypeIdentifiers

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

    /// What a type's fields suggest: a person (`PageHeaderKind`), a Marfa highlight (`core.highlight`, which no field
    /// alone tells), pictures for a file type (a row shows a picture only for an item that is an image file, so a type of
    /// other files draws standard rows), else Task for a type with a status. The app names no type that a person or an
    /// app made.
    static func fromFields(of type: TypeID, in catalogue: Catalogue) -> ListRowStyle? {
        if PageHeaderKind.of(type, in: catalogue) == .person { return .person }
        var visited: Set<TypeID> = []
        var current: TypeID? = type
        while let id = current, visited.insert(id).inserted {
            if id == highlightType { return .highlight }
            current = catalogue.itemTypes[id]?.parent
        }
        if catalogue.isFileType(type) { return .withPictures }
        return catalogue.itemTypes[type]?.statusField == nil ? nil : .task
    }

    private static let highlightType = TypeID("core.highlight")

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
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let data = try? encoder.encode(stored), let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }

    subscript(type: TypeID) -> ListRowStyle? {
        get { styles[type] }
        set { styles[type] = newValue }
    }
}

/// What a list's rows need to know of one type, looked up once for the list so a row does no catalogue work: its style,
/// its icon, and, for a task, the fields its facts read.
nonisolated struct ListRowType: Hashable, Sendable {
    var style: ListRowStyle
    /// What a row of this type draws when its style is With Pictures and its item has no picture to show: the list's Row
    /// Style from Settings, since With Pictures is only where the type starts.
    var pictureless: ListRowStyle = .standard
    var icon: String?
    var isTask = false
    var statusField: ItemTypeInfo.Field?
    var priorityField: ItemTypeInfo.Field?

    /// A type the catalogue does not know: only its style.
    init(style: ListRowStyle, pictureless: ListRowStyle = .standard) {
        self.style = style
        self.pictureless = pictureless
    }

    init(_ type: TypeID, style: ListRowStyle, pictureless: ListRowStyle = .standard, in catalogue: Catalogue) {
        self.style = style
        self.pictureless = pictureless
        let info = catalogue.itemTypes[type]
        icon = info?.icon
        statusField = info?.statusField
        isTask = catalogue.isTask(type)
        if isTask { priorityField = info?.fields.first { $0.key == MarfaMapping.priorityField } }
    }

    /// The style a row draws for an item that does or does not have a picture to show.
    func drawnStyle(hasPicture: Bool) -> ListRowStyle {
        style == .withPictures && !hasPicture ? pictureless : style
    }

    /// The group of the word `item` holds in the type's status field.
    func statusGroup(of item: Item) -> StatusGroup? {
        guard let field = statusField, let word = item.value(of: field.key)?.string else { return nil }
        return field.statusGroup(of: word)
    }

    /// Each of `types` as a list shows it (`ListRowStyle.styles`).
    static func types(
        of types: some Collection<TypeID>, view: ListRowStyle? = nil, choices: ListTypeStyles, rowStyle: ListRowStyle,
        in catalogue: Catalogue
    ) -> [TypeID: ListRowType] {
        let styles = ListRowStyle.styles(of: types, view: view, choices: choices, rowStyle: rowStyle, in: catalogue)
        let pictureless = ListRowStyle.resolve(rowStyle: rowStyle)
        return styles.reduce(into: [:]) { $0[$1.key] = ListRowType($1.key, style: $1.value, pictureless: pictureless, in: catalogue) }
    }
}

extension Item {
    /// Whether the item is an image file, the only item a list row shows a picture for.
    nonisolated var isImageFile: Bool {
        if case .file(let type, _) = content { type.conforms(to: .image) } else { false }
    }
}
