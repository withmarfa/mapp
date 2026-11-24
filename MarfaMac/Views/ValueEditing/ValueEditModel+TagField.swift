import Foundation

extension ValueEditModel {
    /// The Tags box ends other than at Escape: a tag typed and not yet added is added. One the library refuses is kept on
    /// the clipboard and told, once, so ending the field never drops what was typed.
    func finishTagField() {
        guard kind == .tags else { return }
        if !ItemTag.normalized(query).isEmpty {
            submitTyped()
            // The box ends here, so a tag it still holds was not added, whichever row Return chose.
            if unsaved == nil, !ItemTag.normalized(query).isEmpty { refuse(notice ?? String(localized: "The tag could not be added."), typed: true) }
        }
        handBackUnsaved()
    }
}
