import Foundation

/// Saved views, which live on the server and are read from the copy beside the views as a search is, and files.
extension MarfaLibrary {
    private static let previewLimit = 8

    func createView(_ settings: LibraryViewSettings) async -> LibraryView? {
        let result = await writingView(.create(settings), failing: String(localized: "Can’t Save View")) { [source] key in
            try await source.createView(settings, idempotencyKey: key)
        }
        guard case .success(let view) = result else { return nil }
        hold(view)
        return view
    }

    func changeView(_ view: ItemID, _ change: LibraryViewChange, baseVersion: Int64) async -> Result<LibraryView, ViewWriteFailure> {
        let renames = change.title != nil && change.query == nil && change.sort == nil && change.group == nil
        let title = renames ? String(localized: "Can’t Rename View") : String(localized: "Can’t Update View")
        let result = await writingView(.change(view, change, baseVersion), failing: title) { [source] key in
            try await source.changeView(view, change, baseVersion: baseVersion, idempotencyKey: key)
        }
        switch result {
        case .success(let changed): hold(changed)
        // The copy keeps what it held, so the server is asked again for what changed.
        case .failure(let failure) where failure.kind == .conflict: source.refresh()
        case .failure: break
        }
        return result
    }

    func deleteView(_ view: ItemID) async -> Bool {
        let result = await writingView(.delete(view), failing: String(localized: "Can’t Delete View")) { [source] key in
            try await source.deleteView(view, idempotencyKey: key)
        }
        guard case .success = result else { return false }
        take(views.filter { $0.id != view })
        return true
    }

    /// What the server answered is shown at once, before the copy's own word arrives.
    private func hold(_ view: LibraryView) {
        take(LibraryView.ordered(views.filter { $0.id != view.id } + [view]))
    }

    private func writingView<Value>(
        _ write: ViewWrite, failing title: String, _ send: (String) async throws -> Value
    ) async -> Result<Value, ViewWriteFailure> {
        let key = viewWriteKeys[write] ?? UUID().uuidString
        do {
            let value = try await send(key)
            viewWriteKeys[write] = nil
            return .success(value)
        } catch {
            let failure = error as? ViewWriteFailure ?? ViewWriteFailure(kind: .refused, message: error.localizedDescription)
            viewWriteKeys[write] = failure.kind == .offline ? key : nil
            notices.tell(title, failure.message)
            return .failure(failure)
        }
    }

    /// Answers from the copy's own reading of the view, which runs beside the views as a search does: until it
    /// returns, the last list stands, and a change to the items reads it again. The list is what the copy holds.
    func items(inView id: ItemID) -> [Item] {
        listed(viewHits(id))
    }

    func count(inView id: ItemID) -> Int {
        viewHits(id).lazy.filter { self.viewItem($0) != nil }.count
    }

    func listedIDs(_ ids: Set<ItemID>, inView view: ItemID) -> Set<ItemID> {
        Set(viewHits(view).lazy.filter { ids.contains($0) && self.viewItem($0) != nil })
    }

    private func viewHits(_ id: ItemID) -> [ItemID] {
        _ = viewRevision
        let revision = contentRevision
        let held = viewed[id]
        if views.contains(where: { $0.id == id }), held.map({ $0.revision != revision && !$0.running }) ?? true {
            startViewRead(id, at: revision)
        }
        return held?.hits ?? []
    }

    private func listed(_ hits: [ItemID]) -> [Item] {
        let content = contentRevision
        if let held = orderedView, held.content == content, held.hits == hits { return held.items }
        let items = Self.ordered(hits.compactMap(viewItem))
        orderedView = (content, hits, items)
        return items
    }

    private func viewItem(_ id: ItemID) -> Item? {
        guard let item = records[id]?.listedItem, item.state != .trashed else { return nil }
        return item
    }

    func deferredView(_ id: ItemID, preview: LibraryViewQuery?, above limit: Int) -> DeferredListing? {
        let hits = preview.map { previewHits(ofView: id, query: $0) } ?? viewHits(id)
        guard hits.count > limit else { return nil }
        let content = contentRevision
        let revision = viewRevision
        if let held = orderedView, held.content == content, held.hits == hits { return nil }
        let snapshots = index.items
        return DeferredListing(make: {
            Self.ordered(hits.compactMap { id in
                guard let item = snapshots[id], item.state != .trashed else { return nil }
                return item
            })
        }, take: { [weak self] items in
            guard let self, contentRevision == content, viewRevision == revision else { return }
            orderedView = (content, hits, items)
        })
    }

