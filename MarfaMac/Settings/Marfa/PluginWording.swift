import Foundation
import MarfaAPI

/// The words of the Plugins page: what a plugin adds, what removing one did and what a refusal says.
nonisolated enum PluginWording {
    static func list(_ names: [String]) -> String { names.formatted(.list(type: .and)) }

    /// "the type Spikes", "the types Tickets and Spikes".
    static func addedTypes(_ titles: [String]) -> String {
        titles.count == 1
            ? String(localized: "the type \(titles[0])") : String(localized: "the types \(list(titles))")
    }

    static func addedEdgeTypes(_ count: Int) -> String {
        count == 1 ? String(localized: "an edge type") : String(localized: "\(count) edge types")
    }

    /// What an update line says it adds, always ending with what it never does.
    static func updateLine(adds: [String]) -> String {
        guard !adds.isEmpty else { return String(localized: "A newer version. Nothing is removed.") }
        return String(localized: "Adds \(list(adds)). Nothing is removed.")
    }

    /// What the server answered to a removal: the connector that stopped with its settings, secrets and mapping, what its
    /// source keeps, and the types that stay with their items.
    static func removed(_ answer: PluginRemoval, title: String) -> String {
        var parts = [String(localized: "Removed \(title) \(answer.version).")]
        if answer.removedConnector {
            parts.append(
                String(localized: "Its connector stopped, and its settings, secrets and saved mapping are gone, with any rewrite it asked for."))
        }
        if let kept = answer.keptConnector, let line = keptSource(kept) { parts.append(line) }
        let types = answer.keptTypes.count
        let edges = answer.keptEdgeTypes.count
        switch (types, edges) {
        case (0, 0): parts.append(String(localized: "Nothing it brought is left to keep."))
        case (1, 0): parts.append(String(localized: "Its type and its items stay."))
        case (_, 0): parts.append(String(localized: "Its \(types) types and their items stay."))
        case (0, 1): parts.append(String(localized: "Its edge type stays."))
        case (0, _): parts.append(String(localized: "Its \(edges) edge types stay."))
        default:
            let first = types == 1 ? String(localized: "Its type") : String(localized: "Its \(types) types")
            let second = edges == 1 ? String(localized: "its edge type") : String(localized: "its \(edges) edge types")
            parts.append(String(localized: "\(first), \(second) and their items stay."))
        }
        return parts.joined(separator: " ")
    }

    /// What a removed connector's source keeps, or nil where it keeps neither a state nor an agreement.
    static func keptSource(_ kept: PluginRemoval.KeptConnector) -> String? {
        let source = kept.source
        let agreements = kept.agreements
        switch (kept.state, agreements) {
        case (false, 0): return nil
        case (true, 0): return String(localized: "Its source \(source) keeps its state.")
        case (true, 1): return String(localized: "Its source \(source) keeps its state and 1 agreement.")
        case (true, _): return String(localized: "Its source \(source) keeps its state and \(agreements) agreements.")
        case (false, 1): return String(localized: "Its source \(source) keeps its 1 agreement.")
        case (false, _): return String(localized: "Its source \(source) keeps its \(agreements) agreements.")
        }
    }

    /// Why a call about a plugin was refused, in one place for the row that shows it.
    static func line(_ failure: PluginFailure, title: String? = nil) -> String {
        switch failure {
        case .owner(let failure): OwnerWording.line(failure)
        case .releaseUnreadable(let line): line
        case .digestMismatch:
            String(localized: "What the release served isn’t what it lists, so the app used none of it.")
        case .needsNewerServer(let marfa, let server):
            if let title { String(localized: "\(title) needs Marfa \(marfa) or later. This server runs \(server).") } else {
                String(localized: "This plugin needs Marfa \(marfa) or later. This server runs \(server).")
            }
        case .carriesGuidance:
            String(localized: "This Marfa takes a plugin that carries guidance only from the command line for now.")
        case .releaseChanged:
            String(localized: "The release changed since it was read, so the app used none of it. Try again to read it.")
        case .canceled: ""
        }
    }

    /// The line for a plugin's head: its version, its maker and the oldest Marfa it needs.
    static func head(version: String, maker: String, marfa: String) -> String {
        String(localized: "Version \(version), made by \(maker). Needs Marfa \(marfa) or later.")
    }

    /// The direction of a kind a connector brings, in words.
    static func direction(_ direction: String) -> String {
        switch direction {
        case "in": String(localized: "Brings in")
        case "out": String(localized: "Sends out")
        default: String(localized: "Brings in and sends out")
        }
    }
}
