import Foundation

/// How a document is told to be laid out as a mail. Marfa's catalogue has no type for a newsletter or a mail, and a
/// mail's HTML says nothing of what it is, so the layout is all there is to go by: the tools that send mail lay a
/// message out in a table of a fixed width, in inline styles, because a mail client reads nothing else.
///
/// The column is found by walking down from the body while one child holds nearly all the text, and is the first
/// table, `div` or section on that way with a width of its own between a phone's and a desktop mail client's, in its
/// `width` attribute or its inline `width` or `max-width`; the way down must have crossed a table. A web page lays its
/// column out in a style sheet, and one that does it inline without a table is not a mail's.
nonisolated enum MailColumn {
    static let narrowest = 280
    static let widest = 720

    /// Defines `mailColumn(body)` for a script: the element that is the mail's column, or null.
    static let script = """
        function mailColumn(body) {
          const lengths = new Map();
          const walker = document.createTreeWalker(body, NodeFilter.SHOW_TEXT);
          for (let node = walker.nextNode(); node; node = walker.nextNode()) {
            const parent = node.parentElement;
            if (!parent || parent.closest('script, style, template, noscript')) continue;
            const length = node.nodeValue.replace(/\\s+/g, '').length;
            if (!length) continue;
            for (let e = parent; e; e = e.parentElement) {
              lengths.set(e, (lengths.get(e) || 0) + length);
              if (e === body) break;
            }
          }
          const px = value => { const m = /^(\\d+(?:\\.\\d+)?)(?:px)?$/.exec((value || '').trim()); return m ? Number(m[1]) : null; };
          const declared = e => px(e.style.maxWidth) ?? px(e.style.width) ?? px(e.getAttribute('width'));
          let node = body, crossedTable = false;
          for (;;) {
            const total = lengths.get(node) || 0;
            let next = null, nextLength = 0;
            for (const child of node.children) {
              const length = lengths.get(child) || 0;
              if (length > nextLength) { next = child; nextLength = length; }
            }
            if (!next || nextLength < total * 0.9) return null;
            node = next;
            if (node.matches('table')) crossedTable = true;
            if (!node.matches('table, div, section, article, main')) continue;
            const width = declared(node);
            if (crossedTable && width !== null && width >= \(narrowest) && width <= \(widest)) return node;
          }
        }
        """
}
