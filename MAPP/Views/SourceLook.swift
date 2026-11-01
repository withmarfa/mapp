import Foundation

/// Which of its two looks a source's HTML is shown in.
nonisolated enum SourceViewMode: String, CaseIterable, Identifiable, Sendable {
    /// The article in MAPP's own text styles and column, without the source's styling or its artifacts.
    case reader
    /// The source's own HTML, under a baseline that only fills in what the source leaves unsaid.
    case original

    var id: String { rawValue }

    /// One choice for every such item, kept like the page's other settings: a person who reads articles in one look
    /// wants the next article in it too, as Readwise Reader keeps the look a person last chose.
    static let key = "sourceViewMode"
    static let standard = SourceViewMode.reader
    /// Whether the original look runs the full width of the window rather than the text column.
    static let wideKey = "sourceOriginalWide"
    static let wideStandard = false
}

/// How an HTML document from a source is to look, applied by the app's own script after the document has loaded (so it
/// works whether or not the document's scripts run, and none of the document's can see it). The document itself is
/// never rewritten on disk or in the library.
///
/// Both looks lay the document out in the text column of a note's page (`PageStyle.horizontalInset`), as CSS so it
/// follows the window as it resizes; only `wide` sets the original look free of it. The reader look also restyles the
/// document in the note page's text size and removes what a source adds that is not the article: its own styles, a "#"
/// link after each heading, backslashes before quotes, and a leading heading that only repeats the item's title.
nonisolated struct SourceLook: Equatable, Sendable {
    var mode: SourceViewMode
    /// The item's title, to drop a heading that repeats it.
    var title: String
    var textSize: Int
    var readingWidth: Int
    /// The original look runs the full width of the window; the reader look follows the page's own width setting.
    var wide: Bool

    init(mode: SourceViewMode, title: String, page: PageStyle, originalWide: Bool) {
        self.mode = mode
        self.title = title
        textSize = page.textSize
        readingWidth = page.readingWidth
        wide = mode == .original ? originalWide : page.fullWidth
    }

    /// The margin on each side of the text: the note page's rule, as a CSS length.
    var inset: String {
        let minimum = textSize * 3
        guard !wide else { return "\(minimum)px" }
        return "max(\(minimum)px, calc((100vw - \(readingWidth * textSize)px) / 2))"
    }

    /// The style sheet to add to the document.
    var css: String {
        // Rules in a layer lose to any the document writes itself, so the original look keeps the source's design where
        // it has one and fills in where it has none. The reader look drops the source's styles and has no one to lose to.
        let typography = """
            :root { color-scheme: light dark; }
            body { font: \(textSize)px/1.6 -apple-system, system-ui, sans-serif; color: CanvasText; overflow-wrap: break-word; }
            img, video, svg, canvas { max-width: 100%; height: auto; }
            table { max-width: 100%; }
            pre { overflow-x: auto; }
            """
        let layout = """
            html { box-sizing: border-box; margin: 0; padding: 16px \(inset) 48px; }
            body { margin: 0; }
            """
        switch mode {
        case .original:
            return "@layer mapp { \(typography) }\n\(layout)"
        case .reader:
            return typography + "\n" + layout + "\n" + Self.readerRules(textSize: textSize)
        }
    }

    private static func readerRules(textSize: Int) -> String {
        """
        html { background: Canvas; }
        p, ul, ol, pre, table, figure, blockquote, dl { margin: 0 0 1em; }
        h1, h2, h3, h4, h5, h6 { line-height: 1.25; margin: 1.6em 0 0.5em; font-weight: 600; }
        h1 { font-size: 1.6em; } h2 { font-size: 1.35em; } h3 { font-size: 1.15em; } h4, h5, h6 { font-size: 1em; }
        a { color: AccentColor; text-decoration: none; }
        ul, ol { padding-inline-start: 1.6em; }
        li { margin: 0.25em 0; }
        li > ul, li > ol { margin-bottom: 0; }
        img, video, svg { display: block; margin: 1.2em 0; border-radius: 6px; }
        figure { margin: 1.2em 0; }
        figcaption { color: GrayText; font-size: 0.85em; margin-top: 0.5em; }
        blockquote { padding-inline-start: 1em; border-inline-start: 3px solid color-mix(in srgb, CanvasText 20%, transparent); color: GrayText; }
        pre, code { font: 0.9em ui-monospace, Menlo, monospace; }
        pre { padding: 0.8em 1em; border-radius: 6px; background: color-mix(in srgb, CanvasText 7%, transparent); }
        :not(pre) > code { padding: 0.1em 0.3em; border-radius: 4px; background: color-mix(in srgb, CanvasText 7%, transparent); }
        table { display: block; overflow-x: auto; border-collapse: collapse; }
        th, td { border: 1px solid color-mix(in srgb, CanvasText 18%, transparent); padding: 0.35em 0.6em; text-align: start; }
        hr { border: 0; border-top: 1px solid color-mix(in srgb, CanvasText 18%, transparent); margin: 2em 0; }
        """
    }

    /// The script that applies the look. It takes `css`, `reader` and `title` as arguments and runs in the app's own
    /// content world.
    ///
    /// Of the reader look's cleanup:
    /// - An anchor is removed when it is a heading's permalink: a lone `#`, `¶` or `§`, or one marked as such, in or next to
    ///   a heading and linking to a fragment of the page or to the heading's id. Other links stay.
    /// - A backslash before a quote is removed in text, except in code, keyboard input and sample output, where it may be the code.
    /// - The first heading is removed when nothing readable comes before it and it says exactly the title, ignoring case,
    ///   punctuation and spacing, or extends a title that ends in an ellipsis. Only an ancestor left with nothing else goes with it.
    nonisolated static let script = """
        const sheet = document.createElement('style');
        sheet.textContent = css;
        if (reader) {
          for (const e of document.querySelectorAll('style, link[rel~="stylesheet"]')) e.remove();
          for (const e of document.querySelectorAll('[style]')) e.removeAttribute('style');
          for (const e of document.querySelectorAll('[width], [height]')) {
            if (e.matches('img, video, svg, canvas, iframe')) { e.removeAttribute('width'); e.removeAttribute('height'); }
          }
          const permalink = 'a.anchor, a.heading-anchor, a.header-anchor, a.headerlink, a.permalink, a[aria-label*="ermalink" i]';
          const headings = 'h1, h2, h3, h4, h5, h6';
          for (const a of document.querySelectorAll('a')) {
            const text = a.textContent.trim();
            if (!/^[#¶§]$/.test(text) && !a.matches(permalink)) continue;
            const owner = a.closest(headings)
              || [a.previousElementSibling, a.nextElementSibling].find(e => e && e.matches(headings));
            if (!owner) continue;
            const href = a.getAttribute('href') || '';
            const hash = href.includes('#') ? decodeURIComponent(href.slice(href.indexOf('#') + 1)) : null;
            if (href.startsWith('#') || (owner.id && hash === owner.id)) a.remove();
          }
          const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
          for (let node = walker.nextNode(); node; node = walker.nextNode()) {
            if (node.parentElement && node.parentElement.closest('pre, code, kbd, samp, script, style, textarea')) continue;
            if (node.nodeValue.includes('\\\\')) node.nodeValue = node.nodeValue.replace(/\\\\(["'\\u2018\\u2019\\u201C\\u201D])/g, '$1');
          }
          const words = s => s.toLowerCase().replace(/[^\\p{L}\\p{N}]+/gu, ' ').trim();
          const wanted = words(title);
          const heading = document.body.querySelector('h1, h2, h3, h4, h5, h6');
          if (heading && wanted) {
            const before = document.createRange();
            before.setStart(document.body, 0);
            before.setEndBefore(heading);
            const said = words(heading.textContent);
            const cut = /(\\u2026|\\.\\.\\.)\\s*$/.test(title.trim());
            const repeats = said === wanted || (cut && said.startsWith(wanted));
            if (repeats && words(before.toString()) === '') {
              let gone = heading;
              const bare = n => n.nodeType === Node.COMMENT_NODE || (n.nodeType === Node.TEXT_NODE && n.nodeValue.trim() === '');
              while (gone.parentElement && gone.parentElement !== document.body
                     && [...gone.parentElement.childNodes].every(n => n === gone || bare(n))) {
                gone = gone.parentElement;
              }
              gone.remove();
            }
          }
        }
        (document.head || document.documentElement).append(sheet);
        """
}
