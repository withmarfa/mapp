import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

/// What a dragged row of the view panel carries inside the app: its identifier, which is all a drop on a group reads.
nonisolated struct LayoutRowDrag: Codable, Transferable {
    let id: String

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .marfaLayoutRow)
    }
}

extension UTType {
    /// Named for the bundle identifier, as `MarfaMac/Info.plist` declares it, so a row never drags into the other build.
    nonisolated static let marfaLayoutRow = UTType(exportedAs: "\(AppPaths.bundleIdentifier).layout-row")
}
