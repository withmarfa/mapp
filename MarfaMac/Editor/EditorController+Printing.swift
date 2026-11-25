import AppKit
import OSLog
import UniformTypeIdentifiers
import WebKit

private let log = Telemetry.logger(.editor)

/// Printing the item and exporting it as a PDF.
extension EditorController {
    /// The item's title, which names a print job and an exported file.
    private var title: String {
        pageItemID.flatMap { library?.item($0)?.title } ?? String(localized: "Item")
    }


    func printItem() {
        guard hasItem, let window = webView.window else { return }
        renderDocument(in: window, destination: nil)
    }

    func exportPDF() {
        guard hasItem, let window = webView.window else { return }
        let id = pageItemID
        let generation = generation
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = FileName.fileSafe(title)
        panel.beginSheetModal(for: window) { [self] response in
            guard response == .OK, let url = panel.url, pageItemID == id, self.generation == generation else { return }
            exportPDF(to: url)
        }
    }

    func exportPDF(to url: URL) {
        guard hasItem, let window = webView.window else { return }
        renderDocument(in: window, destination: url)
    }

    private func renderDocument(in window: NSWindow, destination: URL?) {
        guard printRenderer == nil, isReady, let id = pageItemID else { return }
        let generation = generation
        let title = title
        let renderer = PrintDocumentRenderer()
        printRenderer = renderer
        Task { [self] in
            defer { renderer.close(); printRenderer = nil }
            do {
                guard pageItemID == id, self.generation == generation else { return }
                let value = try await webView.callAsyncJavaScript("return await window.editor.printable(expected)", arguments: ["expected": generation], in: nil, contentWorld: .page)
                let unprepared = NSError(domain: "MarfaMac.Print", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: String(localized: "The item couldn’t be prepared for printing. Open the item again, then try again."),
                ])
                if let result = value as? [String: Any], let code = result["snapshotError"] {
                    log.error("the page could not prepare the item for printing: \(String(describing: code), privacy: .public)")
                    throw unprepared
                }
                guard let result = value as? [String: Any], let html = result["html"] as? String,
                      let revision = result["revision"] as? Int else { throw unprepared }
                guard pageItemID == id, self.generation == generation else { return }
                try await renderer.load(html, style: style)
                guard pageItemID == id, self.generation == generation, webView.window === window,
                      let current = try await webView.evaluateJavaScript("window.editor.snapshot(\(generation))") as? [String: Any],
                      current["revision"] as? Int == revision else { return }
                if let destination { try await renderer.exportPDF(to: destination) }
                else { _ = await renderer.printDocument(in: window, title: title) }
            } catch {
                guard pageItemID == id, self.generation == generation else { return }
                // WebKit's own words for a failed script say nothing the person can act on.
                let fromThePage = (error as NSError).domain == WKError.errorDomain
                if fromThePage { log.error("the page failed while preparing the item for printing: \(error, privacy: .public)") }
                let message = fromThePage
                    ? String(localized: "The item couldn’t be prepared for printing. Open the item again, then try again.")
                    : error.localizedDescription
                library?.notices.tell(String(localized: "Couldn’t Print Item"), message)
            }
        }
    }
}
