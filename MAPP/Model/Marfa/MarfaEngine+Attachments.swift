import Foundation
import Marfa
import UniformTypeIdentifiers

/// Attaching a file to an item and naming it so an embed names it alone, and adding a file as an item of its own.
///
/// The copy reads a file it takes, which for a large one takes a while, so it does that beside the lane, as a purge
/// is made: the lane checks the item and chooses the title, a task asks the copy, and its answer comes back to the
/// lane as an event (`attached`, `addedFile`), which reads the items again. The person's saves go on meanwhile. The
/// write is set aside (`EngineActivity`) until its answer is taken, so a quit still waits for it.
extension MarfaEngine {
    /// The package queues the upload, the file's item and its edge to this one, and says what to write in the text
    /// to embed it. The title is the file's name unless another attachment of the item has it, or one being attached,
    /// since an embed must name one file alone; the text itself is the page's to place, and the editor saves it as it
    /// does any typing.
    func attach(_ file: URL, to id: ItemID, answering done: CheckedContinuation<Result<Embed, SourceFailure>, Never>) {
        guard let row = rows[id.rawValue], row.state == .active || row.state == .archived else {
            done.resume(returning: .failure(SourceFailure(kind: .missing, message: String(localized: "This item isn’t in the library."))))
            return
        }
        let title = attachmentTitle(for: file, on: row)
        attachingTitles[id.rawValue, default: []].insert(title.lowercased())
        let attachment = Attachment(mimeType: Self.mimeType(of: file), title: title)
        let token = UUID()
        hub.activity.setAside()
        #if DEBUG
        let replacement = hooks.attaching.current
        #endif
        besideTheLane[token] = Task { [copy, hub, tell] in
            let result: Result<Marfa.Attached, SourceFailure>
            do {
                result = .success(try await Self.asking(hub) {
                    #if DEBUG
                    if let replacement { return try await replacement(id.rawValue, title) }
                    #endif
                    return try await copy.items.attach(to: id.rawValue, file: file, attachment)
                })
            } catch {
                result = .failure(Self.failure(error))
            }
            if !tell(.attached(result, id, title: title, token: token, done)) {
                done.resume(returning: result.map { Self.embed(of: $0, title: title) })
            }
        }
    }

    func take(
        attached result: Result<Marfa.Attached, SourceFailure>, to id: ItemID, title: String, token: UUID
    ) async -> Result<Embed, SourceFailure> {
        settled(token, attaching: title, to: id)
        defer { hub.activity.answeredAside() }
        guard case .success(let attached) = result else { return result.map { Self.embed(of: $0, title: title) } }
        await reread(Set([id.rawValue] + [attached.item.itemId].compactMap(\.self)))
        await sync.drain()
        return .success(Self.embed(of: attached, title: title))
    }

    /// Where the package says no embed names the file alone, the file is attached all the same, so the text still
    /// links it by its title rather than the person being told it failed and attaching it twice.
    nonisolated static func embed(of attached: Marfa.Attached, title: String) -> Embed {
        let name = attached.embed.flatMap(embeddedName) ?? title
        return Embed(link: link(to: name), name: name)
    }

    /// The package queues the upload and the file's item, whose file type the core chooses from its media type;
    /// the item is then put under its parent, as a create's is.
    func addFile(
        _ file: URL, title: String?, tier: Tier?, under parent: ItemID?,
        answering done: CheckedContinuation<Result<ItemID, SourceFailure>, Never>
    ) {
        let attachment = Attachment(
            mimeType: Self.mimeType(of: file), title: title.map(Self.embeddable), tier: tier.map(MarfaMapping.marfaTier))
        let token = UUID()
        hub.activity.setAside()
        besideTheLane[token] = Task { [copy, hub, tell] in
            let result: Result<Marfa.Added, SourceFailure>
            do {
                result = .success(try await Self.asking(hub) { try await copy.items.addFile(file, attachment) })
            } catch {
                result = .failure(Self.failure(error))
            }
            if !tell(.addedFile(result, parent: parent, token: token, done)) {
                done.resume(returning: result.flatMap(Self.addedID))
            }
        }
    }

