import AppKit
import WebKit

/// Images put into the note, and the files it embeds opened or shown.
extension EditorController {
    /// Puts images into the note: into the attachments folder, and linked where they were dropped, given in the
    /// page's own coordinates, or at the caret. Whether there were images to take; they are read and placed
    /// once their files have been read, if the note is still the one on the page.
    @discardableResult
    func insertImages(_ sources: [PastedImages.Source], at point: CGPoint? = nil) -> Bool {
        guard isEditable, let noteID, library != nil, !sources.isEmpty else { return false }
        let height = webView.bounds.height
        Task {
            let files = await PastedImages.read(sources)
            guard self.noteID == noteID, isEditable, let library else { return }
            let embeds: [Embed]
            do {
                embeds = try await library.attach(files, to: noteID)
            } catch {
                library.notices.tell(String(localized: "Can’t Attach Images"), String(localized: "The images weren’t added to the note. \(error.localizedDescription)"))
                return
            }
            // The images are kept either way; they go into the note only if it is still the one on the page.
            guard self.noteID == noteID, isEditable else { return }
            let images = embeds.map { ["src": $0.link, "alt": $0.name] }
            guard !images.isEmpty else { return }
            if let point {
                call("insertImages", json(images), String(Double(point.x)), String(Double(point.y)), String(Double(height)))
            } else {
                call("insertImages", json(images))
            }
        }
        return true
    }

    /// Puts what the page writes for files quick add attached to a new note at the end of its text, leaving the
    /// caret where it is: now if the page shows that note, otherwise once it does. The page saves the change as it
    /// does typing. Where the page never shows the note again, the files stay attached without being in its text.
    func append(_ embeds: [Embed], to id: ItemID) {
        guard !windowIsGone, !embeds.isEmpty else { return }
        pendingEmbeds[id, default: []] += embeds
        appendPendingEmbeds()
    }

    /// Sends what waits for the note on the page, and keeps it waiting until the page has written it: the page
    /// takes none while the note is edited as source or composing, and they go once the page next reports its state
    /// in a mode that takes them. Only a failure that trying again cannot change gives them up, and says so.
    func appendPendingEmbeds() {
        guard !isAppendingEmbeds else {
            appendsAgain = true
            return
        }
        guard let noteID, isReady, isEditable, let embeds = pendingEmbeds[noteID], !embeds.isEmpty else { return }
        isAppendingEmbeds = true
        appendsAgain = false
        let generation = generation
        Task {
            let outcome: Any?
            do {
                outcome = try await webView.callAsyncJavaScript(
                    "return window.editor.appendImages(images, expected)",
                    arguments: ["images": embeds.map { ["src": $0.link, "alt": $0.name] }, "expected": generation],
                    in: nil, contentWorld: .page)
            } catch {
                outcome = ["commandError": "exception"]
            }
            isAppendingEmbeds = false
            if outcome as? Bool == true {
                take(embeds, from: noteID)
                appendsAgain = true
            } else if let refusal = (outcome as? [String: Any])?["commandError"] as? String,
                      !Self.passingRefusals.contains(refusal) {
                if take(embeds, from: noteID) { notInText(embeds, of: noteID) }
            }
            if appendsAgain { appendPendingEmbeds() }
        }
    }

    /// Refusals that pass: a composition, a load that made the generation sent stale, and an import still running.
    private static let passingRefusals: Set<String> = ["composition", "stale-document", "operation-pending", "not-ready"]

    /// Takes the embeds sent from those waiting, leaving any that came in while they were sent. False when they
    /// no longer wait, as after the window went.
    @discardableResult
    private func take(_ sent: [Embed], from id: ItemID) -> Bool {
        guard var waiting = pendingEmbeds[id], waiting.starts(with: sent) else { return false }
        waiting.removeFirst(sent.count)
        pendingEmbeds[id] = waiting.isEmpty ? nil : waiting
        return true
    }

    /// Tells the person that files attached to an item are not in its text, so none goes missing unseen.
    func notInText(_ embeds: [Embed], of id: ItemID) {
        guard let library, !embeds.isEmpty else { return }
        let names = embeds.map { "“\($0.name)”" }.formatted(.list(type: .and))
        let title = library.item(id)?.title ?? ""
        let item = title.isEmpty ? String(localized: "Untitled") : title
        if embeds.count == 1 {
            library.notices.tell(
                String(localized: "File Not in the Text"),
                String(localized: "\(names) is attached to “\(item)”, but it couldn’t be put in its text."))
        } else {
            library.notices.tell(
                String(localized: "Files Not in the Text"),
                String(localized: "\(names) are attached to “\(item)”, but they couldn’t be put in its text."))
        }
    }

    /// Opens a file the note embeds in the app the system opens it with, or shows it in the Finder: always for
    /// one that might run when opened (`EmbeddedFiles.opens`), whatever the page asked.
    func openEmbed(_ reference: EmbedReference, in item: ItemID, revealing: Bool = false) {
        Task {
            guard let url = await library?.openEmbeddedFile(reference, in: item)?.url else { return }
            if revealing || !EmbeddedFiles.opens(url) {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } else {
                NSWorkspace.shared.open(url)
            }
        }
    }

    /// The embed the context menu opening now is over, heard from the page just before; each menu takes it once.
    func takeMenuEmbed() -> (item: ItemID, reference: EmbedReference, opens: Bool)? {
        defer { menuEmbed = nil }
        return menuEmbed
    }
}
