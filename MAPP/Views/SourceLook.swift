import Foundation

/// Which of its two looks a source's HTML is shown in, where it has an article to read.
nonisolated enum SourceViewMode: String, CaseIterable, Identifiable, Sendable {
    /// The article in MAPP's own text styles and column, without the source's styling or its artifacts.
    case reader
    /// The source's own page, as it was written.
    case original

    var id: String { rawValue }

    /// One choice for every such item, kept like the page's other settings: a person who reads articles in one look
    /// wants the next article in it too, as Readwise Reader keeps the look a person last chose.
    static let key = "sourceViewMode"
    static let standard = SourceViewMode.reader
}

/// How an HTML document from a source is to look, applied by the app's own script after the document has loaded (so it
/// works whether or not the document's scripts run, and none of the document's can see it). The document itself is
/// never rewritten on disk or in the library.
///
/// - Reader is the document `ReaderDocument` makes of the article (`PageAnalyzer` has already cleaned it): the note
///   page's text size in a serif, in the text column of a note's page (`PageStyle.horizontalInset`), as CSS so it follows
///   the window as it resizes. It sits on the window's own background.
/// - Original is the document as written, at its own width. Only a document that says nothing about its look, with no
///   style, color or background of its own, is given a baseline and the text column, since it has no look to keep;
///   everything else keeps its design, and its light background keeps its text readable in dark mode because the
///   baseline's colors that follow the system are never added to it.
/// - A mail (`MailColumn`) is Original with its column centered, on the surface behind pages (`isOnSurface`). It keeps
///   its own colors: a mail that paints its page, its body or its column paints it still, and a column that nothing
///   paints is given white only if its text is dark. A fully transparent color paints nothing, and neither does a picture
///   at a web address, which the seal blocks. The color that counts is the one most of the text is written in.
nonisolated struct SourceLook: Equatable, Sendable {
    var mode: SourceViewMode
    var isMail: Bool
    var textSize: Int
    var readingWidth: Int
    /// The text runs the window's width, as the page's setting says.
    var wide: Bool

    init(mode: SourceViewMode, isMail: Bool, page: PageStyle) {
        self.mode = mode
        self.isMail = isMail && mode == .original
        textSize = page.textSize
        readingWidth = page.readingWidth
        wide = page.fullWidth
    }

    /// Whether the mail sits on the gray surface that lies behind pages.
    var isOnSurface: Bool { isMail }

    /// Whether the web view is to paint no background of its own, so the window's shows (Reader) or the surface's (a mail).
    /// A page paints its own.
    var leavesBackground: Bool { mode == .reader || isMail }

    /// The margin on each side of the text: the note page's rule, as a CSS length.
    var inset: String {
        let minimum = textSize * 3
        guard !wide else { return "\(minimum)px" }
        return "max(\(minimum)px, calc((100vw - \(readingWidth * textSize)px) / 2))"
    }

    /// The style sheet to add to the document.
    var css: String {
        switch mode {
        case .reader: return readerRules
        case .original: return isMail ? Self.mailRules : ""
        }
    }

    /// The baseline for a document that says nothing about its look. Rules in a layer lose to any the document writes.
    var plain: String {
        """
        @layer mapp {
          :root { color-scheme: light dark; }
          html { box-sizing: border-box; margin: 0; padding: 16px \(inset) 48px; }
          body { margin: 0; font: \(textSize)px/1.6 -apple-system, system-ui, sans-serif; color: CanvasText; overflow-wrap: break-word; }
          img, video, svg, canvas { max-width: 100%; height: auto; }
          table { max-width: 100%; }
          pre { overflow-x: auto; }
        }
        """
    }

    private static let mailRules = "[data-mapp-mail] { margin-left: auto; margin-right: auto; float: none; }"

    /// The board's prose: New York at 14.6 for every 13 of the page's text, a 1.65 line, headings in the same serif.
    private var readerRules: String {
        let size = String(format: "%.1f", Double(textSize) * 14.6 / 13)
        return """
            :root { color-scheme: light dark; }
            html { box-sizing: border-box; margin: 0; padding: 16px \(inset) 48px; }
            body { margin: 0; font: \(size)px/1.65 "New York", ui-serif, Georgia, serif; color: CanvasText; text-align: start; overflow-wrap: break-word; }
            p, ul, ol, pre, table, figure, blockquote, dl { margin: 0 0 0.75em; }
            h1, h2, h3, h4, h5, h6 { line-height: 1.3; margin: 1.4em 0 0.4em; font-weight: 700; text-wrap: balance; }
            h1 { font-size: 1.5em; } h2 { font-size: 1.2em; } h3 { font-size: 1.03em; } h4, h5, h6 { font-size: 1em; }
            a { color: AccentColor; text-decoration: none; }
            ul, ol { padding-inline-start: 1.5em; }
            li { margin: 0 0 0.25em; }
            li::marker { color: AccentColor; }
            li > ul, li > ol { margin-bottom: 0; }
            img, video, svg { display: block; max-width: 100%; height: auto; margin: 0.8em 0; border-radius: 6px; }
            figure { margin: 0 0 0.75em; }
            figcaption { margin-top: 8px; color: GrayText; font: 0.79em/1.4 -apple-system, system-ui, sans-serif; }
            .mapp-lead { display: block; margin: 0 0 1.5em; }
            figure.mapp-lead img, img.mapp-lead { width: 100%; margin: 0; border-radius: 12px; }
            blockquote { margin-inline: 0; padding-inline-start: 1em; border-inline-start: 3px solid color-mix(in srgb, CanvasText 20%, transparent); color: GrayText; }
            pre, code { font: 0.77em ui-monospace, Menlo, monospace; }
            pre { padding: 10px 12px; border-radius: 8px; background: color-mix(in srgb, CanvasText 7%, transparent); white-space: pre-wrap; }
            :not(pre) > code { padding: 1px 4px; border-radius: 4px; background: color-mix(in srgb, CanvasText 7%, transparent); }
            table.mapp-data { display: block; overflow-x: auto; border-collapse: collapse; font-size: 0.86em; }
            .mapp-data th, .mapp-data td { border: 1px solid color-mix(in srgb, CanvasText 18%, transparent); padding: 7px 12px; text-align: start; vertical-align: top; }
            table:not(.mapp-data), table:not(.mapp-data) :is(thead, tbody, tfoot, tr, th, td) { display: block; width: auto; max-width: 100%; padding: 0; }
            hr { border: 0; border-top: 1px solid color-mix(in srgb, CanvasText 18%, transparent); margin: 2em 0; }
            """
    }

    /// Anything a document writes to say how it looks. A style sheet counts only where the document holds it; one it
    /// names on the web never loads, so a document with nothing else has no look to keep.
    private static let styled = "style, link[rel~=\"stylesheet\"][href^=\"data:\" i], [style], [bgcolor], [background], [text], font[color], font[face]"

    /// The script that applies the look. It takes `css`, `plain`, `mail` and `reader` as arguments and runs in the app's
    /// own content world.
    nonisolated static let script = MailColumn.script + """

        const sheet = dom.createElement(document, 'style');
        let text = css;
        if (!reader) {
          if (mail) {
            // A pixel reads every color the engine computes, such as oklch(). The black comes first because a color
            // the canvas refused must read as dark: read as light, it would leave dark text on the dark surface.
            const pixel = dom.createElement(document, 'canvas').getContext('2d', { willReadFrequently: true });
            const channels = color => {
              pixel.clearRect(0, 0, 1, 1);
              pixel.fillStyle = '#000';
              pixel.fillStyle = color;
              pixel.fillRect(0, 0, 1, 1);
              return pixel.getImageData(0, 0, 1, 1).data;
            };
            const luminance = color => {
              const [red, green, blue] = channels(color);
              return (0.2126 * red + 0.7152 * green + 0.0722 * blue) / 255;
            };
            // A mail's own color, from a bgcolor attribute or a style sheet, is what the person is to see; the
            // surface behind the pages shows only where nothing paints, and white is only given there to text that
            // is dark, since light text was written for a page of its own. The seal blocks a picture at a web address,
            // so only a gradient or a picture the document holds stands behind the text.
            const paints = e => {
              const style = getComputedStyle(e);
              return channels(style.backgroundColor)[3] > 0 || /gradient\\(|url\\("?data:/i.test(style.backgroundImage);
            };
            // The column's own color says nothing of text written in another: in a document that follows the system
            // the column's is light in dark mode, whatever color its paragraphs are given.
            const textColor = column => {
              const held = new Map();
              const walker = dom.createTreeWalker(document, column, NodeFilter.SHOW_TEXT);
              let read = 0;
              for (let node = walker.nextNode(); node && read < 500; node = walker.nextNode()) {
                const length = dom.nodeValue(node).trim().length;
                const parent = dom.parentElement(node);
                if (!length || !parent || !dom.checkVisibility(parent, { opacityProperty: true, visibilityProperty: true })) continue;
                read++;
                const color = getComputedStyle(parent).color;
                held.set(color, (held.get(color) || 0) + length);
              }
              return Array.from(held).sort((a, b) => b[1] - a[1])[0]?.[0] ?? getComputedStyle(column).color;
            };
            for (const column of mailColumns(dom.body(document))) {
              dom.setAttribute(column, 'data-mapp-mail', '');
              let painted = false;
              for (let e = column; e && !painted; e = dom.parentElement(e)) painted = paints(e);
              if (!painted && luminance(textColor(column)) < 0.5) {
                dom.style(column).backgroundColor = '#fff';
                // Text with no color of its own still follows the system, and would be light on the white.
                if (luminance(getComputedStyle(column).color) >= 0.5) dom.style(column).color = '#000';
              }
            }
          }
          if (!dom.queryInDocument(document, '\(styled)')) text += '\\n' + plain;
        }
        sheet.textContent = text;
        dom.append(dom.head(document) || dom.documentElement(document), sheet);
        """

    var arguments: [String: Any] { ["css": css, "plain": plain, "mail": isMail, "reader": mode == .reader] }
}
