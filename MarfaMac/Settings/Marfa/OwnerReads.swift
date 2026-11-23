import Foundation

/// How many reads a page may have in flight at once when it fills in what each row says.
nonisolated let ownerReadsAtOnce = 4

/// Reads once for each item, at most `ownerReadsAtOnce` at a time, and hands each answer to `take` on the main actor as
/// it arrives. A read that throws is the read's own to turn into a value.
@MainActor func readEach<Item: Sendable, Answer: Sendable>(
    of items: [Item], read: @escaping @Sendable (Item) async -> Answer, take: (Item, Answer) async -> Void
) async {
    await withTaskGroup(of: (Int, Answer).self) { group in
        var next = 0
        func start() {
            guard next < items.count else { return }
            let index = next
            let item = items[index]
            next += 1
            group.addTask { (index, await read(item)) }
        }
        for _ in 0..<min(ownerReadsAtOnce, items.count) { start() }
        while let (index, answer) = await group.next() {
            await take(items[index], answer)
            start()
        }
    }
}
