import { expect, test } from 'vitest'
import { editorViewCtx } from '@milkdown/kit/core'
import type { Ctx } from '@milkdown/kit/ctx'
import { NoteEditor, type FindState } from '../src/editor'
import { offsetAt, positionAt, textModel } from '../src/find'

async function withNoteEditor<T>(markdown: string, run: (editor: NoteEditor, found: FindState[]) => T) {
  const root = document.createElement('div')
  document.body.append(root)
  const found: FindState[] = []
  const editor = await NoteEditor.mount(root, {
    find(state) {
      found.push(state)
    },
    changed() {},
    stateChanged() {},
    openLink() {},
    copy() {},
  })
  editor.load(markdown, 1)
  try {
    return run(editor, found)
  } finally {
    root.remove()
  }
}

function ctxOf(editor: NoteEditor): Ctx {
  return (editor as unknown as { editor: { ctx: Ctx } }).editor.ctx
}

test('the find bar searches the note as it reads, a line to each block', async () =>
  withNoteEditor('# Kitchen *quotes*\n\n- [ ] Ask about **worktops**\n\n| a | b |\n| --- | --- |\n| 1 | 2 |\n', (editor) => {
    const model = textModel(ctxOf(editor).get(editorViewCtx).state.doc)
    expect(model.text).toBe('Kitchen quotes\nAsk about worktops\na\nb\n1\n2')
  }))

test('text offsets and document positions map both ways', async () =>
  withNoteEditor('One\n\nTwo three\n', (editor) => {
    const { doc } = ctxOf(editor).get(editorViewCtx).state
    const model = textModel(doc)
    const three = model.text.indexOf('three')
    const pos = positionAt(model, three)
    expect(doc.textBetween(pos, pos + 5)).toBe('three')
    expect(offsetAt(model, pos)).toBe(three)
  }))

test('opening the find bar sends the text and the selection', async () =>
  withNoteEditor('Alpha beta\n', (editor, found) => {
    editor.setFinding(true)
    expect(found.at(-1)?.text).toBe('Alpha beta')
    editor.findSelect(6, 10)
    const { state } = ctxOf(editor).get(editorViewCtx)
    expect(state.doc.textBetween(state.selection.from, state.selection.to)).toBe('beta')
  }))

test('replacing writes the new text where the match was, and not in a read-only note', async () => {
  await withNoteEditor('Tea and **tea**\n', (editor) => {
    editor.setFinding(true)
    editor.findReplace(8, 11, 'coffee')
    editor.findReplace(0, 3, 'Coffee')
    expect(editor.markdown()).toBe('Coffee and **coffee**\n')
  })
  await withNoteEditor('Tea\n', (editor) => {
    editor.setEditable(false)
    editor.findReplace(0, 3, 'Coffee')
    expect(editor.markdown()).toBeNull()
  })
})
