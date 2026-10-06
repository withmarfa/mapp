import { imageSchema } from '@milkdown/kit/preset/commonmark'
import type { Node as ProseNode } from '@milkdown/kit/prose/model'
import type { EditorView, NodeView } from '@milkdown/kit/prose/view'
import { $view } from '@milkdown/kit/utils'
import { postToHost, type EmbedRequest, type EmbeddedFile } from './bridge'
import { isDocument, readNamed, wikiEmbedSchema, withWidth } from './wikiembeds'

/** The item on the page, whose embeds the app resolves. */
let item = ''
/** What the app said of each embed asked about for the item on the page. */
let asked = new Map<string, Promise<EmbeddedFile | null>>()

/** Embeds are asked about again for each note, so a file changed on disk shows as it now is. */
export function setItem(id: string): void {
  item = id
  asked = new Map()
}

/** An image's path as markdown gives it; null for an address, which the page never loads, or a document's
 *  path, which is a note embedded rather than a file. */
export function pathRequest(src: string): string | null {
  if (!src || src.startsWith('#') || src.startsWith('//') || /^[a-z][a-z0-9+.-]*:/i.test(src))
    return null
  const path = src.split(/[?#]/)[0] ?? ''
  let decoded = path
  try {
    decoded = decodeURIComponent(path)
  } catch {
    // A stray `%` is kept as written, as Marfa's core keeps one.
  }
  return decoded && !isDocument(decoded) ? src : null
}

/** What the app knows of the embed, or null when it has no file for it. Only an answer with a file is kept,
 *  since a file just pasted may not be written yet. */
function ask(request: EmbedRequest): Promise<EmbeddedFile | null> {
  const key = JSON.stringify(request)
  let answer = asked.get(key)
  if (!answer) {
    const embeds = window.webkit?.messageHandlers?.embeds
    answer = (embeds ? embeds.postMessage(request).catch(() => null) : Promise.resolve(null)).then(
      (file) => {
        if (!file) asked.delete(key)
        return file
      },
    )
    asked.set(key, answer)
  }
  return answer
}

/** How long to wait before asking again for a file that was not there, as when it is still being written. */
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

/** What an embed node asks for and shows while it waits. */
interface Described {
  request: EmbedRequest | null
  name: string
  width: number | null
  fragment: string
}

function describe(node: ProseNode): Described {
  if (node.type.name === 'embed') {
    const named = readNamed(String(node.attrs.raw))
    return {
      request: { item, name: named.name },
      name: named.name.slice(named.name.lastIndexOf('/') + 1),
      width: named.width,
      fragment: named.fragment,
    }
  }
  const src = String(node.attrs.src || '')
  const { alt, width } = splitAlt(String(node.attrs.alt || ''))
  const path = pathRequest(src)
  const hash = src.indexOf('#')
  return {
    request: path ? { item, path } : null,
    name: alt || src,
    width,
    fragment: hash < 0 ? '' : src.slice(hash),
  }
}

/** The embed the page shows, for the context menu the app adds Open and Show in Finder to. */
const shown = new WeakMap<Element, { embed: EmbedRequest; opens: boolean }>()

export function embedAt(
  target: EventTarget | null,
): { embed: EmbedRequest; opens: boolean } | null {
  let element = target instanceof Element ? target : null
  while (element) {
    const request = shown.get(element)
    if (request) return request
    element = element.parentElement
  }
  return null
}

const minimumWidth = 48

/** A file an embed names shows as what it is, in the text's flow: an image as itself, at the width the
 *  markdown gives and never wider than the page, with a handle on its trailing edge that sizes it; sound and
 *  video with the system's controls; a PDF in a frame; anything else as a card that opens it. One the app has
 *  no file for, missing, outside the notes folder or an address, shows what it was called. The markdown keeps
 *  the embed as written in every case. */
class EmbedView implements NodeView {
  dom: HTMLElement
  /** The request this view shows or is waiting for, so an answer for one it no longer shows is not painted. */
  private key: string | null = null
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
    const same =
      node.attrs.src === this.node.attrs.src &&
      node.attrs.alt === this.node.attrs.alt &&
      node.attrs.raw === this.node.attrs.raw
    this.node = node
    // Most updates are the document changing around the embed; redrawing it for those would flash its name.
    if (!same) this.render()
    return true
  }

  /** The handle, the media controls and the card are the view's to handle, not the document's. */
  stopEvent(event: Event): boolean {
    const target = event.target
    if (!(target instanceof Element)) return false
    if (target.closest('.image-handle, audio, video, iframe')) return true
    return target.closest('.embed-card') != null && event.type !== 'dragstart'
  }

  ignoreMutation(): boolean {
    return true
  }

  private render(): void {
    const described = describe(this.node)
    this.width = described.width
    this.absent(described.name)
    this.key = described.request ? JSON.stringify(described.request) : null
    if (described.request) this.show(described, described.request, 0)
  }

  private show(described: Described, request: EmbedRequest, attempt: number): void {
    const key = JSON.stringify(request)
    void ask(request).then((file) => {
      if (this.key !== key) return
      if (!file) {
        const delay = retries[attempt]
        if (delay != null)
          setTimeout(() => this.key === key && this.show(described, request, attempt + 1), delay)
        return
      }
      shown.set(this.dom, { embed: request, opens: file.opens })
      switch (file.kind) {
        case 'image':
          return this.showImage(file, described, request)
        case 'audio':
        case 'video':
          return this.showMedia(file, described, request)
        case 'pdf':
          return this.showPDF(file, described)
        default:
          return this.showCard(file, request)
      }
    })
  }

  private showImage(file: EmbeddedFile, described: Described, request: EmbedRequest): void {
    const element = document.createElement('img')
    element.src = file.url
    element.alt = described.name
    element.draggable = false
    if (this.width != null) element.style.width = `${this.width}px`
    // A file WebKit cannot draw, such as a camera's raw format, is still a file.
    element.addEventListener('error', () => this.image === element && this.showCard(file, request))
    const handle = document.createElement('span')
    handle.className = 'image-handle'
    handle.addEventListener('pointerdown', this.startResize)
    this.image = element
    this.dom.className = 'image'
    this.dom.replaceChildren(element, handle)
  }

  private showMedia(file: EmbeddedFile, described: Described, request: EmbedRequest): void {
    const element = document.createElement(file.kind === 'audio' ? 'audio' : 'video')
    element.controls = true
    element.preload = 'metadata'
    element.src = file.url
    element.title = described.name
    if (element instanceof HTMLVideoElement) {
      element.playsInline = true
      if (this.width != null) element.style.width = `${this.width}px`
    }
    element.addEventListener(
      'error',
      () => this.dom.contains(element) && this.showCard(file, request),
    )
    this.image = undefined
    this.dom.className = `embed-${file.kind}`
    this.dom.replaceChildren(element)
  }

  private showPDF(file: EmbeddedFile, described: Described): void {
    const frame = document.createElement('iframe')
    frame.src = file.url + described.fragment
    frame.title = described.name
    this.image = undefined
    this.dom.className = 'embed-pdf'
    this.dom.replaceChildren(frame)
  }

  private showCard(file: EmbeddedFile, request: EmbedRequest): void {
    const card = document.createElement('span')
    card.className = 'embed-card'
    card.title = file.name
    const icon = document.createElement('img')
    icon.className = 'embed-icon'
    icon.src = file.icon
    icon.alt = ''
    icon.draggable = false
    icon.addEventListener('error', () => icon.remove())
    const name = document.createElement('span')
    name.className = 'embed-name'
    name.textContent = file.name
    const detail = document.createElement('span')
    detail.className = 'embed-detail'
    detail.textContent = file.detail
    card.append(icon, name, detail)
    card.addEventListener('click', (event) => {
      event.preventDefault()
      postToHost({ type: 'openEmbed', embed: request })
    })
    this.image = undefined
    this.dom.className = 'embed-file'
    this.dom.replaceChildren(card)
  }

  private absent(name: string): void {
    this.image = undefined
    shown.delete(this.dom)
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
    if (pos == null || this.width == null) return
    const attrs: Record<string, unknown> = this.node.attrs
    const next: Record<string, unknown> =
      this.node.type.name === 'embed'
        ? { ...attrs, raw: withWidth(String(attrs.raw), this.width) }
        : { ...attrs, alt: joinAlt(splitAlt(String(attrs.alt ?? '')).alt, this.width) }
    if (next.raw === attrs.raw && next.alt === attrs.alt) return
    const { state } = this.view
    this.view.dispatch(state.tr.setNodeMarkup(pos, undefined, next))
  }
}

export const imageView = $view(
  imageSchema.node,
  () => (node, view, getPos) => new EmbedView(node, view, getPos),
)

export const wikiEmbedView = $view(
  wikiEmbedSchema.node,
  () => (node, view, getPos) => new EmbedView(node, view, getPos),
)
