import AppKit
import OSLog
import WebKit

private let log = Telemetry.logger(.editor)

extension EditorController: WKNavigationDelegate {
    /// The page never navigates: a link opens in the browser on Command-click, and nothing else loads but the
    /// frame a PDF the item embeds shows in.
    func webView(
        _ webView: WKWebView,
        decidePolicyFor action: WKNavigationAction,
        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
    ) {
        let isEmbed = action.targetFrame?.isMainFrame == false && action.request.url?.scheme == EmbeddedFiles.scheme
        decisionHandler(action.request.url == pageURL || isEmbed ? .allow : .cancel)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        log.error("navigation failed: \(error.localizedDescription)")
        pageFailedToLoad(navigation, error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        log.error("load failed: \(error.localizedDescription)")
        pageFailedToLoad(navigation, error)
    }

    /// A page that crashes after working comes back with the item it held, as last reported. One that never got
    /// going is not retried, since it would only fail again, and neither is one that ended again before it showed the
    /// item, since the item may be what ends it.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        Telemetry.editorProcessEnded(wasReady: isReady)
        guard isReady || pageLoss != nil else { return }
        let comingBack = isReady && pageLoss == nil
        releaseHeldEdit()
        cancelRequests()
        isReady = false
        reloadWatch?.cancel()
        pageWentDown(comingBack: comingBack)
        guard comingBack, let pageURL else { return }
        pageNavigation = webView.loadFileURL(pageURL, allowingReadAccessTo: pageURL.deletingLastPathComponent())
        let losses = pageLosses
        reloadWatch = Task { [weak self, reloadLimit] in
            try? await Task.sleep(for: reloadLimit)
            guard let self, !Task.isCancelled, !isReady, pageLosses == losses else { return }
            pageWentDown(comingBack: false)
        }
    }

    /// A page that came back may never say it showed the item: a hidden window draws no frames, and outside text
    /// loaded before it painted gives it another generation, for which it posts no `painted`. One that has stayed up
    /// this long has come back, so only a page that goes down again soon after it came back cannot come back.
    func watchSettling() {
        let losses = pageLosses
        reloadWatch = Task { [weak self, settleTime] in
            try? await Task.sleep(for: settleTime)
            guard let self, !Task.isCancelled, isReady, pageLosses == losses else { return }
            pageLoss = nil
        }
    }

    /// Only the page's own load counts, and only after the page had been ready: one that never got going held nothing
    /// typed. A load that failed because the process ended is left to `webViewWebContentProcessDidTerminate`, which
    /// WebKit can call after it, so a page that can come back is reloaded.
    private func pageFailedToLoad(_ navigation: WKNavigation?, _ error: any Error) {
        let error = error as NSError
        if error.domain == WKError.errorDomain, error.code == WKError.webContentProcessTerminated.rawValue { return }
        guard navigation === pageNavigation, isReady || pageLoss != nil else { return }
        releaseHeldEdit()
        cancelRequests()
        isReady = false
        reloadWatch?.cancel()
        pageWentDown(comingBack: false)
    }
}
