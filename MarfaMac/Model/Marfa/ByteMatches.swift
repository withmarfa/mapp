import Foundation
import Marfa

/// The package's per-file answers as the app's, one for each file in the order given.
///
/// A thrown error, or a list that does not line up with the files, is no answer for the whole batch: the add goes
/// ahead, since a failure is never read as "nothing holds these bytes". A file the package could not read is left
/// out, which is no answer for that file alone. An empty holder list is an answer that nothing holds the bytes.
nonisolated enum ByteMatches {
    static func answers(for files: [URL], lookup: @Sendable () async throws -> [Marfa.FileMatch]) async -> FileMatches {
        let matches: [Marfa.FileMatch]
        do {
            matches = try await lookup()
        } catch {
            return .noAnswer
        }
        guard matches.count == files.count else { return .noAnswer }
        var answers: [URL: FileMatchAnswer] = [:]
        for (file, match) in zip(files, matches) {
            guard case .held(_, let holders, let more) = match else { continue }
            answers[file] = .answered(
                holders.map { FileMatch(id: ItemID($0.id), title: $0.title ?? "") }, more: more)
        }
        return FileMatches(answers)
    }
}
