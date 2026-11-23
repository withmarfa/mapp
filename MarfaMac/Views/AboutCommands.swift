import AppKit
import SwiftUI

/// MAPP > About MAPP: the standard About panel, with what the About page of Settings used to say, as its credits: what
/// the app is, and where to find the project, Marfa's documentation and the license.
struct AboutCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About MAPP") {
                NSApp.activate()
                NSApp.orderFrontStandardAboutPanel(options: [.credits: Self.credits])
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
            ("github.com/withmarfa/mapp", AppLinks.source), ("docs.marfa.so", AppLinks.marfaDocumentation),
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
