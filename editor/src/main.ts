import { postToHost } from './bridge'
import { NoteEditor, type FormatCommand, type Keymap } from './editor'
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
  setKeymap: (keymap) => editor.setKeymap(keymap),
  setLabels: (labels) => setLabels(labels),
}

postToHost({ type: 'ready' })