    /// Answers from the copy's own reading of the query, as `items(inView:)` does of the view's: until it returns,
    /// the view's last preview stands, or the view's own list where there is none; a change to the items reads it
    /// again. A query the copy refuses lists the view's own list, and says why once.
    func previewItems(ofView id: ItemID, query: LibraryViewQuery) -> [Item] {
        listed(previewHits(ofView: id, query: query))
    }

    private func previewHits(ofView id: ItemID, query: LibraryViewQuery) -> [ItemID] {
        _ = viewRevision
        let revision = contentRevision
        let key = PreviewKey(view: id, query: query)
        if previewOrder.last != key {
            previewOrder.removeAll { $0 == key }
            previewOrder.append(key)
            while previewOrder.count > Self.previewLimit { previews[previewOrder.removeFirst()] = nil }
        }
        let held = previews[key]
        if views.contains(where: { $0.id == id }), held.map({ $0.revision != revision && !$0.running }) ?? true {
            startPreviewRead(key, at: revision)
        }
        return held?.hits ?? (held?.refused == true ? nil : lastPreview[id]) ?? viewHits(id)
    }

    private func startPreviewRead(_ key: PreviewKey, at revision: Int) {
        previews[key, default: Preview(revision: revision, hits: nil, running: true)].running = true
        newestPreviewRead[key.view] = key
        Task { [weak self, source] in
            let found: Result<[ItemID], any Error>
            do {
                found = .success(try await source.items(matching: key.query))
            } catch {
                found = .failure(error)
            }
            // Dropped with the view, or pushed out by newer queries, while it ran.
            guard let self, let held = previews[key] else { return }
            switch found {
            case .success(let hits):
                previews[key] = Preview(revision: revision, hits: hits, running: false)
                if newestPreviewRead[key.view] == key { lastPreview[key.view] = hits }
                previewsFailing.remove(key.view)
            case .failure(let error):
                previews[key] = Preview(revision: revision, hits: held.hits, running: false, refused: true)
                // A view whose own list was refused has said so already.
                if previewsFailing.insert(key.view).inserted, !viewsFailing.contains(key.view) {
                    notices.tell(String(localized: "Can’t Show This View"), error.localizedDescription)
                }
            }
            viewRevision += 1
        }
    }

    /// A view the copy cannot answer, such as one asking for a type it does not hold, keeps what it last listed
    /// and says why once, rather than at every change; it is not asked again until the items change.
    private func startViewRead(_ id: ItemID, at revision: Int) {
        viewed[id, default: Search(revision: revision, hits: [], running: true)].running = true
        let generation = viewsGeneration
        Task { [weak self, source] in
            let found: Result<[ItemID], any Error>
            do {
                found = .success(try await source.items(inView: id))
            } catch {
                found = .failure(error)
            }
            // The views changed while it ran, so what it read may be of a view since changed.
            guard let self, viewsGeneration == generation else { return }
            switch found {
            case .success(let hits):
                viewed[id] = Search(revision: revision, hits: hits, running: false)
                viewsFailing.remove(id)
            case .failure(let error):
                viewed[id] = Search(revision: revision, hits: viewed[id]?.hits ?? [], running: false)
                if viewsFailing.insert(id).inserted {
                    notices.tell(String(localized: "Can’t Show This View"), error.localizedDescription)
                }
            }
            viewRevision += 1
        }
    }

    /// A file's bytes come from the server's blobs, so they are never at hand without asking.
    func fileURL(of id: ItemID) async throws -> URL? {
        guard item(id)?.isFile == true else { return nil }
        return try await source.fileURL(of: id)
    }

    func attachments(of id: ItemID) -> [ItemID] {
        // The index is not observed. A file attached or taken off changes an edge of this item or of the file.
        // A change to the file itself is followed through its own record, which a reader of the list reads with `item(_:)`.
        observeLinks(of: id)
        return index.links(to: id, type: MarfaMapping.attachmentEdge).map(\.from)
    }
}
