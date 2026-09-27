import WebKit

extension WKWebView {
    /// Leaves the web view clear, so the window's own background shows through a page whose background is
    /// transparent, and the page and the toolbar above it read as one surface, as in Mail. WebKit offers this
    /// only through a key that is not public API, so it is set only while WebKit answers to it, and the page is
    /// marked with `window-background` only then, keeping its own background otherwise. Call before loading.
    func showsWindowBackground() {
        guard responds(to: NSSelectorFromString("_setDrawsBackground:")) else { return }
        setValue(false, forKey: "drawsBackground")
        configuration.userContentController.addUserScript(WKUserScript(
            source: "document.documentElement.classList.add('window-background')",
            injectionTime: .atDocumentStart, forMainFrameOnly: true
        ))
    }
}
