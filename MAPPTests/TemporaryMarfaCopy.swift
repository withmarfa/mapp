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
