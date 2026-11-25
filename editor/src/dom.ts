/** A symbol the app drew, as an image the page uses as a mask so it takes the text's color. */
export interface HeaderIcon {
  url: string
  width: number
  height: number
}

export function element<K extends keyof HTMLElementTagNameMap>(
  tag: K,
  className: string,
  parent?: HTMLElement,
): HTMLElementTagNameMap[K] {
  const node = document.createElement(tag)
  node.className = className
  parent?.append(node)
  return node
}

/** A symbol the app drew, as a mask in the tone's color. */
export function maskSymbol(node: HTMLElement, icon: HeaderIcon | undefined) {
  node.hidden = !icon
  if (!icon) return
  node.style.setProperty('-webkit-mask-image', `url("${icon.url}")`)
  node.style.maskImage = `url("${icon.url}")`
}

/** Gives a chip the tone the app named, from the custom properties the app sent (`--tone-<name>`); the page chooses no
 *  color. A name that is not a word leaves the chip with no tone. */
export function useTone(node: HTMLElement, name: string | null | undefined) {
  if (!name || !/^[a-z]+$/.test(name)) {
    node.style.removeProperty('--tone')
    return
  }
  node.style.setProperty('--tone', `var(--tone-${name})`)
}
