import Foundation
import Synchronization
import WebKit

/// Finds the article in a saved HTML document, and whether it is a mail, so the item page can offer Reader only where
/// there is something to read.
///
/// The document is loaded, with none of its scripts, into a sealed page of its own that is thrown away afterwards, and
/// Mozilla's Readability (vendored under `Reader/`, with its license) runs over a copy of it in the app's own script
/// world. The document cannot reach that world, and what Readability changes is the copy, so neither the page nor the
/// stored file is touched. Apple gives apps no Reader API. A document whose content its scripts build has no article
/// here, and is shown as it is.
///
/// A document too large to parse, or one that takes longer than the limit, has no article, so the item shows the
/// original. Nothing waits on the page's thread, since the work is in the web content process; but no API ends a script
/// that is running there, so the scripts are written to end: they read the document only through `SafeDOM`, which a
/// document's names cannot turn aside, and walk it once.
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
    /// The document names its elements as it likes, and a name can stand where a built-in property should (`SafeDOM`), so
    /// the script first takes the names off what can carry one in the page it reads (the page is thrown away), and reads
    /// everything through `dom` besides. Readability, which reads the copy with plain property access, then finds
    /// nothing in its way.
    ///
    /// Of the cleanup of the article, which Reader needs and the original does not:
    /// - What can load, run or draw outside the article is removed: scripts, styles, frames, objects, embeds, templates (whose
    ///   content `querySelectorAll` cannot reach, so the whole element goes), `meta` and `base`, media, form controls
    ///   and SVG's `foreignObject`, `use`, `animate` and `set`. A form or fieldset is unwrapped and keeps its content.
    /// - Event handlers, inline styles and the attributes that make a request or carry a script are dropped. A `href`,
    ///   `xlink:href` or `src` is kept only if its address, parsed as the web view parses it (which ignores the tabs, line
    ///   breaks and control characters a pattern would miss), is `http`, `https`, `mailto` or `tel`, a relative address, or for
    ///   a picture a `data:image/` one. The document that shows the article allows no script either, so this is the second of two.
    /// - A `name` is dropped, except on an anchor, where a legacy page links to it.
    /// - An anchor is removed when it is a heading's permalink: a lone `#`, `¶` or `§`, or one marked as such, in or next to
    ///   a heading and linking to a fragment of the page or to the heading's id. Other links stay.
    /// - A backslash before a quote is removed in text, except in code, keyboard input and sample output, where it may be the code.
    /// - The first heading is removed when nothing readable comes before it and it says exactly the title, ignoring case,
    ///   punctuation and spacing, or extends a title that ends in an ellipsis. Only an ancestor left with nothing else goes with it.
    /// - A table Readability found to hold data is marked `mapp-data`, so Reader draws a grid only for those.
    /// - A picture's fixed size is dropped, so the styles size it to the column.
    /// - The first picture, when less than a sentence of text comes before it and it is not an icon, is the lead picture.
    nonisolated static let script = MailColumn.script + #"""

        // The elements through which a document can name something else, which Readability's plain reads would meet.
        function takeNamesOff() {
          for (const e of dom.queryAllInDocument(document, 'form[name], img[name], object[name], embed[name], iframe[name], input[name], select[name], textarea[name], button[name], fieldset[name], output[name]')) dom.removeAttribute(e, 'name');
          for (const e of dom.queryAllInDocument(document, 'img[id], object[id], embed[id], input[id], select[id], textarea[id], button[id], fieldset[id], output[id]')) dom.removeAttribute(e, 'id');
        }

        const removed = 'script, style, link, iframe, object, embed, template, meta, base, video, audio, input, select, textarea, button, datalist, output, dialog, foreignObject, use, animate, set';
        const dropped = new Set(['style', 'srcdoc', 'ping', 'action', 'formaction', 'poster', 'data', 'background', 'manifest', 'codebase']);

        function isSafeAddress(value, attribute) {
          let url;
          try { url = new URL(value, 'https://reader.invalid/'); } catch (e) { return false; }
          if (url.protocol === 'http:' || url.protocol === 'https:') return true;
          if (attribute === 'src') return url.protocol === 'data:' && /^data:image\//i.test(url.href);
          return url.protocol === 'mailto:' || url.protocol === 'tel:';
        }

        function cleanArticle(root, title) {
          const doc = dom.ownerDocument(root);
          for (const e of dom.queryAll(root, removed)) dom.remove(e);
          for (const e of dom.queryAll(root, 'form, fieldset')) dom.replaceWith(e, ...Array.from(dom.childNodes(e)));
          for (const e of dom.queryAll(root, '*')) {
            for (const name of dom.getAttributeNames(e)) {
              if (/^on/i.test(name) || dropped.has(name.toLowerCase())) dom.removeAttribute(e, name);
            }
            for (const name of ['href', 'src', 'xlink:href']) {
              const value = dom.getAttribute(e, name);
              if (value !== null && !isSafeAddress(value, name)) dom.removeAttribute(e, name);
            }
            if (dom.getAttribute(e, 'name') !== null && !dom.matches(e, 'a')) dom.removeAttribute(e, 'name');
            if (dom.matches(e, 'img, video, svg, canvas')) { dom.removeAttribute(e, 'width'); dom.removeAttribute(e, 'height'); }
          }
          // Readability has already told a table of data from one a mail or page lays itself out in.
          for (const t of dom.queryAll(root, 'table')) if (t._readabilityDataTable) dom.classList(t).add('mapp-data');
          const permalink = 'a.anchor, a.heading-anchor, a.header-anchor, a.headerlink, a.permalink, a[aria-label*="ermalink" i]';
          const headings = 'h1, h2, h3, h4, h5, h6';
          for (const a of dom.queryAll(root, 'a')) {
            const text = dom.textContent(a).trim();
            if (!/^[#¶§]$/.test(text) && !dom.matches(a, permalink)) continue;
            const owner = dom.closest(a, headings)
              || [dom.previousElementSibling(a), dom.nextElementSibling(a)].find(e => e && dom.matches(e, headings));
            if (!owner) continue;
            const href = dom.getAttribute(a, 'href') || '';
            let hash = null;
            if (href.includes('#')) {
              try { hash = decodeURIComponent(href.slice(href.indexOf('#') + 1)); } catch (e) { hash = href.slice(href.indexOf('#') + 1); }
            }
            if (href.startsWith('#') || (dom.getAttribute(owner, 'id') && hash === dom.getAttribute(owner, 'id'))) dom.remove(a);
          }
          const walker = dom.createTreeWalker(doc, root, NodeFilter.SHOW_TEXT);
          for (let node = walker.nextNode(); node; node = walker.nextNode()) {
            const parent = dom.parentElement(node);
            if (parent && dom.closest(parent, 'pre, code, kbd, samp, textarea')) continue;
            if (dom.nodeValue(node).includes('\\')) node.nodeValue = dom.nodeValue(node).replace(/\\(["'‘’“”])/g, '$1');
          }
          const words = s => s.toLowerCase().replace(/[^\p{L}\p{N}]+/gu, ' ').trim();
          const wanted = words(title);
          const heading = dom.query(root, headings);
          if (heading && wanted) {
            const before = dom.createRange(doc);
            before.setStart(root, 0);
            before.setEndBefore(heading);
            const said = words(dom.textContent(heading));
            const cut = /(…|\.\.\.)\s*$/.test(title.trim());
            if ((said === wanted || (cut && said.startsWith(wanted))) && words(before.toString()) === '') {
              let gone = heading;
              const bare = n => dom.nodeType(n) === Node.COMMENT_NODE || (dom.nodeType(n) === Node.TEXT_NODE && dom.nodeValue(n).trim() === '');
              for (let parent = dom.parentElement(gone); parent && parent !== root
                   && Array.from(dom.childNodes(parent)).every(n => n === gone || bare(n)); parent = dom.parentElement(gone)) {
                gone = parent;
              }
              dom.remove(gone);
            }
          }
          for (const img of dom.queryAll(root, 'img')) {
            if (/icon|logo|avatar|emoji/i.test(dom.getAttribute(img, 'src') || '')) continue;
            const before = dom.createRange(doc);
            before.setStart(root, 0);
            before.setEndBefore(img);
            if (before.toString().trim().length < 80) dom.classList(dom.closest(img, 'figure') || img).add('mapp-lead');
            break;
          }
        }

        let article = null;
        try {
          takeNamesOff();
          const copy = dom.cloneNode(document, true);
          if (isProbablyReaderable(copy)) {
            const parsed = new Readability(copy, { maxElemsToParse: limit, serializer: el => el, charThreshold: 500 }).parse();
            if (parsed && parsed.content) {
              const root = parsed.content;
              cleanArticle(root, title);
              article = {
                html: dom.innerHTML(root),
                length: dom.textContent(root).replace(/\s+/g, ' ').trim().length,
                lang: parsed.lang || null,
                dir: parsed.dir || null,
              };
            }
          }
        } catch (e) {}
        let mail = false;
        try { mail = mailColumns(dom.body(document)).length > 0; } catch (e) {}
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
