import SwiftUI

/// Board sizes in points at Actual Size. Page roles scale with the page body and interface roles with the UI.
nonisolated enum Typography {
    static let body = 13
    static let primary = 13
    static let chip = 12.0
    static let caption = 11.0
    static let title = 24.7
    static let titleTracking = -0.022
    static let readerBody = 14.6
    static let codeBlockRatio = 0.867
    static let systemCSS = "-apple-system, system-ui, sans-serif"
    static let monoCSS = "ui-monospace, 'SF Mono', Menlo, monospace"

    static func pageSize(_ role: Double, at textSize: CGFloat) -> CGFloat {
        textSize * role / Double(body)
    }

    static func headingSize(_ level: Int) -> Double {
        switch level {
        case 1: 20
        case 2: 17.5
        case 3: 15
        default: Double(body)
        }
    }
}
