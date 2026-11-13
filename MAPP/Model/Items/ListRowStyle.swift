import Foundation
import UniformTypeIdentifiers

/// How a row of a list is drawn. Standard, Compact and With Pictures can be the style of every list; Task, Highlight and
/// Person read the fields of the items they suit, so they are chosen for a view, or come from a type's fields.
nonisolated enum ListRowStyle: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
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

    /// The one style a list's rows take: the view's choice, else the style the type's fields suggest, else the Row Style
    /// of Settings. Row Style names a style for every list, so another one stored there reads as Standard.
    static func resolve(view: ListRowStyle? = nil, fields: ListRowStyle? = nil, rowStyle: ListRowStyle) -> ListRowStyle {
        view ?? fields ?? (forEveryList.contains(rowStyle) ? rowStyle : .standard)
    }

    /// The style each of `types` takes in a list, resolved once for the list so a row only looks its type up. A
    /// view's choice names every row's style.
    static func styles(
        of types: some Collection<TypeID>, view: ListRowStyle? = nil, rowStyle: ListRowStyle, in catalogue: Catalogue
    ) -> [TypeID: ListRowStyle] {
        Dictionary(
            types.map { type in (type, resolve(view: view, fields: fromFields(of: type, in: catalogue), rowStyle: rowStyle)) },
            uniquingKeysWith: { first, _ in first })
    }

    /// The style the type's preset suggests (`LookPreset.suggested`): Person for a person, Highlight for a quote, Task for
    /// a type with a status, and pictures for a file type (a row shows a picture only for an item that is an image file,
    /// so a type of other files draws standard rows). The other presets leave the style to the list.
    static func fromFields(of type: TypeID, in catalogue: Catalogue) -> ListRowStyle? {
        switch LookPreset.suggested(for: type, in: catalogue) {
        case .person: .person
        case .quote: .highlight
        case .task: .task
        case .media: catalogue.isFileType(type) ? .withPictures : nil
        case .note, .message, .event, .place, .clip, .record: nil
        }
    }

    /// Whether rows of this style may show a picture.
    var showsPictures: Bool { self == .withPictures }
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
        of types: some Collection<TypeID>, view: ListRowStyle? = nil, rowStyle: ListRowStyle, in catalogue: Catalogue
    ) -> [TypeID: ListRowType] {
        let styles = ListRowStyle.styles(of: types, view: view, rowStyle: rowStyle, in: catalogue)
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
