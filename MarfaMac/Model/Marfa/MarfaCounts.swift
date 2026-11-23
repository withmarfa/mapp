import Foundation
import Marfa

/// Maps the app's count queries to the working copy and leaves unanswered items out of the result.
nonisolated struct MarfaCounts: Sendable {
    /// The package's call behind one closure, which a test answers.
    typealias Ask = @Sendable ([String], Counted) async throws -> [Marfa.ItemCount]

    let ask: Ask

    init(ask: @escaping Ask) {
        self.ask = ask
    }

    init(copy: WorkingCopy) {
        ask = { ids, counted in try await MarfaEngine.asking { try await copy.counts(of: ids, counted) } }
    }

    @concurrent func counts(of ids: [ItemID], _ query: CountQuery) async throws -> [ItemID: ItemCountAnswer] {
        let answered: [Marfa.ItemCount]
        do {
            answered = try await ask(ids.map(\.rawValue), Self.counted(query))
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw ItemCountUnavailable()
        }
        var answers: [ItemID: ItemCountAnswer] = [:]
        let asked = Set(ids)
        for count in answered where asked.contains(ItemID(count.id)) {
            answers[ItemID(count.id)] = Self.answer(count)
        }
        return answers
    }

    static func counted(_ query: CountQuery) -> Counted {
        switch query {
        case .children: .backref(edgeType: MarfaMapping.parentEdge)
        case .members: .edge(edgeType: MarfaMapping.collectionEdge)
        case .rows(let table): .rows(table: table)
        }
    }

    static func answer(_ count: Marfa.ItemCount) -> ItemCountAnswer {
        ItemCountAnswer(
            total: count.total,
            groups: count.statusGroups.map {
                ItemCountAnswer.Groups(
                    notStarted: $0.notStarted, inProgress: $0.inProgress, completed: $0.completed, canceled: $0.canceled)
            })
    }
}
