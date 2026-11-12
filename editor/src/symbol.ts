import type { HeaderIcon } from './header'

/** Draws a symbol the app made as a mask on an element, so it takes the element's color. */
export function maskWith(element: HTMLElement, icon: HeaderIcon): void {
  element.style.width = `${icon.width}px`
  element.style.height = `${icon.height}px`
  element.style.setProperty('-webkit-mask-image', `url("${icon.url}")`)
  element.style.maskImage = `url("${icon.url}")`
}

/** Shows a symbol in `glyph`, or hides `glyph` while the app has not sent it. */
export function showSymbol(glyph: HTMLElement, icon: HeaderIcon | undefined): void {
  glyph.hidden = !icon
  if (icon) maskWith(glyph, icon)
}

/** A button whose only content is a symbol: it shows once the symbol has arrived, and is hidden until then, so it
 *  is never an empty circle. */
export function showSymbolButton(
  button: HTMLElement,
  glyph: HTMLElement,
  icon: HeaderIcon | undefined,
): void {
  showSymbol(glyph, icon)
  button.hidden = !icon
}
