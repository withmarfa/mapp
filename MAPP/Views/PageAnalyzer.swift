import Foundation
import Synchronization
import WebKit

/// Finds the article in a saved HTML document, and whether it is a mail, so the item page can offer Reader only where
/// there is something to read.
///
/// The document is loaded, with none of its scripts, into a sealed page of its own that is thrown away afterwards, and
/// Mozilla's Readability (vendored under `Reader/`, with its licence) runs over a copy of it in the app's own script
/// world. The document cannot reach that world, and what Readability changes is the copy, so neither the page nor the
/// stored file is touched. Apple gives apps no Reader API. A document whose content its scripts build has no article
/// here, and is shown as it is.
///
/// A document too large to parse, or one that takes longer than the limit, has no article, so the item shows the
/// original as it did before Reader existed; nothing waits on the page's thread, since the work is in the web content
/// process.
enum PageAnalyzer {
    /// The longest an analysis may take before the document is taken to have no article.
    static let timeLimit = Duration.seconds(15)
    /// The most elements Readability reads before it gives up on a document.
    static let maxElements = 30_000

    /// What the document has, found in a page of its own. Throws `CancellationError` when the task is cancelled, so a
    /// caller that has moved on to another item never gets this one's answer. Any other failure, and running out of
    /// time, is a document with no article.
    static func analyze(
        _ html: Data, encoding: String.Encoding? = nil, title: String, limit: Duration = timeLimit, elementLimit: Int = maxElements
    ) async throws -> PageAnalysis {
        guard let readability else { return .none }
        let outcome = Outcome()
        // The work cannot be waited for under a group: a page that stops answering would hold the group open. It
        // answers the outcome when it has an answer, and is cancelled when something else has.
        let work = Task {
            do {
                let sealed = try await SealedWebPage.make(runsScripts: false)
                try await sealed.show(html, encoding: encoding)
                let answer = try await sealed.page.callJavaScript(
                    readability + script, arguments: ["title": title, "limit": elementLimit], contentWorld: SealedWebPage.world)
                outcome.finish(.success(PageAnalysis(javaScript: answer)))
            } catch is CancellationError {
                outcome.finish(.failure(CancellationError()))
            } catch {
                outcome.finish(.success(.none))
            }
        }
        let timer = Task {
            try? await Task.sleep(for: limit)
            outcome.finish(.success(.none))
        }
        defer {
            work.cancel()
            timer.cancel()
        }
        return try await withTaskCancellationHandler {
            try await outcome.value()
        } onCancel: {
            outcome.finish(.failure(CancellationError()))
        }
    }

    /// Readability and its readerable check, as Mozilla ships them, in one string to run before the analysis. Nil only if
    /// the app was built without them, which `ReadabilityScriptTests` would show.
    nonisolated static let readability: String? = {
        let parts = ["Readability", "Readability-readerable"].map {
            Bundle.main.url(forResource: $0, withExtension: "js").flatMap { try? String(contentsOf: $0, encoding: .utf8) }
        }
        guard let first = parts[0], let second = parts[1] else { return nil }
        return first + "\n" + second + "\n"
    }()

    /// Takes `title` and `limit`; returns `{ mail, article: { html, length, lang, dir } | null }`.
    ///
    /// Of the cleanup of the article, which Reader needs and the original does not:
    /// - An anchor is removed when it is a heading's permalink: a lone `#`, `¶` or `§`, or one marked as such, in or next to
    ///   a heading and linking to a fragment of the page or to the heading's id. Other links stay.
    /// - A backslash before a quote is removed in text, except in code, keyboard input and sample output, where it may be the code.
    /// - The first heading is removed when nothing readable comes before it and it says exactly the title, ignoring case,
    ///   punctuation and spacing, or extends a title that ends in an ellipsis. Only an ancestor left with nothing else goes with it.
    /// - A table Readability found to hold data is marked `mapp-data`, so Reader draws a grid only for those.
    /// - A picture's fixed size is dropped, so the styles size it to the column.
    /// - Event handlers and `javascript:` addresses are dropped. The document that shows the article allows no script
    ///   either, so this is the second of two.
    /// - The first picture, when less than a sentence of text comes before it and it is not an icon, is the lead picture.
    nonisolated static let script = MailColumn.script + #"""

