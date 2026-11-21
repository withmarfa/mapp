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

    /// How a part stands, from what the server says needs attention. A health concern names its component exactly
    /// (`database` and `database_write` are Database, `disk` is Disk, `blob_storage` is Files), and is down where the server's
    /// own title says so ("<part> is down"); one the model cannot place shows on no row and stays under Needs Attention. Where
    /// the server could not check health, no part is shown as working.
    func health(of component: Component) -> HealthPart {
        let references: Set<String> =
            switch component {
            case .database: ["database", "database_write"]
            case .disk: ["disk"]
            case .files: ["blob_storage"]
            }
        let named = concerns.filter { $0.kind == .health && references.contains($0.reference) }
        if named.contains(where: { $0.title.hasSuffix(" is down") }) { return HealthPart(condition: .down) }
        if !named.isEmpty { return HealthPart(condition: .degraded) }
        return HealthPart(condition: healthUnavailable ? .unknown : .ok)
    }

    /// Whether the server reported that it could not check health: an `unavailable` concern names the check as "Health".
    private var healthUnavailable: Bool {
        concerns.contains { $0.kind == .unavailable && $0.reference == "Health" }
    }

    /// The backups row, from the backup concerns the model can place. A folder notice or a reference it does not know is told
    /// under Needs Attention and never makes the row "Failing": that word is for a failed store or run.
    var backups: BackupsHealth {
        let references = Set(concerns.filter { $0.kind == .backup }.map(\.reference))
        let state: BackupsHealth.State =
            if !references.isDisjoint(with: ["store", "run"]) { .failing }
            else if !references.isDisjoint(with: ["incomplete", "parts_damaged"]) { .incomplete }
            else if !references.isDisjoint(with: ["no_backup_destination", "turned_off"]) { .off }
            else if healthUnavailable { .unknown }
            else { .ok }
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
