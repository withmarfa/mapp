import { postToHost } from './bridge'
import { NoteEditor, type FormatCommand, type Keymap } from './editor'
import { InkKitError } from '@aicayzer/inkkit'
import '@aicayzer/inkkit/style.css'
import type { EditorLabels } from '@aicayzer/inkkit'
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
      setEditingMode(mode: 'source' | 'formatted', expected?: number): void
      undo(expected?: number): void
      redo(expected?: number): void
      setItem(id: string): void
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
      snapshot(expected?: number): unknown
      printable(expected?: number): Promise<unknown>
      setFullWidth(full: boolean): void
      setTextSize(points: number): void
      setReadingWidth(ems: number): void
      setHeaderHeight(height: number): void
      setSpellcheck(spellcheck: boolean): void
    }
  }
}

const root = document.getElementById('editor')
if (!root) throw new Error('editor root missing')

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
  (window as unknown as { mappLabels?: Partial<EditorLabels> }).mappLabels,
)

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
    if (!data || data.types.includes('text/html')) return
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

// Links open on ⌘-click, so the pointer says so only while ⌘ is down.
for (const name of ['keydown', 'keyup'] as const) {
  window.addEventListener(name, (event) =>
    document.documentElement.classList.toggle('meta', event.metaKey),
  )
}
// A selection in a window in the background is drawn grey, as the system draws it.
window.addEventListener('blur', () => {
  document.documentElement.classList.remove('meta')
  document.documentElement.classList.add('inactive')
})
window.addEventListener('focus', () => document.documentElement.classList.remove('inactive'))

let generation = 0
let scrollPending = false
function reportScroll(): void {
  postToHost({ type: 'scrolled', offset: window.scrollY, generation: editor.loadedGeneration })
}
window.addEventListener(
  'scroll',
  () => {
    if (scrollPending) return
    scrollPending = true
    requestAnimationFrame(() => {
      scrollPending = false
      reportScroll()
    })
  },
  { passive: true },
)

window.editor = {
  load: (markdown, nextGeneration, editable) => {
    generation = nextGeneration
    editor.load(markdown, nextGeneration, editable)
    reportScroll()
  },
  reload: (markdown, nextGeneration, editable) => {
    generation = nextGeneration
    editor.reload(markdown, nextGeneration, editable)
    reportScroll()
  },
  markdown: () => editor.markdown(),
  flush: (expected) => editor.flush(expected),
  format: (command, arg, expected) => editor.format(command, arg ?? undefined, expected),
  focus: () => editor.focus(),
  setEditingMode: (mode, expected) => editor.setEditingMode(mode, expected),
  undo: (expected) => editor.undo(expected),
  redo: (expected) => editor.redo(expected),
  setItem: (id) => editor.setItem(id),
  setFinding: (finding) => editor.setFinding(finding),
  findSelect: (from, to, generation, snapshotId) =>
    editor.findSelect(from, to, generation, snapshotId),
  findScroll: (from, generation, snapshotId) => editor.findScroll(from, generation, snapshotId),
  findReplace: (from, to, text, generation, snapshotId, batch) =>
    editor.findReplace(from, to, text, generation, snapshotId, batch),
  // The app gives a drop's place in the web view; the page's window starts below whatever covers its top.
  insertImages: (images, x, y, height) =>
    editor.insertImages(
      images,
      x,
      y == null ? y : y - Math.max(0, (height ?? window.innerHeight) - window.innerHeight),
    ),
  setKeymap: (keymap) => editor.setKeymap(keymap),
  snapshot: (expected) => editor.snapshot(expected),
  printable: async (expected) => {
    try {
      return await editor.printable(expected)
    } catch (error) {
      if (error instanceof InkKitError) return { snapshotError: error.code, message: error.message }
      throw error
    }
  },
  setFullWidth: (full) => document.documentElement.classList.toggle('full-width', full),
  // Text measures use rem, so the reading width scales with its text.
  setTextSize: (points) => {
    document.documentElement.style.fontSize = `${points}px`
  },
  setSpellcheck: (spellcheck) => editor.setSpellcheck(spellcheck),
  setReadingWidth: (ems) =>
    document.documentElement.style.setProperty('--reading-width', `${ems}rem`),
  setHeaderHeight: (height) => {
    document.documentElement.style.setProperty('--item-header-height', `${Math.max(0, height)}px`)
  },
}

postToHost({ type: 'ready' })
