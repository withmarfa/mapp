import Foundation

extension ValueEditModel {
    /// The Tags box ends other than at Escape: a tag typed and not yet added is added. One the library refuses is kept on
    /// the clipboard and told, so ending the field never drops what was typed.
    func finishTagField() {
        guard kind == .tags, !ItemTag.normalized(query).isEmpty else { return }
        submitTyped()
        guard !ItemTag.normalized(query).isEmpty else { return }
        request.library.notices.notKept(
            String(localized: "Tag Not Added"), text: query, reason: notice ?? String(localized: "The tag could not be added."))
    }
}
