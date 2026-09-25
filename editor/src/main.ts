import { postToHost } from './bridge'
import { NoteEditor, type FormatCommand, type Keymap } from './editor'
import './style.css'

declare global {
  interface Window {
    editor: {
      load(markdown: string, generation: number, editable: boolean): void
      markdown(): string | null
      format(command: FormatCommand, arg?: string | number): void
      focus(): void
      find(text: string): void
      undo(): void
      redo(): void
      setKeymap(keymap: Keymap): void
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
  escape() {
    postToHost({ type: 'escape' })
  },
})

// Links open on ⌘-click, so the pointer says so only while ⌘ is down.
for (const name of ['keydown', 'keyup'] as const) {
  window.addEventListener(name, (event) =>
    document.documentElement.classList.toggle('meta', event.metaKey),
  )
}
window.addEventListener('blur', () => document.documentElement.classList.remove('meta'))

window.editor = {
  load: (markdown, generation, editable) => {
    editor.setEditable(editable)
    editor.load(markdown, generation)
  },
  markdown: () => editor.markdown(),
  format: (command, arg) => editor.format(command, arg),
  focus: () => editor.focus(),
  find: (text) => editor.find(text),
  undo: () => editor.undo(),
  redo: () => editor.redo(),
  setKeymap: (keymap) => editor.setKeymap(keymap),
}

postToHost({ type: 'ready' })
