import { expect, test, vi } from 'vitest'
import { Editor, editorViewCtx } from '@milkdown/kit/core'
import { NoteEditor } from '../src/editor'

async function withEditor(run: (editor: NoteEditor, milkdown: Editor) => void) {
  const root = document.createElement('div')
  document.body.append(root)
  const editor = await NoteEditor.mount(root, {
    find() {},
    changed() {},
    stateChanged() {},
    openLink() {},
    copy() {},
  })
  const milkdown = (editor as unknown as { editor: Editor }).editor
  const scroll = vi.spyOn(window, 'scrollTo').mockImplementation(() => {})
  try {
    run(editor, milkdown)
  } finally {
    await milkdown.destroy()
    scroll.mockRestore()
    root.remove()
  }
}

test('browsing a note ending in a heading stays unfocused at the top', async () => {
  await withEditor((editor, milkdown) => {
    const view = milkdown.ctx.get(editorViewCtx)
    const scrollSelection = vi.fn(() => true)
    view.setProps({ handleScrollToSelection: scrollSelection })
    editor.load('A paragraph.\n\n## Closing\n', 1)
    expect(view.hasFocus()).toBe(false)
    expect(view.dom.classList.contains('ProseMirror-focused')).toBe(false)
    expect(view.state.selection.$from.parent.type.name).toBe('heading')
    expect(view.state.selection.from).toBe(view.state.doc.content.size - 1)
    expect(scrollSelection).not.toHaveBeenCalled()
    expect(window.scrollTo).toHaveBeenLastCalledWith(0, 0)
    expect(editor.markdown()).toBeNull()
  })
})

test('an explicit focus request reveals the saved insertion point', async () => {
  await withEditor((editor, milkdown) => {
    editor.load('A paragraph.\n\n## Closing\n', 1)
    const view = milkdown.ctx.get(editorViewCtx)
    const selection = view.state.selection
    const scrollSelection = vi.fn(() => true)
    view.setProps({ handleScrollToSelection: scrollSelection })
    editor.focus()
    expect(view.hasFocus()).toBe(true)
    expect(view.dom.classList.contains('ProseMirror-focused')).toBe(true)
    expect(view.state.selection.eq(selection)).toBe(true)
    expect(scrollSelection).toHaveBeenCalledOnce()
    expect(editor.markdown()).toBeNull()
  })
})

test('leaving the editor preserves the caret and undo history for a formatting command', async () => {
  await withEditor((editor, milkdown) => {
    editor.load('A paragraph.\n\n## Closing\n', 1)
    const view = milkdown.ctx.get(editorViewCtx)
    view.setProps({ handleScrollToSelection: () => true })
    editor.focus()
    view.dispatch(view.state.tr.insertText(' words'))
    const selection = view.state.selection
    view.dom.blur()
    expect(view.hasFocus()).toBe(false)
    expect(view.dom.classList.contains('ProseMirror-focused')).toBe(false)
    expect(view.state.selection.eq(selection)).toBe(true)
    editor.undo()
    expect(editor.markdown()).toBeNull()
    editor.redo()
    expect(editor.markdown()).toBe('A paragraph.\n\n## Closing words\n')
    editor.format('paragraph')
    expect(view.hasFocus()).toBe(true)
    expect(editor.markdown()).toBe('A paragraph.\n\nClosing words\n')
  })
})
