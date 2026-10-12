import AppKit
import Testing
import WebKit
@testable import MAPP

@Suite(.serialized)
struct WebViewContainerTests {
    @Test func webViewFollowsGrowAndShrinkBeforeAnotherLayoutPass() {
        let webView = WKWebView()
        let container = EditorContainer(webView: webView)
        container.frame = NSRect(x: 0, y: 0, width: 700, height: 600)
        container.topInset = 44
        let bar = NSView(frame: NSRect(x: 0, y: 0, width: 700, height: 32))
        container.findBarView = bar
        container.isFindBarVisible = true
        container.layoutSubtreeIfNeeded()
        let top = webView.frame.minY
        let bottom = container.bounds.height - webView.frame.maxY
        for size in [NSSize(width: 980, height: 800), NSSize(width: 330, height: 240), NSSize(width: 720, height: 610)] {
            container.setFrameSize(size)
            #expect(webView.frame.width == size.width)
            #expect(webView.frame.minY == top)
            #expect(webView.frame.maxY == size.height - bottom)
            #expect(bar.frame.width == size.width)
            #expect(bar.frame.height == 32)
        }
        container.layoutSubtreeIfNeeded()
        #expect(webView.obscuredContentInsets.top == 76 || webView.frame.minY == 76)
        container.isFindBarVisible = false
        container.layoutSubtreeIfNeeded()
        #expect(webView.obscuredContentInsets.top == 44 || webView.frame.minY == 44)
    }
}
