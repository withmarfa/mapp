import Foundation
import UniformTypeIdentifiers

/// A regular file in the chosen library, whose bytes remain its only content authority.
nonisolated struct AppFile: Identifiable, Sendable {
    var id: ItemID
    var stored: StoredFile
    var folderID: ItemID?
    var path: String { stored.path }
    var title: String { (path as NSString).lastPathComponent }
    var contentType: UTType { UTType(filenameExtension: (path as NSString).pathExtension) ?? .data }
    var isImage: Bool { contentType.conforms(to: .image) }
    var isPDF: Bool { contentType.conforms(to: .pdf) }
}
