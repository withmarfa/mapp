import Foundation
import Marfa

nonisolated struct TemporaryMarfaCopy {
    let root: URL

    init() throws {
        root = URL.temporaryDirectory.appending(path: "MarfaCopy-\(UUID())", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func open() async throws -> WorkingCopy {
        try await WorkingCopy.open(store: root.appending(path: "store.sqlite"))
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}

extension Marfa.ItemType {
    /// A note as the server ships it, for a fake copy's catalog: an app declares only `app.*` types, which MAPP hides.
    nonisolated static let shippedNote = Marfa.ItemType(
        id: "core.note", label: "Note",
        fields: [
            TypeField(name: "title", type: "string", declaredBy: "core.note"),
            TypeField(name: "body", type: "string", declaredBy: "core.note"),
        ], titleField: "title", bodyField: "body")
}
