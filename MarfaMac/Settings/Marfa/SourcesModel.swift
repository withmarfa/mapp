import Foundation
import Marfa
import Observation

/// What the Sources page asks of the app: the sources as the server last named them, and one change to a source. Both are
/// the app's own terms, so a test scripts them.
struct SourceAccess {
    var rows: () -> [MarfaSourceRow]
    var refresh: () async -> Void
    var change: (String, MarfaSourceChange) async -> OwnerFailure?
    var marks: (String, MarfaMarkSet) -> [String]
}

/// The Sources page: the sources with their names and marks, and the rename and mark a source can change. A name or mark is
/// kept on the server for every app, so a change needs the server and is never queued; what it refuses is kept for the sheet
/// to show, with what was typed.
@Observable @MainActor final class SourcesModel: OwnerDraftHolding {
    enum Sheet: Hashable {
        case name(code: String)
        case mark(code: String)
    }

    private let access: SourceAccess
    let markSets: [MarfaMarkSet]

    private(set) var sheet: Sheet?
    var name = ""
    var search = ""
    var markSet: MarfaMarkSet
    private(set) var isWorking = false
    /// Why the last change was refused, until the next change.
    private(set) var failure: String?
    private(set) var hasLoaded = false
    /// Why the last change made from a source's menu was refused, shown above the list until the next one.
    private(set) var listFailure: OwnerFailure?

    init(access: SourceAccess, markSets: [MarfaMarkSet]) {
        self.access = access
        self.markSets = markSets
        markSet = markSets.first ?? MarfaMarkSet(id: "", title: "")
    }

    var rows: [MarfaSourceRow] { access.rows() }

    func row(_ code: String) -> MarfaSourceRow? { rows.first { $0.code == code } }

    func load() async {
        await access.refresh()
        hasLoaded = true
    }

    // MARK: The sheets

    func beginRename(_ code: String) {
        guard let row = row(code) else { return }
        name = row.name
        failure = nil
        sheet = .name(code: code)
    }

    func beginMark(_ code: String) {
        guard let row = row(code) else { return }
        search = ""
        failure = nil
        markSet = row.mark.flatMap { mark in markSets.first { mark.hasPrefix($0.id + ":") } } ?? markSets.first ?? markSet
        sheet = .mark(code: code)
    }

    func close() {
        guard !isWorking else { return }
        sheet = nil
        failure = nil
    }

    var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var openRow: MarfaSourceRow? {
        switch sheet {
        case .name(let code)?, .mark(let code)?: row(code)
        case nil: nil
        }
    }

    var canRename: Bool { !isWorking && !trimmedName.isEmpty && trimmedName != openRow?.name }
    var canUseDefaultName: Bool { !isWorking && openRow?.hasChosenName == true }
    var canRemoveMark: Bool { !isWorking && openRow?.mark != nil }
    var markChoices: [String] { Array(access.marks(search, markSet).prefix(60)) }

    // MARK: Changes

    /// A change made from a source's menu, with no sheet: the line is shown on the page's own refusal row.
    func useDefaultName(_ code: String) async { await changeFromMenu(.useDefaultName, for: code) }
    func removeMark(_ code: String) async { await changeFromMenu(.removeMark, for: code) }

    private func changeFromMenu(_ change: MarfaSourceChange, for code: String) async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        listFailure = await access.change(code, change)
    }

    func rename() async { await run(.rename(trimmedName), allowed: canRename) }
    func useDefaultName() async { await run(.useDefaultName, allowed: canUseDefaultName) }
    func choose(mark: String) async { await run(.setMark(mark), allowed: !isWorking) }
    func removeMark() async { await run(.removeMark, allowed: canRemoveMark) }

    private func run(_ change: MarfaSourceChange, allowed: Bool) async {
        guard allowed, let code = openRow?.code else { return }
        isWorking = true
        failure = nil
        defer { isWorking = false }
        if let refused = await access.change(code, change) {
            failure = OwnerWording.line(refused, on: .sources)
        } else {
            sheet = nil
        }
    }

    /// A name typed in the rename sheet and not kept goes back to the person when Settings closes.
    func takeDrafts() -> [OwnerDraft] {
        guard case .name(let code)? = sheet, trimmedName != row(code)?.name, !trimmedName.isEmpty else { return [] }
        defer { sheet = nil }
        return [.typed(title: String(localized: "Source Name Not Kept"), text: trimmedName)]
    }
}
