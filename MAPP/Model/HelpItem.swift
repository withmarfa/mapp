import Foundation

/// The Help menu's commands, the one list the menu and the command palette are both made from.
nonisolated enum HelpItem: CaseIterable {
    case help, keyboardShortcuts, whatsNew, marfaDocumentation, reportAProblem

    var title: LocalizedStringResource {
        switch self {
        case .help: "MAPP Help"
        case .keyboardShortcuts: "Keyboard Shortcuts"
        case .whatsNew: "What’s New in MAPP"
        case .marfaDocumentation: "Marfa Documentation"
        case .reportAProblem: "Report a Problem…"
        }
    }

    var systemImage: String {
        switch self {
        case .help: "questionmark.circle"
        case .keyboardShortcuts: "keyboard"
        case .whatsNew: "sparkles"
        case .marfaDocumentation: "book"
        case .reportAProblem: "exclamationmark.bubble"
        }
    }

    /// Where the command goes in the browser, or nil for the one that opens a window of the app's own.
    var url: URL? {
        switch self {
        case .help: AppLinks.help
        case .keyboardShortcuts: nil
        case .whatsNew: AppLinks.releases
        case .marfaDocumentation: AppLinks.marfaDocumentation
        case .reportAProblem: AppLinks.reportFromThisMac
        }
    }

    /// Whether a rule separates it from the commands above it in the menu: the app's own help comes first, then Marfa's
    /// documentation and the report.
    var startsGroup: Bool { self == .marfaDocumentation }
}
