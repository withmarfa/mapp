import Foundation
import UniformTypeIdentifiers

/// What Quick Look is showing for a window: the files it was given, in the order the arrow keys move through them,
/// and the copies made for it, which are removed once it closes.
struct QuickLookRequest {
    let urls: [URL]
    var current: URL?
    fileprivate let staged: [QuickLookFile]
}

extension Browser {
    /// Shows the selected items in Quick Look: a file item as its file, fetched first, and any other item as its
    /// text in a markdown file. Quick Look picks a previewer from the file's name, so each is shown a copy named after
    /// the item. An item that has neither, or whose file cannot be fetched, is left out and the person is told when
    /// that leaves nothing to show.
    func quickLookSelection(in library: any ItemLibrary) async {
        dismissQuickLook()
        let chosen = selectedItems(in: library).sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        var urls: [URL] = []
        var staged: [QuickLookFile] = []
        var failure: String?
        for item in chosen {
            if item.isFile {
                do {
                    guard let url = try await library.fileURL(of: item.id) else { continue }
                    let copy = QuickLookFile.copy(of: url, titled: item.title, as: item.fileType ?? .data, key: item.id.rawValue)
                    copy.map { staged.append($0) }
                    urls.append(copy?.url ?? url)
                } catch {
                    failure = (error as? SourceFailure)?.message ?? error.localizedDescription
                }
            } else if let body = library.body(of: item.id),
                      let file = QuickLookFile.write(body.text, titled: item.title, as: .markdown, key: item.id.rawValue) {
                staged.append(file)
                urls.append(file.url)
            }
        }
        guard !urls.isEmpty else {
            if !chosen.isEmpty {
                library.notices.tell(
                    String(localized: "Can’t Quick Look"), failure ?? String(localized: "Nothing selected has a file or text to show."))
            }
            return
        }
        quickLook = QuickLookRequest(urls: urls, current: urls[0], staged: staged)
    }

    /// Closes Quick Look's request and removes the copies made for it.
    func dismissQuickLook() {
        quickLook?.staged.forEach { $0.remove() }
        quickLook = nil
    }
}
