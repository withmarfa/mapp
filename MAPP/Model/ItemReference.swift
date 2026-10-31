import CoreTransferable
import UniformTypeIdentifiers

/// What a dragged item carries. Inside the app it is the item's identity, which is all a drop on a collection or a
/// board lane reads. Out of the app it is a file: a note as a markdown file and as text, and a file item as the
/// file itself, each named after the item, so Finder and any app that takes files can be given it.
nonisolated struct ItemReference: Codable, Transferable, Identifiable {
    /// What the item is when it leaves the app. Nil where the item has nothing to leave as, such as a file item
    /// whose file cannot be fetched; the reference still names the item for drops in the app.
    nonisolated enum Content: Sendable {
        case text(String)
        /// Fetches the file where it is kept, which may take a moment.
        case file(@MainActor @Sendable () async throws -> URL?)
    }

    let id: ItemID
    let title: String
    /// What the file is: the file's own type, or markdown for a note.
    let type: UTType
    let content: Content?

    init(id: ItemID, title: String = "", type: UTType = .data, content: Content? = nil) {
        self.id = id
        self.title = title
        self.type = type
        self.content = content
    }

    // Only the identity crosses to another window of the app; the file is made again from the library there.
    private enum CodingKeys: String, CodingKey { case id }

    init(from decoder: any Decoder) throws {
        self.init(id: try decoder.container(keyedBy: CodingKeys.self).decode(ItemID.self, forKey: .id))
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
    }

    /// The note's markdown, for an app that takes text.
    var text: String? {
        if case .text(let text) = content { text } else { nil }
    }

    private var fileName: String { QuickLookFile.name(for: title, type: type) }

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .mappItem)
        FileRepresentation(exportedContentType: .plainText) { reference in
            guard case .text(let text) = reference.content,
                  let staged = QuickLookFile.write(text, titled: reference.title, as: reference.type, in: Self.folder, key: reference.id.rawValue)
            else { throw CocoaError(.fileNoSuchFile) }
            return SentTransferredFile(staged.url)
        }
        .exportingCondition { $0.text != nil }
        .suggestedFileName { $0.fileName }
        ProxyRepresentation(exporting: { $0.text ?? "" })
            .exportingCondition { $0.text != nil }
        FileRepresentation(exportedContentType: .data) { reference in
            guard case .file(let fetch) = reference.content, let url = try await fetch(),
                  let staged = QuickLookFile.copy(of: url, titled: reference.title, as: reference.type, in: Self.folder, key: reference.id.rawValue)
            else { throw CocoaError(.fileNoSuchFile) }
            return SentTransferredFile(staged.url)
        }
        .exportingCondition { if case .file = $0.content { true } else { false } }
        .suggestedFileName { $0.fileName }
    }

    /// Where the files an item is dragged out as are made, one folder for each item, replaced by the next drag.
    nonisolated static let folder = "Drag"
}

extension UTType {
    /// Named for the bundle identifier, as `MAPP/Info.plist` declares it, so the Debug build and the installed app
    /// each own their type and an item never drags from one into the other.
    nonisolated static let mappItem = UTType(exportedAs: "\(Bundle.main.bundleIdentifier ?? "com.withmarfa.mapp").item")
}

extension ItemLibrary {
    /// What a drag of `id` carries. A note brings its text, held now; a file brings the way to fetch it, since the
    /// file may be on the server until a drop target asks for it.
    func dragReference(of id: ItemID) -> ItemReference {
        guard let item = item(id) else { return ItemReference(id: id) }
        if item.isFile {
            return ItemReference(id: id, title: item.title, type: item.fileType ?? .data, content: .file { [self] in try await fileURL(of: id) })
        }
        guard let body = body(of: id) else { return ItemReference(id: id, title: item.title) }
        return ItemReference(id: id, title: item.title, type: .markdown, content: .text(body.text))
    }
}
