import AppKit
import WebKit
import PDFKit

@MainActor
final class PrintDocumentRenderer: NSObject, WKNavigationDelegate {
    private let view: WKWebView = {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        return WKWebView(frame: NSRect(x: 0, y: 0, width: 612, height: 792), configuration: configuration)
    }()
    // WebKit needs a window-backed drawing surface for complete native print output.
    private let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 612, height: 792), styleMask: [.borderless], backing: .buffered, defer: false)
    private var printContinuation: CheckedContinuation<Bool, Never>?
    private var timeout: Task<Void, Never>?
    private var continuation: CheckedContinuation<Void, any Error>?

    func load(_ html: String, textSize: CGFloat = 15) async throws {
        guard html.utf8.count <= 64 << 20 else { throw PrintError.limit }
        window.isReleasedWhenClosed = false
        window.contentView = view
        view.navigationDelegate = self
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            view.loadHTMLString(html, baseURL: nil)
            timeout = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(15))
                guard !Task.isCancelled, let self else { return }
                self.view.stopLoading()
                self.complete(PrintError.unavailable)
            }
        }
        _ = try await view.callAsyncJavaScript("""
        document.documentElement.style.fontSize = `${textSize}px`;
        await Promise.race([
          (async () => { await document.fonts.ready; await Promise.all(Array.from(document.images, image => image.decode())); })(),
          new Promise((_, reject) => setTimeout(() => reject(new Error('Print content could not finish loading.')), 15000))
        ]);
        """, arguments: ["textSize": textSize], in: nil, contentWorld: .page)
    }

    func close() {
        view.stopLoading()
        window.contentView = nil
        window.close()
    }

    enum PrintError: LocalizedError {
        case unavailable, limit
        var errorDescription: String? {
            switch self {
            case .unavailable: String(localized: "The printable note could not finish loading.")
            case .limit: String(localized: "The PDF exceeds the export limit of 200 pages or 64 MB.")
            }
        }
    }

    struct Limits {
        // Bound both WebKit work and accumulated PDF data before touching the destination.
        var pages = 200
        var bytes = 64 << 20
    }

    func exportPDF(to destination: URL, limits: Limits = Limits()) async throws {
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        let paper = info.paperSize
        let width = paper.width - 108
        let height = paper.height - 108
        guard width > 0, height > 0, limits.pages > 0, limits.bytes > 0 else { throw PrintError.limit }
        view.frame = NSRect(x: 0, y: 0, width: width, height: height)
        let layout: [[String: Double]]?
        do { layout = try await view.callAsyncJavaScript("""
        const style = document.createElement('style');
        style.textContent = `html,body{margin:0!important;padding:0!important;min-height:0!important;max-width:none!important;width:auto!important}
          img{max-width:100%;max-height:${height}px;object-fit:contain} pre{white-space:pre-wrap}`;
        document.head.append(style);
        const bottom = Math.max(document.body.scrollHeight, document.documentElement.scrollHeight);
        const spans = Array.from(document.querySelectorAll('p,li,h1,h2,h3,h4,h5,h6,tr,img,pre,blockquote')).map(e => {
          const r = e.getBoundingClientRect(); return {top:r.top,bottom:r.bottom,heading:/^H[1-6]$/.test(e.tagName)};
        });
        const texts = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
        while(texts.nextNode()) {
          if(!texts.currentNode.textContent.trim()) continue;
          const range = document.createRange(); range.selectNodeContents(texts.currentNode);
          for(const r of range.getClientRects()) spans.push({top:r.top,bottom:r.bottom});
        }
        let pages = [], start = 0;
        while(start < bottom) {
          if(pages.length >= limit) throw new Error('PDF_PAGE_LIMIT');
          let end = Math.min(start + height, bottom);
          const crossing = spans.filter(r => r.top > start && r.top < end && r.bottom > end);
          if(crossing.length) {
            let boundary = Math.min(...crossing.map(r => r.top));
            const heading = spans.find(r => r.heading && r.top > start && r.bottom <= boundary && boundary-r.bottom < 40);
            if(heading) boundary = heading.top;
            if(boundary > start + height * 0.4) end = boundary;
          }
          pages.push({start,height:end-start}); start = end;
        }
        return pages;
        """, arguments: ["height": height, "limit": limits.pages], in: nil, contentWorld: .page) as? [[String: Double]] }
        catch {
            if ((error as NSError).userInfo["WKJavaScriptExceptionMessage"] as? String)?.contains("PDF_PAGE_LIMIT") == true { throw PrintError.limit }
            throw error
        }
        guard let layout, !layout.isEmpty, layout.count <= limits.pages else { throw PrintError.limit }
        let output = NSMutableData()
        guard let consumer = CGDataConsumer(data: output) else { throw PrintError.unavailable }
        var box = CGRect(origin: .zero, size: paper)
        guard let context = CGContext(consumer: consumer, mediaBox: &box, nil) else { throw PrintError.unavailable }
        var sourceBytes = 0
        for slice in layout {
            guard let start = slice["start"], let sliceHeight = slice["height"] else { throw PrintError.unavailable }
            let configuration = WKPDFConfiguration()
            configuration.rect = CGRect(x: 0, y: start, width: width, height: sliceHeight)
            let data = try await pdf(configuration)
            sourceBytes += data.count
            guard sourceBytes <= limits.bytes, let provider = CGDataProvider(data: data as CFData),
                  let document = CGPDFDocument(provider), document.numberOfPages == 1,
                  let page = document.page(at: 1) else { throw PrintError.limit }
            context.beginPDFPage(nil)
            context.saveGState()
            context.translateBy(x: 54, y: paper.height - 54 - sliceHeight)
            context.drawPDFPage(page)
            context.restoreGState()
            context.endPDFPage()
            guard output.length <= limits.bytes else { throw PrintError.limit }
        }
        context.closePDF()
        guard output.length <= limits.bytes, let document = PDFDocument(data: output as Data),
              document.pageCount == layout.count else { throw PrintError.limit }
        try (output as Data).write(to: destination, options: .atomic)
    }

    private func pdf(_ configuration: WKPDFConfiguration) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            var answered = false
            let deadline = Task { @MainActor in
                try? await Task.sleep(for: .seconds(15))
                guard !Task.isCancelled, !answered else { return }
                answered = true
                continuation.resume(throwing: PrintError.unavailable)
            }
            view.createPDF(configuration: configuration) { result in
                guard !answered else { return }
                answered = true
                deadline.cancel()
                continuation.resume(with: result)
            }
        }
    }

    func printOperation(with info: NSPrintInfo) -> NSPrintOperation {
        info.horizontalPagination = .fit
        info.isHorizontallyCentered = false
        info.isVerticallyCentered = false
        info.topMargin = 54
        info.bottomMargin = 54
        info.leftMargin = 54
        info.rightMargin = 54
        return view.printOperation(with: info)
    }

    func printDocument(in window: NSWindow, title: String) async -> Bool {
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        let operation = printOperation(with: info)
        operation.jobTitle = title
        operation.showsPrintPanel = true
        operation.showsProgressPanel = true
        return await run(operation, in: window)
    }

    func run(_ operation: NSPrintOperation, in presentingWindow: NSWindow? = nil) async -> Bool {
        guard printContinuation == nil else { return false }
        // WebKit computes print pages asynchronously; synchronous main-thread printing cannot await them.
        operation.canSpawnSeparateThread = true
        return await withCheckedContinuation { continuation in
            printContinuation = continuation
            operation.runModal(for: presentingWindow ?? window, delegate: self,
                               didRun: #selector(printDidRun(_:success:contextInfo:)), contextInfo: nil)
        }
    }

    @objc nonisolated private func printDidRun(_ operation: NSPrintOperation, success: Bool, contextInfo: UnsafeMutableRawPointer?) {
        Task { @MainActor in
            let continuation = self.printContinuation
            self.printContinuation = nil
            continuation?.resume(returning: success)
        }
    }

    private func complete(_ error: (any Error)?) {
        timeout?.cancel()
        timeout = nil
        if let error { continuation?.resume(throwing: error) }
        else { continuation?.resume() }
        continuation = nil
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { complete(PrintError.unavailable) }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        complete(nil)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        complete(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        complete(error)
    }
}
