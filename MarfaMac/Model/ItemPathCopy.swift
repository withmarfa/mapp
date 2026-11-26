import AppKit

nonisolated enum ItemPathLimit {
    /// The most items Copy File Paths takes at once: each file is fetched before its path is known.
    static let items = 100
}

extension ItemLibrary {
    /// Whether any of `ids` is a file item, which is all Copy File Path acts on.
    func holdsFile(among ids: Set<ItemID>) -> Bool {
        ids.contains { item($0)?.isFile == true }
    }

    /// Copies the path of each chosen file item's file, fetched first, one to a line in the order given. An item that
    /// is not a file is left out and the person is told how many, and counts nothing against the limit; with no file to
    /// copy, or if the pasteboard changed while the files were fetched, it is left as it was.
    func copyFilePaths(of ids: [ItemID], to pasteboard: NSPasteboard = .general) async {
        guard mayWriteClipboard() else { return }
        let files = ids.filter { item($0)?.isFile == true }
        guard files.count <= ItemPathLimit.items else {
            notices.tell(
                String(localized: "Too Many Items for Paths"),
                String(localized: "Copy File Paths takes up to \(ItemPathLimit.items) items at once, because each file is fetched. Choose fewer items."))
            return
        }
        let before = pasteboard.changeCount
        var paths: [String] = []
        var skipped = ids.count - files.count
        var failure: String?
        for id in files {
            do {
                if let url = try await fileURL(of: id) { paths.append(url.path) } else { skipped += 1 }
            } catch {
                skipped += 1
                failure = (error as? SourceFailure)?.message ?? error.localizedDescription
            }
        }
        guard !paths.isEmpty else {
            notices.tell(
                ids.count == 1 ? String(localized: "Can’t Copy File Path") : String(localized: "Can’t Copy File Paths"),
                failure ?? String(localized: "These items have no file."))
            return
        }
        guard pasteboard.changeCount == before else {
            notices.tell(
                String(localized: "Paths Not Copied"),
                String(localized: "The clipboard changed while the files were being fetched, so it was left as it is. Try again."))
            return
        }
        pasteboard.clearContents()
        pasteboard.setString(paths.joined(separator: "\n"), forType: .string)
        if skipped > 0 {
            notices.tell(
                String(localized: "Some Paths Not Copied"),
                String(localized: "\(skipped) of the items have no file, or it couldn’t be fetched, so only the others were copied."))
        }
    }
}
