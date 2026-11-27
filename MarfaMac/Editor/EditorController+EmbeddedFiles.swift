import AppKit
import OSLog
import WebKit

/// Images put into the item, and the files it embeds opened or shown.
extension EditorController {
    /// Takes images for the item that is open now and tries to place their links at the drop point or caret.
    /// Reports each image that could not be attached or placed in the text.
    @discardableResult
    func insertImages(_ sources: [PastedImages.Source], at point: CGPoint? = nil) -> Bool {
        guard isEditable, let pageItemID, let library, !sources.isEmpty else { return false }
        let height = webView.bounds.height
        Task {
            let (files, skipped) = await PastedImages.read(sources)
            let report = files.isEmpty ? AttachReport() : await library.attach(files, to: pageItemID)
            let placed = self.pageItemID == pageItemID && isEditable
            let embeds = report.embeds
            var notPlaced: [String] = []
            if placed, !embeds.isEmpty,
                await !place(embeds.map { ["src": $0.link, "alt": $0.name] }, at: point, height: height, in: pageItemID) {
                notPlaced = embeds.map(\.name)
            }
            Self.reportUnplaced(
                skipped: skipped, failed: report.failed, attached: embeds.count,
                unplaced: placed ? [] : embeds.map(\.name), refused: notPlaced,
                in: library.item(pageItemID)?.title ?? "", to: library
            )
        }
        return true
    }

    /// Asks the page to put the images in, and again after the next paint while it refuses them for folded text,
    /// which Inkkit has opened by then, up to `hiddenTextRetryLimit` times. False when they were not placed.
    private func place(_ images: [[String: String]], at point: CGPoint?, height: CGFloat, in id: ItemID) async -> Bool {
        let arguments: [String: Any] = [
            "images": images, "x": point.map { Double($0.x) } ?? NSNull(), "y": point.map { Double($0.y) } ?? NSNull(),
            "height": Double(height),
        ]
        for attempt in 0...Self.hiddenTextRetryLimit {
            guard pageItemID == id, isEditable else { return false }
            let outcome: Any?
            do {
                outcome = try await webView.callAsyncJavaScript(
                    "return window.editor.insertImages(images, x, y, height)", arguments: arguments, in: nil, contentWorld: .page)
            } catch {
                Telemetry.logger(.editor).error("insertImages: \(error.localizedDescription)")
                return false
            }
            if outcome as? Bool == true { return true }
            guard let refusal = (outcome as? [String: Any])?["commandError"] as? String, Self.retriesAfterPaint(refusal),
                attempt < Self.hiddenTextRetryLimit
            else { return false }
            try? await Task.sleep(for: Self.hiddenTextRetryDelay)
        }
        return false
    }

    private static func reportUnplaced(
        skipped: [String], failed: [(name: String, reason: String)], attached: Int, unplaced: [String], refused: [String] = [],
        in title: String, to library: any ItemLibrary
    ) {
        guard !skipped.isEmpty || !failed.isEmpty || !unplaced.isEmpty || !refused.isEmpty else { return }
        let largest = Int64(PastedImages.largestImage).formatted(.byteCount(style: .memory))
        let lines = skipped.map { String(localized: "“\($0)” is larger than \(largest) or can’t be read.") }
            + failed.map { String(localized: "“\($0.name)” couldn’t be attached. \($0.reason)") }
            + unplaced.map { String(localized: "“\($0)” was attached to “\(title)” but isn’t in its text, because the item was no longer open for editing.") }
            + refused.map { String(localized: "“\($0)” was attached to “\(title)” but isn’t in its text. It was meant for a folded section or text not yet shown.") }
        let title = if skipped.isEmpty && failed.isEmpty {
            String(localized: "Images Weren’t Added to the Item")
        } else if attached == 0 {
            String(localized: "Can’t Attach Images")
        } else {
            String(localized: "Some Images Weren’t Attached")
        }
        library.notices.tell(title, lines.joined(separator: "\n"))
    }

    nonisolated static let hiddenTextTitle = String(localized: "Text Wasn’t Added")
    nonisolated static let hiddenTextMessage = String(
        localized: "What you typed reached a folded section, which is now open. It wasn’t added, so type it again.")

    /// How long the page waits for Marfa to bind an embed not yet bound, as one just pasted is once its text is saved.
    nonisolated static let embedWait = Duration.seconds(10)

    /// Puts what the page writes for files the new-item form attached to a new item at the end of its text, leaving the
    /// caret where it is: now if the page shows that item, otherwise once it does. The page saves the change as it
    /// does typing. Where the page never shows the item again, the files stay attached without being in its text.
    func append(_ embeds: [Embed], to id: ItemID) {
        guard !windowIsGone, !embeds.isEmpty else { return }
        pendingEmbeds[id, default: []] += embeds
        appendPendingEmbeds()
    }

