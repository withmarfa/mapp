import Foundation
import SQLite3

/// Sets aside a copy that a different version of the app made and that holds nothing the server has not taken, so
/// a new one can be made in its place. The package refuses such a copy whether or not this process could become
/// its writer, and a process that holds it as writer, such as another copy of the app sharing the container, may
/// still write to it. So the copy is moved only under the writer lock the core takes (`lock.rs` in Marfa's core),
/// and in one rename, which happens whole or not at all.
///
/// The SQLite this calls is the core's own, linked into the app with it. SQLite tracks the locks of every connection
/// it has open in this process, so a core connection here holding the lock is seen, and closing this connection
/// keeps a core connection's lock. POSIX locks belong to the process, so a separate SQLite library would do neither.
nonisolated enum MarfaCopyReplacement {
    enum Refusal: Error, Hashable {
        /// Another process holds the copy as its writer.
        case held
        /// The lock could not be taken or the copy could not be moved, and nothing changed.
        case notMoved
    }

    /// Moves `directory`, which holds `store`, to a sibling named for `date`, and answers where it went.
    static func setAside(_ directory: URL, store: URL, at date: Date = .now) throws(Refusal) -> URL {
        let lock = try claim(store.path + ".writer-lock")
        // Closing the connection ends its transaction, which releases the lock.
        defer { sqlite3_close(lock) }
        let stamp = Int64(date.timeIntervalSince1970 * 1000)
        let aside = directory.deletingLastPathComponent()
            .appending(path: "\(directory.lastPathComponent).replaced-\(stamp)", directoryHint: .isDirectory)
        guard renamex_np(directory.path, aside.path, UInt32(RENAME_EXCL)) == 0 else { throw .notMoved }
        return aside
    }

    /// The core's claim: an exclusive transaction on the lock file, with no wait, on a connection that can write,
    /// since SQLite opens a file it cannot write read-only without saying so and grants that only a shared lock.
    private static func claim(_ path: String) throws(Refusal) -> OpaquePointer {
        let made = open(path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
        if made >= 0 { close(made) } else if errno != EEXIST { throw .notMoved }
        for _ in 0..<3 {
            var opened: OpaquePointer?
            guard sqlite3_open_v2(path, &opened, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK,
                let connection = opened
            else {
                sqlite3_close(opened)
                throw .notMoved
            }
            if sqlite3_db_readonly(connection, "main") != 0 {
                sqlite3_close(connection)
                continue
            }
            sqlite3_busy_timeout(connection, 0)
            switch sqlite3_exec(connection, "BEGIN EXCLUSIVE", nil, nil, nil) & 0xFF {
            case SQLITE_OK:
                return connection
            case SQLITE_BUSY, SQLITE_LOCKED:
                sqlite3_close(connection)
                throw .held
            default:
                sqlite3_close(connection)
                throw .notMoved
            }
        }
        throw .notMoved
    }
}
