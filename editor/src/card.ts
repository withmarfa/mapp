import { postToHost } from './bridge'

/** What a link's card is for: an item the app named on a row, a foot row or a chip (`data-card-item`), or a link in the
 *  text, which only the app can say what it means (as authored). */
export interface CardTarget {
  kind: 'item' | 'wiki'
  /** An item's identity, or a link as authored. */
  link: string
}

const selector = '[data-card-item], [data-inkkit-wiki]'

/** The linked item under `node`, or null where it holds none. A link to the page's own heading names no item. */
export function cardTargetAt(
  node: EventTarget | null,
): { target: CardTarget; element: Element } | null {
  const element = (node as Element | null)?.closest?.(selector)
  if (!element) return null
  const id = element.getAttribute('data-card-item')
  if (id) return { target: { kind: 'item', link: id }, element }
  const name = element.getAttribute('data-inkkit-wiki')
  const raw = element.getAttribute('data-inkkit-wiki-raw')
  return name && raw ? { target: { kind: 'wiki', link: raw }, element } : null
}

/** The frame the card sits under: the part of a link that wraps onto lines which the pointer is over. */
function frameOf(element: Element, x: number, y: number): DOMRect {
  const rects = [...element.getClientRects()]
  return (
    rects.find((rect) => x >= rect.left && x <= rect.right && y >= rect.top && y <= rect.bottom) ??
    element.getBoundingClientRect()
  )
}

/** Tells the app which linked item the pointer rests on and when it leaves, for the card the app draws after a pause. The
 *  page times nothing and draws nothing, takes no focus and no key; it ends the card at once on a scroll, a key, a click
 *  or when the window loses the pointer, and the app does the same. */
export function watchCards(page: () => string | undefined): void {
  let current: Element | undefined
  const end = () => {
    if (!current) return
    current = undefined
    postToHost({ type: 'cardEnd' })
  }
  document.addEventListener('pointerover', (event) => {
    if (event.pointerType !== 'mouse' || event.buttons !== 0) return end()
    const found = cardTargetAt(event.target)
    const item = page()
    if (!found || !item) return end()
    if (found.element === current) return
    current = found.element
    const rect = frameOf(found.element, event.clientX, event.clientY)
    postToHost({
      type: 'cardHover',
      item,
      card: found.target,
      rect: [rect.left, rect.top, rect.width, rect.height],
      viewportHeight: window.innerHeight,
    })
  })
  document.addEventListener('pointerout', (event) => {
    if (!current) return
    const into = event.relatedTarget as Node | null
    if (into && current.contains(into)) return
    end()
  })
  for (const name of ['pointerdown', 'keydown', 'wheel', 'contextmenu', 'dragstart']) {
    document.addEventListener(name, end, { capture: true, passive: true })
  }
  // The page scrolls in its body, so a scroll anywhere in the document ends it.
  document.addEventListener('scroll', end, { capture: true, passive: true })
  window.addEventListener('blur', end)
}
