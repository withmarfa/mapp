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
      insertImages(images: { src: string; alt: string }[], x?: number, y?: number): void
      setKeymap(keymap: Keymap): void
      setLabels(labels: Partial<Labels>): void
    }
  }
}

const root = document.getElementById('editor')
if (!root) throw new Error('editor root missing')

const editor = await NoteEditor.mount(root, {
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
    if (![...data.items].some((item) => item.kind === 'file' && item.type.startsWith('image/'))) return
    event.preventDefault()
    event.stopPropagation()
    postToHost({ type: 'pasteImages' })
  },
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
  insertImages: (images, x, y) => editor.insertImages(images, x, y),
  setKeymap: (keymap) => editor.setKeymap(keymap),
  setLabels: (labels) => setLabels(labels),
}

postToHost({ type: 'ready' })
