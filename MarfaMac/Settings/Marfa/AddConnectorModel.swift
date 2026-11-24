import Foundation
import MarfaAPI
import Observation

/// Add a Connector: places an installed connector that runs on no machine. On a machine already linked it is only assigned;
/// on another machine the Marfa makes one with a one-time link, and the sheet shows the command to paste there. The link
/// gives that machine a key, so it lives only in this model: never logged, never in a draft, never handed over, and gone
/// when the sheet closes or the link ends. The app can't run a connector itself, so there is no On This Mac.
@Observable @MainActor final class AddConnectorModel {
    enum Place: Hashable {
        /// A machine not linked yet, which the Marfa makes.
        case newMachine
        case host(String)
    }

    /// A connector placed on a machine that still has to be linked.
    struct Placed {
        let plugin: String
        let title: String
        let host: ConnectorHostInfo
        /// Nil once the link has ended.
        fileprivate(set) var link: ConnectorHostLink?
    }

    private let context: OwnerContext
    /// The connectors no machine runs, which the sheet offers.
    let candidates: [PluginConnectorSummary]
    let hosts: [ConnectorHostInfo]
    private let placedOne: (String) async -> Void
    var plugin: String
    var place: Place = .newMachine
    var machineName = ""
    private(set) var error: String?
    private(set) var isWorking = false
    private(set) var placed: Placed?
    /// Set when Settings closes while a call is under way, so what it made is told about when it ends.
    private var closedWhileWorking = false

    /// `placedOne` is told the plugin whose connector now has a machine, so the page reads it again.
    init(context: OwnerContext, candidates: [PluginConnectorSummary], hosts: [ConnectorHostInfo], placedOne: @escaping (String) async -> Void) {
        self.context = context
        self.candidates = candidates
        self.hosts = hosts
        self.placedOne = placedOne
        plugin = candidates.first?.name ?? ""
    }

    private var trimmedName: String { machineName.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// The server takes a name of 1 to 100 characters.
    var canAdd: Bool {
        guard !isWorking, placed == nil, candidates.contains(where: { $0.name == plugin }) else { return false }
        switch place {
        case .newMachine: return (1...100).contains(trimmedName.count)
        case .host(let id): return hosts.contains { $0.id == id }
        }
    }

    /// What the owner pastes on the other machine: the plugins release's installer, given the link. Nil for a link the shell
    /// would read as more than one word, which the server never answers.
    var command: String? { placed?.link.flatMap { Self.command(for: $0.link) } }

    static func command(for link: String) -> String? {
        guard let url = URL(string: link), ["https", "http"].contains(url.scheme), url.host() != nil,
            !link.unicodeScalars.contains(where: { $0 == "'" || $0 == "\\" || CharacterSet.whitespacesAndNewlines.contains($0) || CharacterSet.controlCharacters.contains($0) })
        else { return nil }
        return "curl -fsSL \(PluginRelease.latestAddress)/install-host.sh | sh -s -- '\(link)'"
    }

    func add() async {
        guard canAdd, let summary = candidates.first(where: { $0.name == plugin }) else { return }
        isWorking = true
        error = nil
        do throws(OwnerFailure) {
            switch place {
            case .host(let id):
                if hosts.first(where: { $0.id == id })?.linked == true {
                    try await context.calls.assignConnector(summary.name, toHost: id)
                    isWorking = false
                    closedWhileWorking = false
                } else {
                    // A machine never linked gets a fresh link, which ends the one it had.
                    let link = try await context.calls.linkConnectorHost(id)
                    try await context.calls.assignConnector(summary.name, toHost: id)
                    show(Placed(plugin: summary.name, title: summary.title, host: link.host, link: link))
                }
            case .newMachine:
                let link = try await context.calls.createConnectorHost(named: trimmedName)
                do throws(OwnerFailure) {
                    try await context.calls.assignConnector(summary.name, toHost: link.host.id)
                } catch {
                    // A machine made for a connector that couldn't be placed on it would only stand in the list.
                    try? await context.calls.removeConnectorHost(link.host.id)
                    throw error
                }
                show(Placed(plugin: summary.name, title: summary.title, host: link.host, link: link))
            }
        } catch {
            isWorking = false
            if closedWhileWorking {
                closedWhileWorking = false
            } else {
                self.error = OwnerWording.line(error)
            }
            await context.learn(from: error)
            return
        }
        await placedOne(summary.name)
    }

    /// Shows the command, or, where Settings closed while the call was under way, tells that the link can't be shown again.
    private func show(_ made: Placed) {
        isWorking = false
        if closedWhileWorking {
            closedWhileWorking = false
            context.lateDraft(Self.notShown(made))
        } else {
            placed = made
        }
    }

    /// Waits until the link ends and drops it, so an ended link is never offered. The sheet runs it while the link shows.
    func endLinkWhenDue() async {
        guard let expires = placed?.link?.expires else { return }
        let left = expires.timeIntervalSinceNow
        if left > 0 { try? await Task.sleep(for: .seconds(left)) }
        guard !Task.isCancelled, placed?.link?.expires == expires else { return }
        endLink()
    }

    /// Drops the link once it has ended, so the sheet offers New Link.
    func endLink() { placed?.link = nil }

    /// A new link for the machine just made, once its first one has ended.
    func renewLink() async {
        guard let made = placed, made.link == nil, !isWorking else { return }
        isWorking = true
        error = nil
        do {
            let link = try await context.calls.linkConnectorHost(made.host.id)
            isWorking = false
            if closedWhileWorking {
                closedWhileWorking = false
                context.lateDraft(Self.notShown(made))
            } else {
                placed?.link = link
            }
        } catch {
            isWorking = false
            closedWhileWorking = false
            self.error = OwnerWording.line(error)
            await context.learn(from: error)
        }
    }

    /// What Settings closing tells about: a link on show is not handed over, only that it can't be shown again. A call under
    /// way is told about when it ends.
    func takeDrafts() -> [OwnerDraft] {
        if isWorking {
            closedWhileWorking = true
            return []
        }
        defer { placed = nil }
        guard let placed, placed.link != nil else { return [] }
        return [Self.notShown(placed)]
    }

    private static func notShown(_ placed: Placed) -> OwnerDraft {
        .told(
            title: String(localized: "Connector Link Not Shown Again"),
            message: String(localized: "\(placed.title) is set to run on “\(placed.host.name)”, and its one-time link can’t be shown again. If you didn’t paste its command there, choose No Machine on \(placed.title)’s page, then add it again on “\(placed.host.name)”."))
    }

    /// Drops the link, which nothing keeps.
    func close() {
        placed = nil
        error = nil
    }
}
