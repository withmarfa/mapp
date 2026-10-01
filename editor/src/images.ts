import { imageSchema } from '@milkdown/kit/preset/commonmark'
import type { Node as ProseNode } from '@milkdown/kit/prose/model'
import type { EditorView, NodeView } from '@milkdown/kit/prose/view'
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
  const path = directory.split('/').filter(Boolean).map(encodeURIComponent).join('/')
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

/** The image as the app hands it over, a data URL, or null when the app has none to give. Only an answer with
 *  an image is kept, since a file just pasted may not be written yet. */
function image(path: string): Promise<string | null> {
  let answer = asked.get(path)
  if (!answer) {
    const files = window.webkit?.messageHandlers?.files
    answer = (files ? files.postMessage(path).catch(() => null) : Promise.resolve(null)).then(
      (data) => {
        if (!data) asked.delete(path)
        return data
      },
    )
    asked.set(path, answer)
  }
  return answer
}

/** How long to wait before asking again for an image that was not there, as when it is still being written. */
const retries = [250, 1000]

/** A width rides in the alt text, as `![a picture|400](../Attachments/….png)`, the form Obsidian reads.
 *  Anything else reading the note shows the picture and keeps the number, which is what a plain markdown file
 *  has to do. */
export function splitAlt(alt: string): { alt: string; width: number | null } {
  const match = /^([\s\S]*)\|(\d{1,5})$/.exec(alt)
  if (!match) return { alt, width: null }
  return { alt: match[1] ?? '', width: Number(match[2]) }
}

export function joinAlt(alt: string, width: number | null): string {
  return width == null ? alt : `${alt}|${width}`
}

const minimumWidth = 48

/** An image the notes folder holds shows as itself, at the width its alt text gives and never wider than the
 *  page, with a handle on its trailing edge that sizes it. Any other shows what it was called, and the
 *  markdown keeps the image as written either way. */
class ImageView implements NodeView {
  dom: HTMLElement
  /** The image this view shows or is waiting for, so an answer for one it no longer shows is not painted. */
  private path: string | null = null
  private image?: HTMLImageElement
  private width: number | null = null

  constructor(
    private node: ProseNode,
    private readonly view: EditorView,
    private readonly getPos: () => number | undefined,
  ) {
    this.dom = document.createElement('span')
    this.render()
  }

  update(node: ProseNode): boolean {
    if (node.type !== this.node.type) return false
    const same = node.attrs.src === this.node.attrs.src && node.attrs.alt === this.node.attrs.alt
    this.node = node
    // Most updates are the document changing around the image; redrawing it for those would flash its name.
    if (!same) this.render()
    return true
  }

  /** The handle's own events are the view's to handle, not the document's. */
  stopEvent(event: Event): boolean {
    return event.target instanceof HTMLElement && event.target.classList.contains('image-handle')
  }

  ignoreMutation(): boolean {
    return true
  }

  private render(): void {
    const src = String(this.node.attrs.src || '')
    const { alt, width } = splitAlt(String(this.node.attrs.alt || ''))
    const name = alt || src
    const path = folderPath(src)
    this.width = width
    // The name shows until the image arrives, and stays when there is none: a file that is not there, not an
    // image, or outside the notes folder.
    this.absent(name)
    this.path = path
    if (path) this.show(path, name, 0)
  }

  private show(path: string, name: string, attempt: number): void {
    void image(path).then((data) => {
      if (this.path !== path) return
      if (!data) {
        const delay = retries[attempt]
        if (delay != null)
          setTimeout(() => this.path === path && this.show(path, name, attempt + 1), delay)
        return
      }
      const element = document.createElement('img')
      element.src = data
      element.alt = name
      element.draggable = false
      if (this.width != null) element.style.width = `${this.width}px`
      const handle = document.createElement('span')
      handle.className = 'image-handle'
      handle.addEventListener('pointerdown', this.startResize)
      this.image = element
      this.dom.className = 'image'
      this.dom.replaceChildren(element, handle)
    })
  }

  private absent(name: string): void {
    this.image = undefined
    this.dom.className = 'image-absent'
    this.dom.textContent = name
  }

  private startResize = (event: PointerEvent): void => {
    const image = this.image
    if (!image || !this.view.editable) return
    event.preventDefault()
    const handle = event.currentTarget as HTMLElement
    const startX = event.clientX
    const startWidth = image.getBoundingClientRect().width
    // The width the text runs to, inside the page's margins.
    const style = getComputedStyle(this.view.dom)
    const limit =
      this.view.dom.clientWidth - parseFloat(style.paddingLeft) - parseFloat(style.paddingRight)
    handle.setPointerCapture?.(event.pointerId)
    const move = (moved: PointerEvent) => {
      const next = Math.round(
        Math.min(limit, Math.max(minimumWidth, startWidth + (moved.clientX - startX))),
      )
      this.width = next
      image.style.width = `${next}px`
    }
    const done = () => {
      handle.removeEventListener('pointermove', move)
      handle.removeEventListener('pointerup', done)
      handle.removeEventListener('pointercancel', done)
      this.commit()
    }
    handle.addEventListener('pointermove', move)
    handle.addEventListener('pointerup', done)
    handle.addEventListener('pointercancel', done)
  }

  /** One drag is one edit, and so one step to undo. */
  private commit(): void {
    const pos = this.getPos()
    if (pos == null) return
    const { alt } = splitAlt(String(this.node.attrs.alt ?? ''))
    const next = joinAlt(alt, this.width)
    if (next === this.node.attrs.alt) return
    const { state } = this.view
    this.view.dispatch(state.tr.setNodeMarkup(pos, undefined, { ...this.node.attrs, alt: next }))
  }
}

export const imageView = $view(
  imageSchema.node,
  () => (node, view, getPos) => new ImageView(node, view, getPos),
)
