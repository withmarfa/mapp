import CoreTransferable
import UniformTypeIdentifiers

/// Board moves need identities even when an item's body has not been downloaded.
nonisolated struct BoardItemReference: Codable, Transferable, Identifiable {
    let id: ItemID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .mappBoardItem)
    }
}

extension UTType {
    nonisolated static let mappBoardItem = UTType(exportedAs: "com.withmarfa.mapp.board-item")
}
