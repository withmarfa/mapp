import AppKit
import WebKit

/// Images put into the note, and the files it embeds opened or shown.
extension EditorController {
    /// Attaches images to the note and links them where they were dropped, given in the page's own coordinates, or
    /// at the caret. Whether there were images to take; they are read and placed once their files have been read,
    /// if the note is still the one on the page. Each image that couldn't be taken is named, and the rest are
    /// still placed, so trying again adds only those named. Images attached after the note left the page are named
    /// too, since they are in the note's attachments but not in its text.
    @discardableResult
    func insertImages(_ sources: [PastedImages.Source], at point: CGPoint? = nil) -> Bool {
        guard isEditable, let noteID, library != nil, !sources.isEmpty else { return false }
        let height = webView.bounds.height
        Task {
            let (files, skipped) = await PastedImages.read(sources)
            guard self.noteID == noteID, isEditable, let library else { return }
            let report = files.isEmpty ? AttachReport() : await library.attach(files, to: noteID)
            // The images are kept either way; they go into the note only if it is still the one on the page.
            let placed = self.noteID == noteID && isEditable
            Self.reportUnplaced(
                skipped: skipped, failed: report.failed, attached: report.embeds.count,
                unplaced: placed ? [] : report.embeds.map(\.name), in: library.item(noteID)?.title ?? "", to: library
            )
            guard placed else { return }
            let images = report.embeds.map { ["src": $0.link, "alt": $0.name] }
            guard !images.isEmpty else { return }
            if let point {
                call("insertImages", json(images), String(Double(point.x)), String(Double(point.y)), String(Double(height)))
            } else {
                call("insertImages", json(images))
            }
        }
        return true
    }

    private static func reportUnplaced(
        skipped: [String], failed: [(name: String, reason: String)], attached: Int, unplaced: [String], in note: String,
        to library: any ItemLibrary
    ) {
        guard !skipped.isEmpty || !failed.isEmpty || !unplaced.isEmpty else { return }
        let largest = Int64(PastedImages.largestImage).formatted(.byteCount(style: .memory))
        let lines = skipped.map { String(localized: "“\($0)” is larger than \(largest) or can’t be read.") }
            + failed.map { String(localized: "“\($0.name)” couldn’t be attached. \($0.reason)") }
            + unplaced.map { String(localized: "“\($0)” was attached to “\(note)” but isn’t in its text, because the note was no longer open for editing.") }
        let title = if skipped.isEmpty && failed.isEmpty {
            String(localized: "Images Weren’t Added to the Note")
        } else if attached == 0 {
            String(localized: "Can’t Attach Images")
        } else {
            String(localized: "Some Images Weren’t Attached")
        }
        library.notices.tell(title, lines.joined(separator: "\n"))
    }

    /// How long the page waits for Marfa to bind an embed not yet bound, as one just pasted is once its text is saved.
    nonisolated static let embedWait = Duration.seconds(10)

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

    /// Follows the library for the embeds of the note on the page, and tells the page which have changed: a file
    /// that arrived, was renamed or removed, or an embed the copy has since bound. The page then asks again for just
    /// those (`refreshReferences`). It also follows the files attached to the note that were saved from a web
    /// address, and has the page ask again about the pictures at those addresses when a file arrives, is changed or goes
    /// (`ItemLibrary.openSavedPicture`). Changes come in bursts, as files arrive and text is saved, so the page hears
    /// once they pause. Never rewrites the note.
    func watchEmbeds() {
        embedWatch += 1
        guard let library, let note = noteID else {
            embedStates = nil
            savedStates = nil
            return
        }
        let watch = embedWatch
        var states: [String: EmbedState] = [:]
        var saved: [SavedPictureState] = []
        withObservationTracking {
            states = library.embedStates(of: note)
            saved = library.savedPictureStates(of: note)
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(300))
                guard let self, !windowIsGone, embedWatch == watch else { return }
                tellEmbedsChanged(in: note)
            }
        }
        if embedStates?.note != note { embedStates = (note, states) }
        if savedStates?.note != note { savedStates = (note, saved) }
    }

    private func tellEmbedsChanged(in note: ItemID) {
        guard let library, noteID == note else { return }
        let now = library.embedStates(of: note)
        let before = embedStates?.states ?? [:]
        embedStates = (note, now)
        let changed = now.filter { before[$0.key] != $0.value }.keys.sorted()
        if !changed.isEmpty, isReady { call("embedsChanged", json(changed)) }
        let saved = library.savedPictureStates(of: note)
        let savedBefore = savedStates?.states ?? []
        savedStates = (note, saved)
        let differing = Set(Set(saved).symmetricDifference(savedBefore).map(\.address)).sorted()
        if !differing.isEmpty, isReady { call("savedPicturesChanged", json(differing)) }
        watchEmbeds()
    }

    /// Opens a file the note embeds in the app the system opens it with, or shows it in the Finder: always for
    /// one that might run when opened (`EmbeddedFiles.opens`), whatever the page asked.
    func openEmbed(_ reference: EmbedReference, in item: ItemID, revealing: Bool = false) {
        Task {
            guard let url = await library?.openEmbeddedFile(reference, in: item).file?.url else { return }
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

extension EditorController {
    /// The page asks again for the pictures at web addresses that were waiting or turned off, and for those it
    /// loaded, when the Remote Pictures setting has changed. Settings changes of any kind arrive here.
    func pictureSettingChanged() {
        let setting = pictures.setting
        guard setting != toldPictureSetting else { return }
        toldPictureSetting = setting
        call("picturesChanged")
    }
}