    func take(added result: Result<Marfa.Added, SourceFailure>, under parent: ItemID?, token: UUID) async -> Result<ItemID, SourceFailure> {
        settled(token)
        defer { hub.activity.answeredAside() }
        let id: ItemID
        switch result.flatMap(Self.addedID) {
        case .success(let added): id = added
        case .failure(let failure): return .failure(failure)
        }
        if let parent { await place(id, under: parent) }
        await reread(Set([id.rawValue] + [parent?.rawValue].compactMap(\.self)))
        await sync.drain()
        return .success(id)
    }

    nonisolated static func addedID(_ added: Marfa.Added) -> Result<ItemID, SourceFailure> {
        guard let raw = added.item.itemId else {
            return .failure(SourceFailure(kind: .failed, message: String(localized: "The file couldn’t be added.")))
        }
        return .success(ItemID(raw))
    }

    /// The copy answered the work beside the lane that `token` names.
    func settled(_ token: UUID, attaching title: String? = nil, to id: ItemID? = nil) {
        besideTheLane[token] = nil
        guard let title, let id else { return }
        attachingTitles[id.rawValue]?.remove(title.lowercased())
        if attachingTitles[id.rawValue]?.isEmpty == true { attachingTitles[id.rawValue] = nil }
    }

    /// Returns once the copy has answered every attach and added file asked of it beside the lane, so their writes
    /// are in its queue.
    func besideTheLaneQueued() async {
        for work in besideTheLane.values { await work.value }
    }

    /// The file's name, or that name with a number when another attachment of the item already has it.
    private func attachmentTitle(for file: URL, on host: Marfa.Item) -> String {
        let taken = Set(
            edges.edges(touching: host.id)
                .filter { $0.edgeType == MarfaMapping.attachmentEdge && $0.targetId == host.id }
                .compactMap { rows[$0.sourceId]?.title?.lowercased() })
            .union(attachingTitles[host.id] ?? [])
        let name = file.lastPathComponent
        let stem = file.deletingPathExtension().lastPathComponent
        let ext = file.pathExtension
        var title = Self.embeddable(name)
        var number = 1
        while taken.contains(title.lowercased()) {
            number += 1
            title = Self.embeddable(ext.isEmpty ? "\(stem) \(number)" : "\(stem) \(number).\(ext)")
        }
        return title
    }

    /// The media type the system gives the file, which the core keeps and chooses the file's type by. The core's
    /// own table of extensions is shorter than the system's: a TIFF or a FLAC file is still an image or a sound.
    nonisolated static func mimeType(of file: URL) -> String? {
        let type = (try? file.resourceValues(forKeys: [.contentTypeKey]).contentType)
            ?? UTType(filenameExtension: file.pathExtension)
        return type?.preferredMIMEType
    }

    /// An embed names its file between `![[` and `]]`, where `[`, `]`, `|`, `#` and `^` mean something else, so a
    /// title that holds them could not be embedded. The file keeps its name on disk; only its title in Marfa changes.
    nonisolated static func embeddable(_ name: String) -> String {
        String(name.map { "[]|#^".contains($0) ? "-" : $0 })
    }

    /// The name inside `![[name]]`, which the package writes for an embed.
    nonisolated static func embeddedName(_ embed: String) -> String? {
        guard embed.hasPrefix("![["), embed.hasSuffix("]]"), embed.count > 5 else { return nil }
        return String(embed.dropFirst(3).dropLast(2))
    }

    /// The name as a markdown destination: the page writes `![name](link)`, and the core reads the percent
    /// escapes of a path back to the name.
    nonisolated static func link(to name: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        // The destination of `![alt](path)` ends at the first closing parenthesis, so a name's own must be escaped.
        allowed.remove(charactersIn: "()")
        return name.addingPercentEncoding(withAllowedCharacters: allowed) ?? name
    }
}
