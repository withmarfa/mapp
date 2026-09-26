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
    find() {},
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

/** Types `insert` straight after the first `after` in the note's text, and returns what the note would save. */
function typeAfter(editor: NoteEditor, ctx: Ctx, after: string, insert: string): string | null {
  const view = ctx.get(editorViewCtx)
  let at = -1
  view.state.doc.descendants((node, pos) => {
    if (at < 0 && node.isText && node.text?.includes(after))
      at = pos + node.text.indexOf(after) + after.length
  })
  expect(at).toBeGreaterThan(0)
  view.dispatch(view.state.tr.insertText(insert, at))
  return editor.markdown()
}

function append(ctx: Ctx, text: string): void {
  const view = ctx.get(editorViewCtx)
  const { schema } = view.state
  view.dispatch(
    view.state.tr.insert(
      view.state.doc.content.size,
      schema.nodes.paragraph!.create(null, schema.text(text)),
    ),
  )
}

describe('what the editor does not show is kept', () => {
  test('a link definition after the last block survives a block added after it', async () => {
    await withLoaded('See [x][ref].\n\nLast\n\n[ref]: https://e.com\n', (editor, ctx) => {
      append(ctx, 'New')
      expect(editor.markdown()).toBe('See [x][ref].\n\nLast\n\nNew\n\n[ref]: https://e.com\n')
    })
  })

  test('a definition no link uses is kept when the blocks around it change', async () => {
    await withLoaded('Para\n\n[unused]: https://e.com\n\nLast\n', (editor, ctx) => {
      const saved = typeAfter(editor, ctx, 'Last', '!')!
      expect(saved).toContain('[unused]: https://e.com')
    })
  })

  test('a definition is written once however many blocks change', async () => {
    await withLoaded('A\n\n[d]: /x\n\nB\n\nC\n', (editor, ctx) => {
      typeAfter(editor, ctx, 'A', '!')
      typeAfter(editor, ctx, 'B', '!')
      append(ctx, 'N')
      const saved = editor.markdown()!
      expect(saved.split('[d]: /x').length - 1).toBe(1)
    })
  })

  test('a definition inside a quote still gives other blocks their meaning', async () => {
    const source = '> [q]: https://q.com\n\nSee [x][q].\n\nOther EDIT\n'
    await withLoaded(source, (editor, ctx) => {
      expect(typeAfter(editor, ctx, 'EDIT', '!')).toBe(source.replace('EDIT', 'EDIT!'))
    })
  })
})

describe('blocks keep their own shape', () => {
  test('an indented list keeps the indent of its first line', async () => {
    const source = 'Para EDIT\n\n  - a\n  - b\n'
    await withLoaded(source, (editor, ctx) => {
      expect(typeAfter(editor, ctx, 'EDIT', '!')).toBe(source.replace('EDIT', 'EDIT!'))
    })
  })

  test('an indented fence keeps its indent', async () => {
    const source = 'Para EDIT\n\n  ```\n  code\n  ```\n'
    await withLoaded(source, (editor, ctx) => {
      expect(typeAfter(editor, ctx, 'EDIT', '!')).toBe(source.replace('EDIT', 'EDIT!'))
    })
  })

  test('a fence left open at the end of the note is kept open', async () => {
    const source = 'Para EDIT\n\n```\ncode\n'
    await withLoaded(source, (editor, ctx) => {
      expect(typeAfter(editor, ctx, 'EDIT', '!')).toBe(source.replace('EDIT', 'EDIT!'))
    })
  })

  test('blank lines around blocks further on are not moved by edits before them', async () => {
    const source = 'A\n\n\n\n\nB\n\nC\n\nD\n'
    await withLoaded(source, (editor, ctx) => {
      typeAfter(editor, ctx, 'A', '!')
      typeAfter(editor, ctx, 'C', '!')
      expect(editor.markdown()).toBe('A!\n\n\n\n\nB\n\nC!\n\nD\n')
    })
  })
})
