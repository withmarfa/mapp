import Foundation

nonisolated extension AttributedString {
    /// The characters without their attributes. A plural written as `^[\(count) item](inflect: true)` is resolved only
    /// by `AttributedString(localized:)` or `Text`, never by `String(localized:)`, which leaves the markup in the
    /// text; so the model, which draws nothing, reads its plural strings through this.
    var text: String { String(characters) }
}
