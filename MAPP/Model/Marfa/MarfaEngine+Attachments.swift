import Foundation
import Marfa

/// Attaching a file to an item and naming it so an embed names it alone.
extension MarfaEngine {
    /// The package queues the upload, the file's item and its edge to this one, and says what to write in the text
    /// to embed it. The title is the file's name unless another attachment of the item has it, since an embed must
    /// name one file alone; the text itself is the page's to place, and the editor saves it as it does any typing.
    func attach(_ file: URL, to id: ItemID) async -> Result<Embed, SourceFailure> {
        do {
            guard let row = rows[id.rawValue], row.state == .active || row.state == .archived else {
                throw SourceFailure(kind: .missing, message: String(localized: "This item isn’t in the library."))
            }
            let title = attachmentTitle(for: file, on: row)
            let attached = try await Self.asking(hub) {
                try await copy.items.attach(to: id.rawValue, file: file, Attachment(title: title))
            }
            await reread(Set([id.rawValue] + [attached.item.itemId].compactMap(\.self)))
            await sync.drain()
            // Where the package says no embed names the file alone, the file is attached all the same, so the text
            // still links it by its title rather than the person being told it failed and attaching it twice.
            let name = attached.embed.flatMap(Self.embeddedName) ?? title
            return .success(Embed(link: Self.link(to: name), name: name))
        } catch let error as SourceFailure {
            return .failure(error)
        } catch {
            return .failure(Self.failure(error))
        }
    }

    /// The file's name, or that name with a number when another attachment of the item already has it.
    private func attachmentTitle(for file: URL, on host: Marfa.Item) -> String {
        let taken = Set(
            edges.edges(touching: host.id)
                .filter { $0.edgeType == MarfaMapping.attachmentEdge && $0.targetId == host.id }
                .compactMap { rows[$0.sourceId]?.title?.lowercased() })
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
