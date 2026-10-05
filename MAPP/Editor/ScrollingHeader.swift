import AppKit
import SwiftUI
import WebKit

/// Native controls overlay a WebKit document. Unhandled wheel events must reach that document instead
/// of the window: the controls and page are siblings, so their default responder chains do not meet.
struct ScrollingHeader<Content: View>: NSViewControllerRepresentable {
    let webView: WKWebView
    @ViewBuilder let content: () -> Content

    func makeNSViewController(context: Context) -> HeaderHostingController {
        let controller = HeaderHostingController(rootView: AnyView(content().environment(\.self, context.environment)))
        controller.safeAreaRegions = []
        controller.scrollingView = webView
        return controller
    }

    func updateNSViewController(_ controller: HeaderHostingController, context: Context) {
        controller.rootView = AnyView(content().environment(\.self, context.environment))
        controller.scrollingView = webView
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsViewController controller: HeaderHostingController, context: Context) -> CGSize? {
        guard let width = proposal.width else { return nil }
        return controller.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude))
    }
}

final class HeaderHostingController: NSHostingController<AnyView> {
    weak var scrollingView: WKWebView?

    override func scrollWheel(with event: NSEvent) {
        if let scrollingView { scrollingView.scrollWheel(with: event) }
        else { super.scrollWheel(with: event) }
    }
}
