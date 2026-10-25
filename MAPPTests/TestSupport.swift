import Foundation
@testable import MAPP

/// A folder of its own in the temporary directory, removed when the test ends.
final class TemporaryFolder {
    let url: URL

    init() throws {
        url = URL.temporaryDirectory.appending(path: "MAPPTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    func write(_ text: String, to path: String) throws {
        let file = url.appending(path: path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: file)
    }
}

extension ItemLibrary {
    /// Text typed on the text the library holds now, as the page reports it while nothing has changed elsewhere.
    func updateBody(of id: ItemID, to body: String) {
        updateBody(of: id, to: body, readAt: self.body(of: id)?.version ?? ItemVersion(0))
    }
}
