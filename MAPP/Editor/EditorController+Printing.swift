import AppKit
import UniformTypeIdentifiers
import WebKit

/// Printing the note and exporting it as a PDF.
extension EditorController {
    /// The note's title, which names a print job and an exported file.
    private var title: String {
        noteID.flatMap { library?.item($0)?.title } ?? String(localized: "Note")
    }


    func printNote() {
        guard hasNote, let window = webView.window else { return }
        renderDocument(in: window, destination: nil)
    }

    func exportPDF() {
        guard hasNote, let window = webView.window else { return }
        let id = noteID
        let generation = generation
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = NoteText.fileSafe(title)
        panel.beginSheetModal(for: window) { [self] response in
            guard response == .OK, let url = panel.url, noteID == id, self.generation == generation else { return }
            exportPDF(to: url)
        }
    }

    func exportPDF(to url: URL) {
        guard hasNote, let window = webView.window else { return }
        renderDocument(in: window, destination: url)
    }

    private func renderDocument(in window: NSWindow, destination: URL?) {
        guard printRenderer == nil, isReady, let id = noteID else { return }
        let generation = generation
        let title = title
        let renderer = PrintDocumentRenderer()
        printRenderer = renderer
        Task { [self] in
            defer { renderer.close(); printRenderer = nil }
            do {
                guard noteID == id, self.generation == generation else { return }
                let value = try await webView.callAsyncJavaScript("return await window.editor.printable(expected)", arguments: ["expected": generation], in: nil, contentWorld: .page)
                if let result = value as? [String: Any], result["snapshotError"] != nil, let message = result["message"] as? String {
                    throw NSError(domain: "MAPP.Print", code: 2, userInfo: [NSLocalizedDescriptionKey: message])
                }
                guard let result = value as? [String: Any], let html = result["html"] as? String,
                      let revision = result["revision"] as? Int else {
                    throw NSError(domain: "MAPP.Print", code: 1, userInfo: [NSLocalizedDescriptionKey: String(localized: "The printable note could not finish loading.")])
                }
                guard noteID == id, self.generation == generation else { return }
                try await renderer.load(html, textSize: CGFloat(style.textSize))
                guard noteID == id, self.generation == generation, webView.window === window,
                      let current = try await webView.evaluateJavaScript("window.editor.snapshot(\(generation))") as? [String: Any],
                      current["revision"] as? Int == revision else { return }
                if let destination { try await renderer.exportPDF(to: destination) }
                else { _ = await renderer.printDocument(in: window, title: title) }
            } catch {
                guard noteID == id, self.generation == generation else { return }
                library?.notices.tell(String(localized: "Couldn’t Print Note"), error.localizedDescription)
            }
        }
    }
}
