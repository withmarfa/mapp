import Foundation

/// The mark beside a name in a place that lists both types' icons and symbols the app chose for itself, such as the
/// command palette's rows, an index page's tiles and a list row's line of facts.
nonisolated enum RowIcon: Hashable, Sendable {
    /// An SF Symbol for something that is not a type: a place, a command, a state.
    case symbol(String)
    /// A type's icon, an Iconify ID such as `lucide:folder`; nil for a type that has none.
    case type(String?)
}

/// How the editor page names a type's icon among the images the app sends it.
nonisolated enum TypeIconKey {
    static func value(for icon: String?) -> String { "type:" + (icon ?? "") }
}
