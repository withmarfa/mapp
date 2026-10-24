import { postToHost } from './bridge'
import {
  NoteEditor,
  guardedCommand,
  splitLabels,
  type AppLabels,
  type FormatCommand,
  type Keymap,
} from './editor'
import { ItemHeader, type HeaderIcons, type HeaderModel } from './header'
import { InkKitError } from '@aicayzer/inkkit'
import '@aicayzer/inkkit/style.css'
import './style.css'

declare global {
  interface Window {
    editor: {
      load(markdown: string, generation: number, editable: boolean): void
      reload(markdown: string, generation: number, editable: boolean): void
      markdown(): string | null
      flush(expected?: number): string | null
      format(command: FormatCommand, arg?: string | number, expected?: number): void
      focus(): void
      focusTitle(item: string): void
      blurText(expected: number): void
      setEditingMode(mode: 'source' | 'formatted', expected?: number): void
      undo(expected?: number): void
      redo(expected?: number): void
      setItem(id: string): void
      linksChanged(): void
      revealHeading(text: string, expected?: number): boolean
      setFinding(finding: boolean): void
      findSelect(from: number, to: number, generation?: number, snapshotId?: string): void
      findScroll(from: number, generation?: number, snapshotId?: string): void
      findReplace(
        from: number,
        to: number,
        text: string,
        generation?: number,
        snapshotId?: string,
        batch?: string,
      ): void
      insertImages(
        images: { src: string; alt: string }[],
        x?: number,
        y?: number,
        height?: number,
      ): void
      setKeymap(keymap: Keymap): void
      readableSnapshot(expected?: number): unknown
      snapshot(expected?: number): unknown
      printable(expected?: number): Promise<unknown>
      setFullWidth(full: boolean): void
      setTextSize(points: number): void
      setReadingWidth(ems: number): void
      setHeader(model: HeaderModel | null): void
      setHeaderIcons(icons: HeaderIcons): void
      setSpellcheck(spellcheck: boolean): void
    }
  }
}

const root = document.getElementById('editor')
const headerRoot = document.getElementById('item-header')
if (!root || !headerRoot) throw new Error('editor root missing')
const labels = splitLabels((window as unknown as { mappLabels?: AppLabels }).mappLabels ?? {})

const editor = await NoteEditor.mount(
  root,
  {
    find(state) {
      postToHost({ type: 'find', ...state })
    },
    changed(markdown, generation) {
      postToHost({ type: 'changed', markdown, generation })
    },
    stateChanged(state) {
      postToHost({ type: 'state', ...state })
    },
    openLink(href) {
      postToHost({ type: 'openLink', href })
    },
    copy(text) {
      postToHost({ type: 'copy', text })
    },
  },
  labels.editor,
  labels.words,
)
const header = new ItemHeader(headerRoot, labels.header)

// Escape hands the keyboard back to the list. Heard on the window, since a read-only page's editor hears
// no keys of its own.
window.addEventListener('keydown', (event) => {
  if (event.key !== 'Escape' || event.metaKey || event.ctrlKey || event.altKey || event.shiftKey)
    return
  event.preventDefault()
  postToHost({ type: 'escape' })
})

// An image pasted on its own, a screenshot or an image file copied in the Finder, becomes a file of the notes
// folder, which the app takes from the pasteboard itself; a copied web page, images and all, is the page's.
window.addEventListener(
  'paste',
  (event) => {
    const data = event.clipboardData
    if (!data || data.types.includes('text/html') || headerRoot.contains(event.target as Node))
      return
    const files = [...data.items].filter((item) => item.kind === 'file')
    if (files.length === 0 || !files.every((item) => item.type.startsWith('image/'))) return
    // Text beside the image is kept for the page, unless it only names a file copied in the Finder.
    if (data.types.includes('text/plain') && !data.types.includes('text/uri-list')) return
    event.preventDefault()
    event.stopPropagation()
    postToHost({ type: 'pasteImages' })
  },
  { capture: true },
)

window.addEventListener(
  'contextmenu',
  () => postToHost({ type: 'embedMenu', embed: null, opens: false }),
  { capture: true },
)

// A selection in a window in the background is drawn grey, as the system draws it.
window.addEventListener('blur', () => document.documentElement.classList.add('inactive'))
window.addEventListener('focus', () => document.documentElement.classList.remove('inactive'))

