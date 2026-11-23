import AppKit
import SwiftUI

/// Marfa > Check for Updates…, off while a check runs. A view of its own, so the menu follows `canCheckForUpdates`.
private struct CheckForUpdatesButton: View {
    let updater: AppUpdater

    var body: some View {
        Button("Check for Updates…") { updater.checkForUpdates() }
            .disabled(!updater.canCheckForUpdates)
    }
}

/// Marfa > About Marfa: the standard About panel, with what the About page of Settings used to say, as its credits: what
/// the app is, and where to find the project, Marfa's documentation and the license.
struct AboutCommands: Commands {
    /// Nil in a build that does not update itself, which has no Check for Updates….
    let updater: AppUpdater?

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Marfa") {
                NSApp.activate()
                NSApp.orderFrontStandardAboutPanel(options: [.credits: Self.credits])
            }
            if let updater {
                CheckForUpdatesButton(updater: updater)
            }
        }
    }

    private static var credits: NSAttributedString {
        let credits = NSMutableAttributedString(
            string: String(localized: "An app for your Marfa server’s items.") + "\n",
            attributes: [.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize), .foregroundColor: NSColor.secondaryLabelColor])
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        credits.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: credits.length))
        let links: [(String, URL)] = [
            ("github.com/withmarfa/marfa-mac", AppLinks.source), ("docs.marfa.so", AppLinks.marfaDocumentation),
            (String(localized: "Apache-2.0"), AppLinks.license),
        ]
        for (index, link) in links.enumerated() {
            credits.append(NSAttributedString(
                string: link.0 + (index < links.count - 1 ? "  " : ""),
                attributes: [
                    .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize), .link: link.1, .paragraphStyle: paragraph,
                ]))
        }
        return credits
    }
}
