import Foundation
import Testing
@testable import MAPP

/// Times what the views ask of a large library. The ceilings are far above what a Mac takes, so they catch a
/// read that has turned quadratic, which took seconds here, rather than ordinary noise; the timings are kept for
/// comparing builds.
@Suite(.serialized)
struct LibraryPerformanceTests {
    static let noteCount = 3_000
    static let fileCount = 200
    static let folders = (1...5).map { StoredFolder(id: .mint(), name: "Folder \($0)") }
    static let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    /// Projects, tickets under them, and notes that link to one another, spread over the Inbox and five folders,
    /// with a few favorites, a few in the trash and some files beside them.
    static func makeLibrary() async -> NoteLibrary {
        var stored = StoredLibrary()
        stored.folders = folders
        let paragraph = String(repeating: "Some words that make a paragraph of an ordinary length. ", count: 12)
        for index in 0..<noteCount {
            let title = "Note \(index)"
            var front: [String] = []
            switch index % 10 {
            case 0: front = ["type: aic.project"]
            case 1...5: front = ["type: aic.ticket.task", "child-of: \"[[Note \(index / 10 * 10)]]\"", "status: pending"]
            default: break
            }
            if index % 50 == 0 { front.append("tags: [favorite]") }
            let header = front.isEmpty ? "" : "---\n" + front.joined(separator: "\n") + "\n---\n"
            let body = "# \(title)\n\n\(paragraph)\n\nSee [[Note \((index + 7) % noteCount)]].\n\n\(paragraph)\n"
            let directory = index % 6 == 0 ? "" : folders[index % 5].name + "/"
            let note = StoredNote(
                id: .mint(), path: "\(directory)\(title).md", text: header + body,
                created: start + Double(index), modified: start + Double(index * 2))
            if index % 100 == 99 {
                stored.trash.append(TrashedNote(id: UUID(), note: note, trashed: start + 1_000_000))
            } else {
                stored.notes.append(note)
            }
        }
        let extensions = ["png", "pdf", "txt", "jpg"]
        for index in 0..<fileCount {
            let directory = index % 3 == 0 ? "" : folders[index % 5].name + "/"
            stored.files.append(StoredFile(
                id: .mint(), path: "\(directory)File \(index).\(extensions[index % 4])",
                created: start + Double(index), modified: start + Double(index), byteCount: 1_024))
        }
        let store = RecordingStore()
        store.stored = stored
        let library = NoteLibrary(loadingFrom: store, defaults: nil, now: { start + 1_000_000 })
        await library.load()
        return library
    }

    /// The median of several runs, in milliseconds, after one run to warm caches as a running app has.
    static func measure(runs: Int = 7, _ body: () -> Void) -> Double {
        body()
        var times: [Double] = []
        for _ in 0..<runs {
            let clock = ContinuousClock()
            let elapsed = clock.measure(body)
            times.append(Double(elapsed.components.attoseconds) / 1e15 + Double(elapsed.components.seconds) * 1e3)
        }
        return times.sorted()[runs / 2]
    }

    @Test func readingALargeLibraryStaysFast() async throws {
        let library = await Self.makeLibrary()
        let browser = Browser()
        let order = NoteOrder()
        let edited = try #require(library.notes.first { !$0.isDeleted && $0.title == "Note 1" }).id
        let places: [SidebarItem] = [.inbox, .allNotes, .favorites, .files, .recentlyDeleted]
            + WorkbenchSchema.types.map { .itemType($0.id) } + Self.folders.map { .folder($0.id) }

        func readAllItems() {
            let sections = browser.sections(in: library, order: order, now: library.now())
            #expect(sections.reduce(0) { $0 + $1.items.count } == Self.noteCount - Self.noteCount / 100 + Self.fileCount)
        }

        let all = Self.measure(readAllItems)
        // The views hold the library as `any ItemLibrary`; reading through it should cost what reading it directly does.
        let existential: any ItemLibrary = library
        let direct = Self.measure { #expect(!library.items(in: .allNotes).isEmpty) }
        let throughProtocol = Self.measure { #expect(!existential.items(in: .allNotes).isEmpty) }
        let type = Self.measure {
            #expect(library.items(in: .itemType("aic.ticket.task")).count == Self.noteCount / 2)
        }
        var keystroke = 0
        let edit = Self.measure {
            keystroke += 1
            library.updateBody(of: edited, to: "# Note 1\n\nTyped \(keystroke)\n\nSee [[Note 8]].\n")
            readAllItems()
            #expect(library.item(edited) != nil)
            #expect(!library.relationships(for: edited).isEmpty)
        }
        let counts = Self.measure {
            #expect(places.reduce(0) { $0 + library.count(in: $1) } > 0)
        }
        let countsAfterEdit = Self.measure {
            keystroke += 1
            library.updateBody(of: edited, to: "# Note 1\n\nTyped \(keystroke)\n\nSee [[Note 8]].\n")
            #expect(places.reduce(0) { $0 + library.count(in: $1) } > 0)
        }

        let timings = [
            ("items in All Notes", all), ("All Notes read directly", direct), ("All Notes read through ItemLibrary", throughProtocol),
            ("items of a type", type),
            ("one body edit, then the list, the item and its relationships", edit), ("sidebar counts", counts),
            ("one body edit, then the sidebar counts", countsAfterEdit)
        ]
        let report = timings.map { "\($0): \(String(format: "%.3f", $1)) ms\n" }.joined()
        print(report, terminator: "")
        // The test runner keeps no standard output, so the timings are also left where a person can read them.
        try? Data(report.utf8).write(to: URL.temporaryDirectory.appending(path: "MAPP-performance.txt"))

        #expect(all < 50)
        #expect(throughProtocol < 50)
        #expect(type < 50)
        #expect(edit < 100)
        #expect(counts < 50)
        #expect(countsAfterEdit < 50)
    }
}
