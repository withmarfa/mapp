import Foundation
import Testing

@testable import MAPP

@MainActor
struct ItemWindowsTests {
    private func ids(_ count: Int) -> [ItemID] { (0..<count).map { _ in ItemID(rawValue: UUID().uuidString) } }

    private func run(_ ids: [ItemID], answer: Bool) -> (asked: [Int], opened: [ItemID]) {
        var asked: [Int] = []
        var opened: [ItemID] = []
        ItemWindows.open(
            ids,
            asking: { count, proceed in
                asked.append(count)
                if answer { proceed() }
            },
            opening: { opened.append($0) })
        return (asked, opened)
    }

    @Test func tenWindowsOpenWithoutAsking() {
        let list = ids(10)
        let result = run(list, answer: false)
        #expect(result.asked.isEmpty)
        #expect(result.opened == list)
    }

    @Test func moreThanTenAskOnceNamingTheCount() {
        let list = ids(11)
        let result = run(list, answer: true)
        #expect(result.asked == [11])
        #expect(result.opened == list)
    }

    @Test func decliningOpensNothing() {
        let result = run(ids(25), answer: false)
        #expect(result.asked == [25])
        #expect(result.opened.isEmpty)
    }

    @Test func nothingToOpenDoesNotAsk() {
        let result = run([], answer: true)
        #expect(result.asked.isEmpty)
        #expect(result.opened.isEmpty)
    }
}
