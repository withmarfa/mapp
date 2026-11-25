import Foundation
import Marfa
import Synchronization

/// Which copy each server origin opens, and which Marfa instance each copy holds, so one Marfa keeps one copy however
/// its address is typed and wherever it moves. It is kept beside the copies, in one file written whole, so a step that
/// stops part way leaves the record as it was before or after, never between.
nonisolated final class MarfaCopies: Sendable {
    struct Record: Codable, Equatable, Sendable {
        /// The copy folder each origin opens, by the origin the package keeps its sign-in under.
        var origins: [String: String] = [:]
        /// The instance each copy folder was read or verified to hold.
        var instances: [String: String] = [:]
    }

    enum Failure: Error, Equatable {
        case notKept
    }

    let file: URL
    private let record: Mutex<Record>

    private init(root: URL) {
        file = root.appending(path: "Copies.json", directoryHint: .notDirectory)
        record = Mutex(Self.read(file))
    }

    /// One record for each folder of copies in this process, so every `MarfaStoreLocation` on it agrees.
    private static let open = Mutex<[String: MarfaCopies]>([:])

    static func at(_ root: URL) -> MarfaCopies {
        open.withLock { open in
            let key = root.standardizedFileURL.path
            if let copies = open[key] { return copies }
            let copies = MarfaCopies(root: root)
            open[key] = copies
            return copies
        }
    }

    /// A file that cannot be read is set aside beside itself, never removed, and the copies are found by their
    /// addresses until the record is made again.
    private static func read(_ file: URL) -> Record {
        guard let data = try? Data(contentsOf: file) else { return Record() }
        if let record = try? JSONDecoder().decode(Record.self, from: data) { return record }
        let aside = file.deletingLastPathComponent().appending(path: "Copies unreadable \(UUID().uuidString).json")
        try? FileManager.default.moveItem(at: file, to: aside)
        return Record()
    }

    /// The origin a sign-in is kept under, which leaves out the scheme's own port.
    static func origin(of connection: MarfaConnection) -> String {
        KeychainKeyStore.account(for: connection.address)
    }

    var current: Record { record.withLock { $0 } }

    func folder(forOrigin origin: String) -> String? {
        record.withLock { $0.origins[origin] }
    }

    func instance(ofFolder folder: String) -> String? {
        record.withLock { $0.instances[folder] }
    }

    /// The folders recorded as holding `instance`.
    func folders(holding instance: String) -> [String] {
        record.withLock { $0.instances.filter { $0.value == instance }.map(\.key).sorted() }
    }

    /// Changes the record and writes it whole. Where it cannot be written, the record stays as it was.
    func change(_ edit: (inout Record) -> Void) throws(Failure) {
        try record.withLock { (held: inout Record) throws(Failure) in
            var next = held
            edit(&next)
            guard next != held else { return }
            do {
                try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                try JSONEncoder().encode(next).write(to: file, options: .atomic)
            } catch {
                throw .notKept
            }
            held = next
        }
    }

    /// Puts the record back to `earlier`, for a step that did not finish.
    func restore(_ earlier: Record) {
        try? change { $0 = earlier }
    }
}
