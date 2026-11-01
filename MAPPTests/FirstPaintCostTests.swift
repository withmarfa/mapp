import Foundation
import Marfa
import Testing
@testable import MAPP

/// What asking the core for every item's name and preview costs a large library's first paint, over a real working
/// copy in a temporary folder: no server is involved. Run it with the Measure test plan. It prints one
/// `PAINT|<name>|<value>|<unit>` line per number and checks only that each step reached its end: the numbers are
/// for a person to read, never a gate. `MAPP_MEASURE_NOTES` sets how many notes the copy holds (20000 by default).
@MainActor
@Suite(.tags(.measure), .enabled(if: ProcessInfo.processInfo.environment["MAPP_MEASURE"] != nil), .serialized)
struct FirstPaintCostTests {
    private static func ms(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
    }

    private func line(_ name: String, _ duration: Duration) { line(name, Self.ms(duration)) }

    private func line(_ name: String, _ value: Double, _ unit: String = "ms") {
        print("PAINT|\(name)|\(String(format: unit == "count" ? "%.0f" : "%.1f", value))|\(unit)")
    }

    private static func body(_ index: Int) -> String {
        let paragraph = "A paragraph of **ordinary** writing with a [[link]] and `code`, number \(index), long enough to be real. "
        return "# Note \(index)\n\n" + String(repeating: paragraph, count: 30)
    }

    @Test(.timeLimit(.minutes(10)))
    func displaysAgainstTheFirstPaint() async throws {
        let count = Int(ProcessInfo.processInfo.environment["MAPP_MEASURE_NOTES"] ?? "") ?? 20_000
        let store = try TemporaryMarfaCopy()
        defer { store.remove() }
        let copy = try await store.open()
        for index in 0..<count {
            _ = try await copy.items.create(
                Draft(type: "core.note", properties: ["title": .string("Note \(index)"), "body": .string(Self.body(index))], id: ItemID.mint().rawValue))
        }
        let rows = try await copy.items.list(ListFilters(allStates: true)).rows
        #expect(rows.count == count)
        line("notes", Double(rows.count), "count")
        line("bodyBytes", Double(rows.first?.properties["body"]?.string?.utf8.count ?? 0), "count")

        let clock = ContinuousClock()
        let whole = try await clock.measure { _ = try await copy.items.displays(of: rows) }
        line("displaysOneCall", whole)
        let batch = MarfaEngine.displayBatch
        if batch < rows.count {
            var longest = Duration.zero
            let chunked = try await clock.measure {
                for start in stride(from: 0, to: rows.count, by: batch) {
                    let one = try await clock.measure { _ = try await copy.items.displays(of: Array(rows[start..<min(rows.count, start + batch)])) }
                    longest = max(longest, one)
                }
            }
            line("displaysChunked", chunked)
            line("displaysLongestChunk", longest)
        }

        let source = MarfaSource(copy: copy, connection: SampleLibrary.connection)
        let log = ChangeLog(source)
        let painted = clock.now
        source.events.yield(.paint)
        let snapshot = try #require(await log.wait(for: .seconds(300)) { $0.snapshot != nil }?.snapshot)
        line("firstPaint", clock.now - painted)
        #expect(snapshot.items.count == count)
        #expect(snapshot.items.first?.name != nil)
        await source.close()
    }
}
