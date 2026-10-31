/** The address of the first link the selection touches, as written in the document, or null where it touches none.
 *  Inkkit's caret state names the link mark but not its address, so the Link sheet reads it from the links the page
 *  draws. A selection of a link's text can start in the text before it, so the range is tested against each link
 *  rather than its start. */
export function linkAddressAtSelection(root: HTMLElement): string | null {
  const selection = root.ownerDocument.defaultView?.getSelection()
  if (!selection || selection.rangeCount === 0) return null
  const range = selection.getRangeAt(0)
  for (const link of root.querySelectorAll('a[href]')) {
    if (range.intersectsNode(link)) return link.getAttribute('href')
  }
  return null
}
