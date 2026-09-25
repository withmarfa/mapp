import { readdirSync, readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, test } from 'vitest'
import { editorViewCtx, parserCtx } from '@milkdown/kit/core'
import type { Ctx } from '@milkdown/kit/ctx'
import { TextSelection } from '@milkdown/kit/prose/state'
import { serialize } from '../src/dialect'
import { NoteEditor } from '../src/editor'

const corpus = resolve(__dirname, '../fixtures/corpus')
const marker = 'EDIT HERE'

async function withLoaded<T>(
  markdown: string,
  run: (editor: NoteEditor, ctx: Ctx) => T,
): Promise<T> {
  const root = document.createElement('div')
  document.body.append(root)
  const editor = await NoteEditor.mount(root, {
    changed() {},
    stateChanged() {},
    openLink() {},
    copy() {},
  })
  editor.load(markdown, 1)
  try {
    return run(editor, (editor as unknown as { editor: { ctx: Ctx } }).editor.ctx)
  } finally {
    root.remove()
  }
}

/** Types after the marker, as a person would, and returns what the note would now save. */
function typeAfterMarker(editor: NoteEditor, ctx: Ctx, text: string): string | null {
  const view = ctx.get(editorViewCtx)
  let at = -1
  view.state.doc.descendants((node, pos) => {
    if (at < 0 && node.isText && node.text?.includes(marker))
      at = pos + node.text.indexOf(marker) + marker.length
  })
  expect(at).toBeGreaterThan(0)
  view.dispatch(view.state.tr.insertText(text, at))
  return editor.markdown()
}

describe.each(readdirSync(corpus).filter((name) => name.endsWith('.md')))('%s', (name) => {
  const source = readFileSync(resolve(corpus, name), 'utf8')

  test('opened and left alone, it is not rewritten', async () => {
    await withLoaded(source, (editor) => expect(editor.markdown()).toBe(null))
  })

  test('an edit to one paragraph changes that paragraph and nothing else', async () => {
    await withLoaded(source, (editor, ctx) => {
      expect(typeAfterMarker(editor, ctx, '!')).toBe(source.replace(marker, `${marker}!`))
    })
  })

  test('an edit undone leaves the note as it was', async () => {
    await withLoaded(source, (editor, ctx) => {
      typeAfterMarker(editor, ctx, '!')
      const view = ctx.get(editorViewCtx)
      let at = -1
      view.state.doc.descendants((node, pos) => {
        if (at < 0 && node.isText && node.text?.includes(`${marker}!`))
          at = pos + node.text.indexOf(`${marker}!`) + marker.length
      })
      view.dispatch(view.state.tr.delete(at, at + 1))
      expect(editor.markdown()).toBe(null)
    })
  })
})

test('a block added at the end keeps everything before it as written', async () => {
  const source = readFileSync(resolve(corpus, 'tables.md'), 'utf8')
  await withLoaded(source, (editor, ctx) => {
    const view = ctx.get(editorViewCtx)
    const paragraph = view.state.schema.nodes.paragraph!.create(
      null,
      view.state.schema.text('Added.'),
    )
    view.dispatch(view.state.tr.insert(view.state.doc.content.size, paragraph))
    expect(editor.markdown()).toBe(`${source}\nAdded.\n`)
  })
})

test('a removed block takes its own text away and leaves its neighbours as written', async () => {
  const source = '*One*  \n\nTwo\n\n__Three__\n'
  await withLoaded(source, (editor, ctx) => {
    const view = ctx.get(editorViewCtx)
    const second = view.state.doc.child(1)
    const start = view.state.doc.child(0).nodeSize
    view.dispatch(view.state.tr.delete(start, start + second.nodeSize))
    expect(editor.markdown()).toBe('*One*  \n\n__Three__\n')
  })
})

test('kept blocks that would read differently side by side are written canonically instead', async () => {
  // Removing the paragraph would leave two bullet lists touching, which read back as one list.
  const source = '- a\n\nBetween\n\n- b\n'
  await withLoaded(source, (editor, ctx) => {
    const view = ctx.get(editorViewCtx)
    const start = view.state.doc.child(0).nodeSize
    view.dispatch(view.state.tr.delete(start, start + view.state.doc.child(1).nodeSize))
    const saved = editor.markdown()!
    const reread = serialize(ctx, ctx.get(parserCtx)(saved))
    expect(reread).toBe(serialize(ctx))
  })
})

test('a table made in the editor is written with plain delimiters among blocks kept as written', async () => {
  const source = '* star\n\nPara  \n'
  await withLoaded(source, (editor, ctx) => {
    const view = ctx.get(editorViewCtx)
    view.dispatch(view.state.tr.setSelection(TextSelection.atEnd(view.state.doc)))
    editor.format('table')
    const saved = editor.markdown()!
    expect(saved.startsWith('* star\n\nPara  \n')).toBe(true)
    expect(saved).toContain('| --- | --- | --- |')
  })
})