        function cleanArticle(root, title) {
          const doc = root.ownerDocument;
          for (const e of root.querySelectorAll('script, style, link, iframe, object, embed')) e.remove();
          for (const e of root.querySelectorAll('*')) {
            for (const name of e.getAttributeNames()) {
              if (/^on/i.test(name)) e.removeAttribute(name);
            }
            for (const name of ['href', 'src', 'xlink:href']) {
              if (/^\s*(javascript|vbscript):/i.test(e.getAttribute(name) || '')) e.removeAttribute(name);
            }
            if (e.matches('img, video, svg, canvas')) { e.removeAttribute('width'); e.removeAttribute('height'); }
          }
          // Readability has already told a table of data from one a mail or page lays itself out in.
          for (const t of root.querySelectorAll('table')) if (t._readabilityDataTable) t.classList.add('mapp-data');
          const permalink = 'a.anchor, a.heading-anchor, a.header-anchor, a.headerlink, a.permalink, a[aria-label*="ermalink" i]';
          const headings = 'h1, h2, h3, h4, h5, h6';
          for (const a of root.querySelectorAll('a')) {
            const text = a.textContent.trim();
            if (!/^[#¶§]$/.test(text) && !a.matches(permalink)) continue;
            const owner = a.closest(headings)
              || [a.previousElementSibling, a.nextElementSibling].find(e => e && e.matches(headings));
            if (!owner) continue;
            const href = a.getAttribute('href') || '';
            let hash = null;
            if (href.includes('#')) {
              try { hash = decodeURIComponent(href.slice(href.indexOf('#') + 1)); } catch (e) { hash = href.slice(href.indexOf('#') + 1); }
            }
            if (href.startsWith('#') || (owner.id && hash === owner.id)) a.remove();
          }
          const walker = doc.createTreeWalker(root, NodeFilter.SHOW_TEXT);
          for (let node = walker.nextNode(); node; node = walker.nextNode()) {
            if (node.parentElement && node.parentElement.closest('pre, code, kbd, samp, textarea')) continue;
            if (node.nodeValue.includes('\\')) node.nodeValue = node.nodeValue.replace(/\\(["'‘’“”])/g, '$1');
          }
          const words = s => s.toLowerCase().replace(/[^\p{L}\p{N}]+/gu, ' ').trim();
          const wanted = words(title);
          const heading = root.querySelector(headings);
          if (heading && wanted) {
            const before = doc.createRange();
            before.setStart(root, 0);
            before.setEndBefore(heading);
            const said = words(heading.textContent);
            const cut = /(…|\.\.\.)\s*$/.test(title.trim());
            if ((said === wanted || (cut && said.startsWith(wanted))) && words(before.toString()) === '') {
              let gone = heading;
              const bare = n => n.nodeType === Node.COMMENT_NODE || (n.nodeType === Node.TEXT_NODE && n.nodeValue.trim() === '');
              while (gone.parentElement && gone.parentElement !== root
                     && [...gone.parentElement.childNodes].every(n => n === gone || bare(n))) {
                gone = gone.parentElement;
              }
              gone.remove();
            }
          }
          for (const img of root.querySelectorAll('img')) {
            if (/icon|logo|avatar|emoji/i.test(img.getAttribute('src') || '')) continue;
            const before = doc.createRange();
            before.setStart(root, 0);
            before.setEndBefore(img);
            if (before.toString().trim().length < 80) (img.closest('figure') || img).classList.add('mapp-lead');
            break;
          }
        }

        let article = null;
        try {
          const copy = document.cloneNode(true);
          if (isProbablyReaderable(copy)) {
            const parsed = new Readability(copy, { maxElemsToParse: limit, serializer: el => el, charThreshold: 500 }).parse();
            if (parsed && parsed.content) {
              const root = parsed.content;
              cleanArticle(root, title);
              article = {
                html: root.innerHTML,
                length: root.textContent.replace(/\s+/g, ' ').trim().length,
                lang: parsed.lang || null,
                dir: parsed.dir || null,
              };
            }
          }
        } catch (e) {}
        let mail = false;
        try { mail = mailColumn(document.body) !== null; } catch (e) {}
        return { mail, article };
        """#

    /// Answers once, with whichever of the work, the time limit and the caller's cancellation comes first.
    private nonisolated final class Outcome: Sendable {
        private enum State {
            case idle
            case waiting(CheckedContinuation<PageAnalysis, any Error>)
            case finished(Result<PageAnalysis, any Error>)
            case spent
        }

        private let state = Mutex(State.idle)

        func finish(_ result: Result<PageAnalysis, any Error>) {
            let waiting: CheckedContinuation<PageAnalysis, any Error>? = state.withLock { state in
                switch state {
                case .idle:
                    state = .finished(result)
                    return nil
                case .waiting(let continuation):
                    state = .spent
                    return continuation
                case .finished, .spent:
                    return nil
                }
            }
            waiting?.resume(with: result)
        }

        func value() async throws -> PageAnalysis {
            try await withCheckedThrowingContinuation { continuation in
                let ready: Result<PageAnalysis, any Error>? = state.withLock { state in
                    switch state {
                    case .idle:
                        state = .waiting(continuation)
                        return nil
                    case .finished(let result):
                        state = .spent
                        return result
                    case .waiting, .spent:
                        return nil
                    }
                }
                if let ready { continuation.resume(with: ready) }
            }
        }
    }
}
