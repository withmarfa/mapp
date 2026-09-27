import { postToHost } from './bridge'
import { NoteEditor, type FormatCommand, type Keymap } from './editor'
import { setImageBase } from './images'
import { setLabels, type Labels } from './labels'
import './style.css'

declare global {
  interface Window {
    editor: {
      load(markdown: string, generation: number, editable: boolean): void
      reload(markdown: string, generation: number, editable: boolean): void
      markdown(): string | null
      flush(): string | null
      format(command: FormatCommand, arg?: string | number): void
      focus(): void
      undo(): void
      redo(): void
      setImageBase(directory: string): void
      setFinding(finding: boolean): void
      findSelect(from: number, to: number): void
      findScroll(from: number): void
      findReplace(from: number, to: number, text: string): void
      insertImages(images: { src: string; alt: string }[], x?: number, y?: number, height?: number): void
      setKeymap(keymap: Keymap): void
      setLabels(labels: Partial<Labels>): void
      setFullWidth(full: boolean): void
      setTextSize(points: number): void
      setReadingWidth(ems: number): void
      setSpellcheck(spellcheck: boolean): void
    }
  }
}

const root = document.getElementById('editor')
if (!root) throw new Error('editor root missing')

const editor = await NoteEditor.mount(root, {
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
})

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

// Whether the page is scrolled from its top, told only when it changes, so the app shows the edge under the
// toolbar only while text is beneath it, as Mail does.
let scrolled: boolean | undefined
function reportScroll(): void {
  const now = window.scrollY > 0
  if (now === scrolled) return
  scrolled = now
  postToHost({ type: 'scrolled', scrolled: now })
}
window.addEventListener('scroll', reportScroll, { passive: true })
reportScroll()

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

window.editor = {
  load: (markdown, generation, editable) => {
    editor.setEditable(editable)
    editor.load(markdown, generation)
  },
  reload: (markdown, generation, editable) => {
    editor.setEditable(editable)
    editor.reload(markdown, generation)
  },
  markdown: () => editor.markdown(),
  flush: () => editor.flush(),
  format: (command, arg) => editor.format(command, arg),
  focus: () => editor.focus(),
  undo: () => editor.undo(),
  redo: () => editor.redo(),
  setImageBase: (directory) => setImageBase(directory),
  setFinding: (finding) => editor.setFinding(finding),
  findSelect: (from, to) => editor.findSelect(from, to),
  findScroll: (from) => editor.findScroll(from),
  findReplace: (from, to, text) => editor.findReplace(from, to, text),
  // The app gives a drop's place in the web view; the page's window starts below whatever covers its top.
  insertImages: (images, x, y, height) =>
    editor.insertImages(images, x, y == null ? y : y - Math.max(0, (height ?? window.innerHeight) - window.innerHeight)),
  setKeymap: (keymap) => editor.setKeymap(keymap),
  setLabels: (labels) => setLabels(labels),
  setFullWidth: (full) => document.documentElement.classList.toggle('full-width', full),
  // Every size and measure on the page is in rem, so the whole note scales with its text.
  setTextSize: (points) => {
    document.documentElement.style.fontSize = `${points}px`
  },
  setSpellcheck: (spellcheck) => editor.setSpellcheck(spellcheck),
  setReadingWidth: (ems) => document.documentElement.style.setProperty('--reading-width', `${ems}rem`),
}

postToHost({ type: 'ready' })
