import Foundation

/// Holds a copy's writer lock from a child `sqlite3` process, with an exclusive transaction kept open on its input.
/// POSIX locks belong to a process, so this is a holder that SQLite in the test's own process knows nothing of.
final class OtherProcessLock {
    enum Failure: Error {
        case notStarted(String)
        case notHeld
    }

    private let process = Process()
    private let input = Pipe()

    init(_ store: URL) async throws {
        let output = Pipe()
        process.executableURL = URL(filePath: "/usr/bin/sqlite3")
        process.arguments = [store.path + ".writer-lock"]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            throw Failure.notStarted(String(describing: error))
        }
        input.fileHandleForWriting.write(Data("BEGIN EXCLUSIVE;\nSELECT 'held';\n".utf8))
        // The line comes back only once the transaction has begun.
        for try await line in output.fileHandleForReading.bytes.lines where line == "held" { return }
        release()
        throw Failure.notHeld
    }

    /// Ends the process, which ends its transaction. It is safe to call twice.
    func release() {
        guard process.isRunning else { return }
        process.terminate()
        process.waitUntilExit()
    }
}
