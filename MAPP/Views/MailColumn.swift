import Foundation

/// How a document is told to be laid out as a mail. Marfa's catalogue has no type for a newsletter or a mail, and a
/// mail's HTML says nothing of what it is, so the layout is all there is to go by: the tools that send mail lay a
/// message out in a table of a fixed width, in inline styles, because a mail client reads nothing else.
///
/// The column is found by walking down from the body while one child holds nearly all the text. It is the first
/// table, `div` or section on that way with a width of its own between a phone's and a desktop mail client's, in its
/// `width` attribute or its inline `width` or `max-width`; the way down must have crossed a table. Where no child
/// holds nearly all the text but the text is in sibling tables of one such width (the usual header, body and footer
/// of a template), the tables together are the column. A web page lays its column out in a style sheet, and one that
/// does it inline without a table is not a mail's.
///
/// A page whose column has a sidebar is not a mail: another cell in a row the column sits in holds text or a picture
/// of its own. A mail's spacer cells hold neither.
///
/// The walk reads the document only through `SafeDOM`, once, and never asks an element for its children, so a document
/// that names its elements after properties cannot send it anywhere.
nonisolated enum MailColumn {
    static let narrowest = 280
    static let widest = 720
    /// The most elements and text nodes the walk reads before it gives the document up as no mail.
    static let walkLimit = 100_000
    /// The least width and height, in pixels, of a picture that makes a cell more than a spacer.
    static let smallestPicture = 24

    /// Defines `mailColumns(body)` for a script: the elements that are the mail's column, or an empty array.
    static let script = SafeDOM.script + #"""

        function mailColumns(body) {
          if (!body) return [];
          const elements = [body], index = new Map([[body, 0]]), parentOf = [-1], own = [0];
          const walker = dom.createTreeWalker(document, body, NodeFilter.SHOW_ELEMENT | NodeFilter.SHOW_TEXT, {
            acceptNode: node => dom.nodeType(node) === Node.ELEMENT_NODE && dom.matches(node, 'script, style, template, noscript')
              ? NodeFilter.FILTER_REJECT : NodeFilter.FILTER_ACCEPT,
          });
          let read = 0;
          for (let node = walker.nextNode(); node; node = walker.nextNode()) {
            if (++read > \#(walkLimit)) return [];
            const parent = index.get(dom.parentElement(node));
            if (parent === undefined) continue;
            if (dom.nodeType(node) === Node.ELEMENT_NODE) {
              index.set(node, elements.length);
              elements.push(node);
              parentOf.push(parent);
              own.push(0);
            } else {
              own[parent] += node.nodeValue.replace(/\s+/g, '').length;
            }
          }
          // Each element's text is its own and its children's; a child comes after its parent, so one pass back does it.
          const total = own.slice();
          const kids = elements.map(() => []);
          for (let i = elements.length - 1; i > 0; i--) total[parentOf[i]] += total[i];
          for (let i = 1; i < elements.length; i++) kids[parentOf[i]].push(i);
          const px = value => { const m = /^(\d+(?:\.\d+)?)(?:px)?$/.exec((value || '').trim()); return m ? Number(m[1]) : null; };
          const declared = e => {
            let style = null;
            try { style = dom.style(e); } catch (x) {}
            return px(style && style.maxWidth) ?? px(style && style.width) ?? px(dom.getAttribute(e, 'width'));
          };
          const inRange = width => width !== null && width >= \#(narrowest) && width <= \#(widest);
          const isPicture = img => {
            const [width, height] = [px(dom.getAttribute(img, 'width')), px(dom.getAttribute(img, 'height'))];
            return width !== null && height !== null && width >= \#(smallestPicture) && height >= \#(smallestPicture);
          };
          const hasSidebar = start => {
            for (let i = start; i > 0; i = parentOf[i]) {
              if (!dom.matches(elements[i], 'td, th')) continue;
              for (const other of kids[parentOf[i]]) {
                if (other === i || !dom.matches(elements[other], 'td, th')) continue;
                if (total[other] > 0 || Array.from(dom.queryAll(elements[other], 'img')).some(isPicture)) return true;
              }
            }
            return false;
          };
          const found = columns => columns.length && !hasSidebar(columns[0]) ? columns.map(i => elements[i]) : [];
          let node = 0, crossedTable = false;
          for (;;) {
            let next = -1, best = 0;
            for (const kid of kids[node]) if (total[kid] > best) { next = kid; best = total[kid]; }
            if (next < 0 || best < total[node] * 0.9) {
              // The usual template: a header, a body and a footer, as tables of one width one after another.
              const holders = kids[node].filter(kid => total[kid] > 0);
              const widths = holders.map(kid => declared(elements[kid]));
              const together = holders.reduce((sum, kid) => sum + total[kid], 0);
              const tables = holders.length > 1 && holders.every(kid => dom.matches(elements[kid], 'table'))
                && together >= total[node] * 0.9 && inRange(widths[0]) && widths.every(width => width === widths[0]);
              return tables ? found(holders) : [];
            }
            node = next;
            if (dom.matches(elements[node], 'table')) crossedTable = true;
            if (!dom.matches(elements[node], 'table, div, section, article, main')) continue;
            if (crossedTable && inRange(declared(elements[node]))) return found([node]);
          }
        }
        """#
}