    /// Sends what waits for the item on the page, and keeps it waiting until the page has written it: the page
    /// takes none while the item is edited as source or composing, and they go once the page next reports its state
    /// in a mode that takes them. Only a failure that trying again cannot change gives them up, and says so.
    func appendPendingEmbeds() {
        guard !isAppendingEmbeds else {
            appendsAgain = true
            return
        }
        guard let pageItemID, isReady, isEditable, let embeds = pendingEmbeds[pageItemID], !embeds.isEmpty else { return }
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
                hiddenTextAttempts = 0
                take(embeds, from: pageItemID)
                appendsAgain = true
            } else if let refusal = (outcome as? [String: Any])?["commandError"] as? String {
                if Self.retriesAfterPaint(refusal) {
                    hiddenTextAttempts += 1
                    if hiddenTextAttempts <= Self.hiddenTextRetryLimit {
                        // The page opened the folded section the images belong in; they go once it has painted.
                        Task {
                            try? await Task.sleep(for: Self.hiddenTextRetryDelay)
                            appendPendingEmbeds()
                        }
                    } else {
                        hiddenTextAttempts = 0
                        if take(embeds, from: pageItemID) { notInText(embeds, of: pageItemID) }
                    }
                } else if !Self.passingRefusals.contains(refusal), take(embeds, from: pageItemID) {
                    notInText(embeds, of: pageItemID)
                }
            }
            if appendsAgain { appendPendingEmbeds() }
        }
    }

    /// Whether a refusal means the edit touched folded or not-yet-shown text, which the page has now opened. The images
    /// are sent again after the next paint, up to `hiddenTextRetryLimit` times, and then named as not in the text.
    nonisolated static func retriesAfterPaint(_ refusal: String) -> Bool { refusal == "hidden-text" }

    nonisolated static let hiddenTextRetryDelay = Duration.milliseconds(100)
    nonisolated static let hiddenTextRetryLimit = 10

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
        let item = library.item(id)?.displayTitle ?? String(localized: "Untitled")
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

    /// Follows the library for the embeds of the item on the page, and tells the page which have changed: a file
    /// that arrived, was renamed or removed, or an embed the copy has since bound. The page then asks again for just
    /// those (`refreshReferences`). It also follows the files attached to the item that were saved from a web
    /// address, and has the page ask again about the pictures at those addresses when a file arrives, is changed or goes
    /// (`ItemLibrary.openSavedPicture`). Changes come in bursts, as files arrive and the copy binds embeds, so the page
    /// hears once they pause. A keystroke that changes neither an embed nor a saved picture is not one of them.
    /// Never rewrites the item.
    ///
    /// Known limit: it follows the library's own state, so a connection that returns after an offline spell does not
    /// redraw an embed that showed an error card. The card's retry does, and so does any later change.
    func watchEmbeds() {
        embedWatch += 1
        guard let library, let itemID = pageItemID else {
            embedStates = nil
            savedStates = nil
            return
        }
        let watch = embedWatch
        var states: [String: EmbedState] = [:]
        var saved: [SavedPictureState] = []
        withObservationTracking {
            states = library.embedStates(of: itemID)
            saved = library.savedPictureStates(of: itemID)
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(300))
                guard let self, !windowIsGone, embedWatch == watch else { return }
                tellEmbedsChanged(in: itemID)
            }
        }
        if embedStates?.itemID != itemID { embedStates = (itemID, states) }
        if savedStates?.itemID != itemID { savedStates = (itemID, saved) }
    }

    private func tellEmbedsChanged(in itemID: ItemID) {
        guard let library, pageItemID == itemID else { return }
        let now = library.embedStates(of: itemID)
        let before = embedStates?.states ?? [:]
        embedStates = (itemID, now)
        let changed = now.filter { before[$0.key] != $0.value }.keys.sorted()
        if !changed.isEmpty, isReady { call("embedsChanged", json(changed)) }
        let saved = library.savedPictureStates(of: itemID)
        let savedBefore = savedStates?.states ?? []
        savedStates = (itemID, saved)
        let differing = Set(Set(saved).symmetricDifference(savedBefore).map(\.address)).sorted()
        if !differing.isEmpty, isReady { call("savedPicturesChanged", json(differing)) }
        watchEmbeds()
    }

    /// Opens a file the item embeds in the app the system opens it with, or shows it in the Finder: always for
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

    /// Shows a file the item embeds in Quick Look. The page asks about the item it shows and an embed of its text; a
    /// reference to another item, or one the library no longer binds to a file, shows nothing and tells the person
    /// why. The file is the library's kept copy, already named after the item with its extension, so Quick Look
    /// picks a previewer from it as it does for a file item, and nothing is copied or left to remove.
    func quickLookEmbed(_ reference: EmbedReference, in item: ItemID) {
        guard item == pageItemID, let library else {
            Telemetry.logger(.editor).notice("quick look asked for an embed of an item that is not on the page")
            return
        }
        Task {
            let resolution = await library.openEmbeddedFile(reference, in: item)
            guard pageItemID == item, !windowIsGone else { return }
            switch resolution {
            case .file(let file):
                quickLook = QuickLookRequest(showing: file.url)
                NotificationCenter.default.post(name: .quickLookTaken, object: self)
            case .unavailable(let reason):
                library.notices.tell(String(localized: "Can’t Quick Look"), reason)
            case .missing:
                library.notices.tell(String(localized: "Can’t Quick Look"), String(localized: "This file isn’t in Marfa."))
            }
        }
    }

    /// Closes Quick Look for this editor, as the panel closing or another window taking it does.
    func dismissQuickLook() {
        quickLook = nil
    }

    /// The embed the context menu opening now is over, heard from the page just before; each menu takes it once.
    func takeMenuEmbed() -> (item: ItemID, reference: EmbedReference, opens: Bool)? {
        defer { menuEmbed = nil }
        return menuEmbed
    }

    /// The header row the context menu opening now is over, heard from the page just before; each menu takes it once.
    func takeMenuRow() -> (item: ItemID, row: String)? {
        defer { menuRow = nil }
        return menuRow
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

