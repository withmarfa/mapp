import Foundation
import UniformTypeIdentifiers

/// What Quick Look is showing for a window: the files it was given, in the order the arrow keys move through them,
/// and the copies made for it, which are removed once it closes.
struct QuickLookRequest {
    var urls: [URL]
    var current: URL?
    fileprivate(set) var staged: [QuickLookFile]
}

extension Notification.Name {
    /// Posted, with the browser as its object, when a window shows Quick Look. The panel is shared by every window,
    /// so the others give up theirs and remove their copies.
    static let quickLookTaken = Notification.Name("com.withmarfa.mapp.quickLookTaken")
}

extension Browser {
    /// How many items Quick Look is given, in the order they are on screen. Each file is fetched before it is
    /// shown, so a large selection is not fetched whole.
    static let quickLookLimit = 10

    /// Shows the selected items in Quick Look, in the order they are on screen: a file item as its file, fetched
    /// first, and any other item as its text in a markdown file. Quick Look picks a previewer from the file's name,
    /// so each is shown a copy named after the item. The first is shown as soon as it is ready and the rest join
    /// it as they are fetched, up to `quickLookLimit` items shown. An item that has neither, or whose file cannot be
    /// fetched, is left out and does not count; the person is told when that leaves nothing to show, and once when
    /// the selection has more than were shown. A request that is replaced or closed
    /// meanwhile stops and removes what it made.
    func quickLookSelection(in library: any ItemLibrary) async {
        dismissQuickLook()
        let generation = quickLookGeneration
        let selected = Dictionary(selectedItems(in: library).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var seen: Set<ItemID> = []
        let chosen = (onScreenOrder(in: library) + selection).compactMap { id in seen.insert(id).inserted ? selected[id] : nil }
        var made: [QuickLookFile] = []
        var shown = 0
        var failure: String?
        func isCurrent() -> Bool { generation == quickLookGeneration && isShowing(library) }
        func show(_ url: URL, staged file: QuickLookFile?) {
            shown += 1
            file.map { made.append($0) }
            if quickLook == nil {
                quickLook = QuickLookRequest(urls: [url], current: url, staged: made)
                NotificationCenter.default.post(name: .quickLookTaken, object: self)
            } else {
                quickLook?.urls.append(url)
                quickLook?.staged = made
            }
        }
        var cutOff = false
        for item in chosen {
            if shown == Self.quickLookLimit {
                cutOff = true
                break
            }
            if item.isFile {
                do {
                    let fetched = try await library.fileURL(of: item.id)
                    guard isCurrent() else { return made.forEach { $0.remove() } }
                    guard let fetched else { continue }
                    let copy = QuickLookFile.copy(of: fetched, titled: item.title, as: item.fileType ?? .data)
                    show(copy?.url ?? fetched, staged: copy)
                } catch {
                    guard isCurrent() else { return made.forEach { $0.remove() } }
                    failure = (error as? SourceFailure)?.message ?? error.localizedDescription
                }
            } else if let body = library.body(of: item.id),
                      let file = QuickLookFile.write(body.text, titled: item.title, as: .markdown) {
                show(file.url, staged: file)
            }
        }
        if cutOff {
            library.notices.tell(
                String(localized: "Quick Look"),
                String(localized: "Showing the first \(Self.quickLookLimit) of ^[\(chosen.count) item](inflect: true)."))
        }
        if quickLook == nil, !chosen.isEmpty {
            library.notices.tell(
                String(localized: "Can’t Quick Look"), failure ?? String(localized: "Nothing selected has a file or text to show."))
        }
    }

    /// Closes Quick Look's request, stops one still fetching, and removes the copies made for it.
    func dismissQuickLook() {
        quickLookGeneration += 1
        quickLook?.staged.forEach { $0.remove() }
        quickLook = nil
    }
}