let generation = 0
// The toolbar shows the title once the header has gone under it; the app hears only when that changes. A page
// with no header to show, as for a deleted note, has its title there from the start.
let headerScrolledAway = false
function checkHeaderScrolledAway(): void {
  const away = header.isHidden || window.scrollY >= header.bottom
  if (away === headerScrolledAway) return
  headerScrolledAway = away
  postToHost({ type: 'headerScrolledAway', away, generation: editor.loadedGeneration })
}
window.addEventListener('scroll', checkHeaderScrolledAway, { passive: true })
window.addEventListener('resize', checkHeaderScrolledAway)
// The note's text fills the rest of the window below the header, so a click anywhere below it places the caret
// and a short note does not scroll. The text's height changes in the next frame: changed while the browser
// reports sizes, it would be reported late, which WebKit raises as an error.
// A header that only grew wider moves nothing below it.
let headerHeight = -1
new ResizeObserver(() => {
  const height = headerRoot.offsetHeight
  if (height === headerHeight) return
  headerHeight = height
  requestAnimationFrame(() => {
    root.style.setProperty('--inkkit-min-height', `calc(100vh - ${height}px)`)
    editor.invalidateFindGeometry()
    checkHeaderScrolledAway()
  })
}).observe(headerRoot)

function setPageProperty(name: string, value: string): void {
  const style = document.documentElement.style
  if (style.getPropertyValue(name) === value) return
  style.setProperty(name, value)
  editor.invalidateFindGeometry()
}

window.editor = {
  load: (markdown, nextGeneration, editable) => {
    generation = nextGeneration
    header.cancelTitleFocus()
    editor.load(markdown, nextGeneration, editable)
    headerScrolledAway = false
    checkHeaderScrolledAway()
  },
  reload: (markdown, nextGeneration, editable) => {
    generation = nextGeneration
    editor.reload(markdown, nextGeneration, editable)
  },
  markdown: () => editor.markdown(),
  flush: (expected) => editor.flush(expected),
  format: (command, arg, expected) =>
    guardedCommand(() => editor.format(command, arg ?? undefined, expected)),
  focus: () => {
    header.cancelTitleFocus()
    editor.focus()
  },
  focusTitle: (item) => header.focusTitle(item),
  blurText: (expected: number) => {
    if (expected !== generation) return
    guardedCommand(() => editor.blur(expected))
    const active = document.activeElement
    if (active instanceof HTMLElement && active.matches('.item-title')) active.blur()
  },
  setEditingMode: (mode, expected) => guardedCommand(() => editor.setEditingMode(mode, expected)),
  undo: (expected) => guardedCommand(() => editor.undo(expected)),
  redo: (expected) => guardedCommand(() => editor.redo(expected)),
  setItem: (id) => editor.setItem(id),
  linksChanged: () => editor.linksChanged(),
  revealHeading: (text, expected) => {
    const result = guardedCommand(() => editor.revealHeading(text, expected))
    return result === true
  },
  setFinding: (finding) => editor.setFinding(finding),
  findSelect: (from, to, generation, snapshotId) =>
    guardedCommand(() => editor.findSelect(from, to, generation, snapshotId)),
  findScroll: (from, generation, snapshotId) =>
    guardedCommand(() => editor.findScroll(from, generation, snapshotId)),
  findReplace: (from, to, text, generation, snapshotId, batch) =>
    guardedCommand(() => editor.findReplace(from, to, text, generation, snapshotId, batch)),
  // The app gives a drop's place in the web view; the page's window starts below whatever covers its top.
  insertImages: (images, x, y, height) =>
    guardedCommand(() =>
      editor.insertImages(
        images,
        x,
        y == null ? y : y - Math.max(0, (height ?? window.innerHeight) - window.innerHeight),
      ),
    ),
  setKeymap: (keymap) => editor.setKeymap(keymap),
  readableSnapshot: (expected) => editor.readableSnapshot(expected),
  snapshot: (expected) => editor.snapshot(expected),
  printable: async (expected) => {
    try {
      return await editor.printable(expected)
    } catch (error) {
      if (error instanceof InkKitError) return { snapshotError: error.code, message: error.message }
      throw error
    }
  },
  setFullWidth: (full) => {
    if (document.documentElement.classList.contains('full-width') === full) return
    document.documentElement.classList.toggle('full-width', full)
    editor.invalidateFindGeometry()
  },
  // Text measures use rem, so the reading width scales with its text.
  setTextSize: (points) => setPageProperty('font-size', `${points}px`),
  setSpellcheck: (spellcheck) => editor.setSpellcheck(spellcheck),
  setReadingWidth: (ems) => setPageProperty('--reading-width', `${ems}rem`),
  setHeader: (model) => {
    header.set(model)
    checkHeaderScrolledAway()
  },
  setHeaderIcons: (icons) => header.setIcons(icons),
}

postToHost({ type: 'ready' })
