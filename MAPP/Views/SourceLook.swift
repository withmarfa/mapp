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
///   style, colour or background of its own, is given a baseline and the text column, since it has no look to keep;
///   everything else keeps its design, and its light background keeps its text readable in dark mode because the
///   baseline's colours that follow the system are never added to it.
/// - A mail (`MailColumn`) is Original with its column centred, on the surface behind pages (`isOnSurface`); the column
///   is given white only where the mail paints no background of its own there.
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

    /// Whether the mail sits on the grey surface that lies behind pages.
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

    private static let mailRules = """
        @layer mapp {
          html, body { background: transparent; }
        }
        [data-mapp-mail] { margin-left: auto; margin-right: auto; float: none; }
        """

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
            table { display: block; overflow-x: auto; border-collapse: collapse; font-size: 0.86em; }
            th, td { border: 1px solid color-mix(in srgb, CanvasText 18%, transparent); padding: 7px 12px; text-align: start; vertical-align: top; }
            hr { border: 0; border-top: 1px solid color-mix(in srgb, CanvasText 18%, transparent); margin: 2em 0; }
            """
    }

    /// Anything a document writes to say how it looks.
    private static let styled = "style, link[rel~=\"stylesheet\"], [style], [bgcolor], [background], [text], font[color], font[face]"

    /// The script that applies the look. It takes `css`, `plain`, `mail` and `reader` as arguments and runs in the app's
    /// own content world.
    nonisolated static let script = MailColumn.script + """

        const sheet = document.createElement('style');
        let text = css;
        if (!reader) {
          if (mail) {
            const column = mailColumn(document.body);
            if (column) {
              column.setAttribute('data-mapp-mail', '');
              // A mail's own colour, even from a bgcolor attribute, beats any rule here, so the white is only
              // given where the column paints nothing.
              if (getComputedStyle(column).backgroundColor === 'rgba(0, 0, 0, 0)') column.style.backgroundColor = '#fff';
            }
          }
          if (!document.querySelector('\(styled)')) text += '\\n' + plain;
        }
        sheet.textContent = text;
        (document.head || document.documentElement).append(sheet);
        """

    var arguments: [String: Any] { ["css": css, "plain": plain, "mail": isMail, "reader": mode == .reader] }
}
