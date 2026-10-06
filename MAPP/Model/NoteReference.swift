import CoreTransferable
import UniformTypeIdentifiers

/// What a dragged note carries: its identity for drops inside the app, and its markdown for any other app.
nonisolated struct NoteReference: Codable, Transferable, Identifiable {
    let id: ItemID
    let markdown: String

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .mappNote)
        ProxyRepresentation(exporting: \.markdown)
    }
}

extension UTType {
    nonisolated static let mappNote = UTType(exportedAs: "com.withmarfa.mapp.note")
}
