import Foundation
import MarfaAPI
import Observation

/// Add a Connector: places an installed connector that runs on no machine. On a machine the Marfa knows it is only assigned,
/// so a link that machine is still waiting to use stands; on another machine the Marfa makes one with a one-time link, and the
/// sheet shows the command to paste there. The link gives that machine a key, so it lives only in this model: never logged,
/// never in a draft, never handed over, and gone when the sheet closes or the link ends. The app can't run a connector itself,
/// so there is no On This Mac.
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
        /// Nil once the link has ended, and for a machine whose link was made before this sheet.
        fileprivate(set) var link: ConnectorHostLink?
        /// Whether this sheet made a link for the machine, so a missing one has ended rather than been made elsewhere.
        fileprivate(set) var madeLink: Bool
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

    /// The link while it still works, checked at the moment it is asked for, so an ended link is never offered even before
    /// `endLinkWhenDue` drops it.
    func liveLink(at now: Date = .now) -> ConnectorHostLink? {
        guard let link = placed?.link, link.expires > now else { return nil }
        return link
    }

    /// What the owner pastes on the other machine: the plugins release's installer, given the link. Nil once the link has
    /// ended, and for a link the shell would read as more than one word, which the server never answers.
    var command: String? { liveLink().flatMap { Self.command(for: $0.link) } }

    static func command(for link: String) -> String? {
        guard let url = URL(string: link), ["https", "http"].contains(url.scheme), url.host() != nil,
            !link.unicodeScalars.contains(where: { $0 == "'" || $0 == "\\" || CharacterSet.whitespacesAndNewlines.contains($0) || CharacterSet.controlCharacters.contains($0) })
        else { return nil }
        return "curl -fsSL \(PluginRelease.latestAddress)/install-host.sh | sh -s -- '\(link)'"
    }

    /// Copy Command: copies the command only while its link works, concealed, and answers whether it did.
    @discardableResult func copyCommand(at now: Date = .now, to copy: @MainActor (String) -> Void = OwnerClipboard.copySecret) -> Bool {
        guard let command = liveLink(at: now).flatMap({ Self.command(for: $0.link) }) else {
            if placed?.link != nil { endLink() }
            return false
        }
        copy(command)
        return true
    }

    func add() async {
        guard canAdd, let summary = candidates.first(where: { $0.name == plugin }) else { return }
        isWorking = true
        error = nil
        let place = place
        let name = trimmedName
        // A machine made here that couldn’t be removed after the connector wasn’t placed on it.
        var kept: ConnectorHostInfo?
        do throws(OwnerFailure) {
            switch place {
            case .host(let id):
                // Only the assignment: a new link would end the one the machine may still be waiting to use.
                try await context.calls.assignConnector(summary.name, toHost: id)
                if let host = hosts.first(where: { $0.id == id }), !host.linked {
                    show(Placed(plugin: summary.name, title: summary.title, host: host, link: nil, madeLink: false))
                } else {
                    isWorking = false
                    closedWhileWorking = false
                }
            case .newMachine:
                let link = try await context.calls.createConnectorHost(named: name)
                do throws(OwnerFailure) {
                    try await context.calls.assignConnector(summary.name, toHost: link.host.id)
                } catch {
                    switch await settle(summary.name, on: link.host, after: error) {
                    case .held: break
                    case .removed: throw error
                    case .kept:
                        kept = link.host
                        throw error
                    }
                }
                show(Placed(plugin: summary.name, title: summary.title, host: link.host, link: link, madeLink: true))
            }
        } catch {
            isWorking = false
            let keptLine = kept.map { Self.keptLine($0, connector: summary.title) }
            if closedWhileWorking {
                closedWhileWorking = false
                if let keptLine { context.lateDraft(.told(title: String(localized: "Connector Machine Kept"), message: keptLine)) }
                if place == .newMachine, !name.isEmpty { context.lateDraft(Self.notAdded(name)) }
            } else {
                // A machine kept is all the owner needs: the failure's own words would say nothing was changed.
                self.error = keptLine ?? OwnerWording.line(error)
            }
            await context.learn(from: error)
            return
        }
        await placedOne(summary.name)
    }

    private enum Settled {
        /// The connector is on the machine after all: the failure hid an assignment that held.
        case held
        case removed
        /// The machine stands, and the owner is told how to remove it.
        case kept
    }

    /// After the assignment to the machine just made failed. A failure with no answer, or one that can't be read, may hide an
    /// assignment that held, so the machine is read again before anything. It is removed only when the server refused and
    /// the fresh read shows no connector on it; no other machine is ever removed.
    private func settle(_ plugin: String, on host: ConnectorHostInfo, after failure: OwnerFailure) async -> Settled {
        guard let fresh = try? await context.calls.connectorHost(host.id) else { return .kept }
        if fresh.connectors.contains(plugin) { return .held }
        guard Self.isRefusal(failure), fresh.connectors.isEmpty else { return .kept }
        do {
            try await context.calls.removeConnectorHost(host.id)
            return .removed
        } catch {
            return .kept
        }
    }

    /// Whether the server answered and turned the call down, so nothing it was asked happened.
    static func isRefusal(_ failure: OwnerFailure) -> Bool {
        switch failure {
        case .unreachable, .failed: false
        default: true
        }
    }

    private static func keptLine(_ host: ConnectorHostInfo, connector: String) -> String {
        String(localized: "“\(host.name)” was made, but the app couldn’t put \(connector) on it. If no connector runs on it, remove it in Terminal with marfa hosts remove \(host.id).")
    }

    private static func notAdded(_ name: String) -> OwnerDraft {
        .typed(title: String(localized: "Connector Not Added"), text: name)
    }

    /// Shows the command, or, where Settings closed while the call was under way, tells that the link can't be shown again.
    private func show(_ made: Placed) {
        isWorking = false
        if closedWhileWorking {
            closedWhileWorking = false
            if made.link != nil { context.lateDraft(Self.notShown(made)) }
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

    /// A new link for the machine, made only when the owner asks: it ends any link the machine had.
    func renewLink() async {
        guard let made = placed, liveLink() == nil, !isWorking else { return }
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
                placed?.madeLink = true
            }
        } catch {
            isWorking = false
            closedWhileWorking = false
            self.error = OwnerWording.line(error)
            await context.learn(from: error)
        }
    }

    /// What Settings closing tells about: a link on show is not handed over, only that it can't be shown again; a Machine
    /// Name typed for a connector not added is handed back. A call under way is told about when it ends.
    func takeDrafts() -> [OwnerDraft] {
        if isWorking {
            closedWhileWorking = true
            return []
        }
        defer { placed = nil }
        if let placed { return placed.link != nil ? [Self.notShown(placed)] : [] }
        return place == .newMachine && !trimmedName.isEmpty ? [Self.notAdded(trimmedName)] : []
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
