import { imageSchema } from '@milkdown/kit/preset/commonmark'
import type { Node as ProseNode } from '@milkdown/kit/prose/model'
import type { NodeView } from '@milkdown/kit/prose/view'
import { $view } from '@milkdown/kit/utils'

/** A stand-in origin to resolve a note's relative links against; nothing is fetched from it. */
const origin = 'https://notes.invalid'

/** Where the note on the page is, as a URL its relative links resolve against. */
let base = `${origin}/`
/** Images asked of the app for the note on the page, by their path in the notes folder. */
let asked = new Map<string, Promise<string | null>>()

/** The note's directory within the notes folder, empty at the top. Images are asked for again for each note,
 *  so one changed on disk shows as it now is. */
export function setImageBase(directory: string): void {
  const path = directory
    .split('/')
    .filter(Boolean)
    .map(encodeURIComponent)
    .join('/')
  base = `${origin}/${path ? `${path}/` : ''}`
  asked = new Map()
}

/** An image link's path in the notes folder; null for a link elsewhere, which the page never fetches. */
export function folderPath(src: string): string | null {
  if (!src || /^[a-z][a-z0-9+.-]*:/i.test(src) || src.startsWith('//')) return null
  try {
    const url = new URL(src, base)
    if (url.origin !== origin) return null
    return decodeURIComponent(url.pathname).replace(/^\/+/, '') || null
  } catch {
    return null
  }
}

/** The image as the app hands it over, a data URL, or null when the app has none to give. */
function image(path: string): Promise<string | null> {
  let answer = asked.get(path)
  if (!answer) {
    const files = window.webkit?.messageHandlers?.files
    answer = files ? files.postMessage(path).catch(() => null) : Promise.resolve(null)
    asked.set(path, answer)
  }
  return answer
}

/** An image the notes folder holds shows as itself; any other shows what it was called, and the markdown keeps
 *  the image as written either way. */
class ImageView implements NodeView {
  dom: HTMLElement

  constructor(node: ProseNode) {
    this.dom = document.createElement('span')
    this.render(node)
  }

  update(node: ProseNode): boolean {
    if (node.type.name !== 'image') return false
    this.render(node)
    return true
  }

  ignoreMutation(): boolean {
    return true
  }

  private render(node: ProseNode): void {
    const src = String(node.attrs.src || '')
    const name = String(node.attrs.alt || '') || src
    const path = folderPath(src)
    // The name shows until the image arrives, and stays when there is none: a file that is not there, not an
    // image, or outside the notes folder.
    this.absent(name)
    if (!path) return
    void image(path).then((data) => {
      if (!data || this.dom.textContent !== name) return
      const element = document.createElement('img')
      element.src = data
      element.alt = name
      element.draggable = false
      this.dom.className = 'image'
      this.dom.replaceChildren(element)
    })
  }

  private absent(name: string): void {
    this.dom.className = 'image-absent'
    this.dom.textContent = name
  }
}

export const imageView = $view(imageSchema.node, () => (node) => new ImageView(node))
