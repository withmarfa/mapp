import AppKit
import OSLog
import WebKit

private let log = Telemetry.logger(.editor)

/// What the page tells the app, and what the app does with each message.
extension EditorController {
    /// Tells the person the page ran into a problem, in the app's words and with a next step; what the page or WebKit said
    /// goes to the log.
    func tellPageFault() {
        library?.notices.tell(
            String(localized: "Editor Couldn’t Complete the Action"),
            String(localized: "The editor ran into a problem. If your last change doesn’t show, open the item again."))
    }

    /// A message that did not decode. A change whose text is still readable is handed back; anything else is only logged.
    fileprivate func receiveUnreadable(_ body: Any) {
        // The body may hold text, which does not belong in the log; its type says what went wrong.
        log.error("unreadable message of type \(String(describing: (body as? [String: Any])?["type"]), privacy: .public)")
        guard let markdown = EditorMessage.unreadableChange(body) else { return }
        handBack(markdown, kind: "an edit that did not decode", reason: String(localized: "The editor sent your typing in a form the app couldn’t read."))
    }

    fileprivate func receive(_ message: EditorMessage) {
        switch message {
        case .ready:
            releaseHeldEdit()
            outline = nil
            isReady = true
            reloadWatch?.cancel()
            sendHostActivation()
            applyAccent()
            applyKeymap()
            applyStyle()
            watchLinks()
            // A reloaded page starts at the top, and says nothing while it stays there.
            isHeaderScrolledAway = false
            isContentUnderToolbar = false
            isEditingTitle = false
            headerIconSize = nil
            headerTypeIcons = []
            sendHeader()
            if let pageItemID {
                embeds.version += 1
                call("setItem", json(pageItemID.rawValue))
                nextGeneration(showing: Shown(id: pageItemID, read: read))
                call("load", json(markdown), String(generation), String(isEditable))
                applyEditingMode()
            }
            // A page that ends again before it has shown the item cannot come back: the item may be what ends it.
            if pageItemID == nil { pageLoss = nil } else { pageLoss?.loadedAgain = generation }
            if pageLoss != nil { watchSettling() }
            if let requested = wantsFocus { focus(requested.id, onTitle: requested.onTitle, caret: requested.caret) }
            appendPendingEmbeds()
        case .headings(let headings, let generation):
            let accepted = PageOutline.accepting(headings, generation: generation, current: self.generation, item: shown[generation]?.id)
            if accepted != outline { outline = accepted }
        case .painted(let generation):
            pageWorks(in: generation)
            guard let open = opening, open.generation == generation else { return }
            open.interval.end()
            opening = nil
        case .changed(let markdown, let generation):
            // A page that reports again is answering, so the next flush waits for it as before.
            if generation == abandonedGeneration { abandonedGeneration = nil }
            pageWorks(in: generation)
            if isWritingToolsActive() { return holdEdit(markdown, of: generation) }
            report(markdown, of: generation)
        case .state(let state):
            guard state.generation == generation else { return }
            if state != caret { caret = state }
            if !state.sourceMode { appendPendingEmbeds() }
        case .headerScrolledAway(let away, let generation):
            guard generation == self.generation, away != isHeaderScrolledAway else { return }
            isHeaderScrolledAway = away
        case .contentUnderToolbar(let under, let generation):
            guard generation == self.generation, under != isContentUnderToolbar else { return }
            isContentUnderToolbar = under
        case .titleFocus(let focused):
            isEditingTitle = focused
            if focused { webView.beginEditingTitle() }
        case .titleInput(let item, let text):
            onHeaderEvent(.titleInput(item, text))
        case .titleCommit(let item, let text, let startWriting):
            onHeaderEvent(.titleCommit(item, text, startWriting: startWriting))
        case .titleDiscard(let item):
            onHeaderEvent(.titleDiscard(item))
        case .headerMenu(let menu, let item, let rect, let viewportHeight):
            onHeaderEvent(.menu(menu, item, containerRect(rect, viewportHeight: viewportHeight)))
        case .editValue(let item, let row, let rect, let viewportHeight):
            onHeaderEvent(.edit(row: row, item, containerRect(rect, viewportHeight: viewportHeight)))
        case .fieldMenu(let item, let row, let editsValue, let rect, let viewportHeight):
            onHeaderEvent(.fieldMenu(row: row, editsValue: editsValue, item, containerRect(rect, viewportHeight: viewportHeight)))
        case .valueMoved(let item, let row, let rect, let viewportHeight):
            // The value's editor follows it, which is the presenter's to say whether there is one open for it.
            ValueEditPresenter.shared.valueMoved(item: item, row: row, to: containerRect(rect, viewportHeight: viewportHeight))
        case .moveRow(let item, let row, let order):
            onHeaderEvent(.moveRow(row: row, order: order, item))
        case .changeType(let item, let rect, let viewportHeight):
            onHeaderEvent(.changeType(item, containerRect(rect, viewportHeight: viewportHeight)))
        case .openLink(let href):
            // The page has already refused what Inkkit's `canOpenLink` does not allow.
            openAddress(href)
        case .openItem(let id):
            follow(id)
        case .copy(let text):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        case .escape:
            onEscape()
        case .pasteImages:
            insertImages(PastedImages.sources(on: .general))
        case .openEmbed(let item, let reference):
            openEmbed(reference, in: item)
        case .quickLookEmbed(let item, let reference):
            quickLookEmbed(reference, in: item)
        case .openItemLink(let item, let link):
            Task { await openItemLink(link, from: item) }
        case .linkMenu(let item, let generation, let target, let point, let viewportHeight):
            showLinkMenu(for: target, in: item, generation: generation, at: point, viewportHeight: viewportHeight)
        case .embedMenu(let embed):
            menuEmbed = embed
        case .rowMenu(let row):
            menuRow = row
        case .find(let state):
            guard state.generation == generation else { return }
            pageFinder.update(state)
        case .diagnostic(let message):
            log.notice("preview diagnostic: \(message)")
        case .hiddenText:
            // Inkkit reports none of the refused input, so it can't be kept for the person: they are told it was not added.
            library?.notices.tell(Self.hiddenTextTitle, Self.hiddenTextMessage)
        case .error(let message):
            // The script's own sentence may quote the page's text and offers no next step, so only the log gets it.
            log.error("page error: \(message)")
            tellPageFault()
        }
    }
}

final class MessageProxy: NSObject, WKScriptMessageHandler {
    weak var target: EditorController?

    init(target: EditorController) {
        self.target = target
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let parsed = EditorMessage(body: message.body) else {
            target?.receiveUnreadable(message.body)
            return
        }
        target?.receive(parsed)
    }
}
