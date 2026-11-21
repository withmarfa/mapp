import Foundation
import Marfa
import Observation

/// What the Overview reads of the server: what needs the owner's attention, and how the server stands. The app keeps one, so
/// the sidebar's badge is its count whichever page is shown. A server refusal for want of a permission shows the page's
/// Needs a Permission state and has the grants read again.
@Observable @MainActor final class OverviewModel {
    private let context: OwnerContext

    private(set) var concerns: [AttentionConcern] = []
    private(set) var reading: InstanceReading?
    private(set) var failure: OwnerFailure?
    private(set) var isLoading = false
    private(set) var hasLoaded = false

    init(context: OwnerContext) {
        self.context = context
    }

    /// What the sidebar's badge counts: the server's concerns, not MAPP's own missing permissions.
    var attentionCount: Int { concerns.count }

    // MARK: Health

    enum Component { case database, disk, files }

    /// How a part stands, from what the server says needs attention: a health concern names the part it is about, and the concern itself
    /// is told under Needs Attention. A part with none is working. The server's health has no operation in the package, so this is all MAPP can read.
    func health(of component: Component) -> HealthPart {
        let words: [String] =
            switch component {
            case .database: ["database"]
            case .disk: ["disk"]
            case .files: ["blob", "file"]
            }
        let concern = concerns.first { item in
            item.kind == .health && words.contains { item.reference.localizedCaseInsensitiveContains($0) }
        }
        return HealthPart(condition: concern == nil ? .ok : .degraded)
    }

    var backups: BackupsHealth {
        let concern = concerns.first { $0.kind == .backup }
        let state: BackupsHealth.State =
            switch concern?.reference {
            case nil: .ok
            case "no_backup_destination", "turned_off": .off
            case "incomplete", "parts_damaged": .incomplete
            default: .failing
            }
        return BackupsHealth(state: state, lastBackup: reading?.lastBackup)
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer {
            isLoading = false
            hasLoaded = true
        }
        do {
            concerns = try await context.calls.attention()
            failure = nil
        } catch {
            failure = error
            await context.learn(from: error)
            return
        }
        reading = try? await context.calls.reading()
    }

    /// Forgets what was read, such as when another server is opened.
    func reset() {
        concerns = []
        reading = nil
        failure = nil
        hasLoaded = false
    }
}
