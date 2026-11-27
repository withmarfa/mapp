import Foundation
import Marfa

/// The package's per-file answers as the app's, one for each file in the order given.
///
/// A thrown error or a result count that differs from the file count leaves the whole batch unanswered.
/// An unreadable file keeps its position and leaves only that file unanswered. An empty holder list means
/// the server found no readable item holding those bytes.
nonisolated enum ByteMatches {
    static func answers(for files: [URL], lookup: @Sendable () async throws -> [Marfa.FileMatch]) async -> FileMatches {
        let matches: [Marfa.FileMatch]
        do {
            matches = try await lookup()
        } catch {
            return .noAnswer
        }
        guard matches.count == files.count else { return .noAnswer }
        var answers = Array(repeating: FileMatchAnswer.noAnswer, count: files.count)
        for (index, match) in matches.enumerated() {
            guard case .held(_, let holders, let more) = match else { continue }
            answers[index] = .answered(
                holders.map { FileMatch(id: ItemID($0.id), title: $0.title ?? "") }, more: more)
        }
        return FileMatches(answers)
    }
}
