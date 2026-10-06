import { expect, test } from 'vitest'
import { editorViewCtx } from '@milkdown/kit/core'
import type { Ctx } from '@milkdown/kit/ctx'
import { TextSelection } from '@milkdown/kit/prose/state'
import type { EditorView } from '@milkdown/kit/prose/view'
import { NoteEditor } from '../src/editor'

/** Types `!` after the word EDIT, as a person would, and returns what the note would now save. */
async function typedAfterEdit(markdown: string): Promise<string | null> {
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
    const view = (editor as unknown as { editor: { ctx: Ctx } }).editor.ctx.get(editorViewCtx)
    let at = -1
    view.state.doc.descendants((node, pos) => {
      if (at < 0 && node.isText && node.text?.includes('EDIT'))
        at = pos + node.text.indexOf('EDIT') + 4
    })
    view.dispatch(view.state.tr.insertText('!', at))
    return editor.markdown()
  } finally {
    root.remove()
  }
}

test('a wikilink beside a link definition does not cost the note its definition or its other blocks', async () => {
  const source = '* one\n* two\n\nSee \\[\\[x]] EDIT\n\n[x]: https://example.com\n'
  const saved = await typedAfterEdit(source)
  expect(saved).toContain('* one\n* two\n')
  expect(saved).toContain('[x]: https://example.com')
})

test('an escaped embed stays escaped, so an edit never turns text into a file shown', async () => {
  const source = 'Type !\\[\\[Photo.png]] to embed EDIT\n'
  expect(await typedAfterEdit(source)).toBe(source.replace('EDIT', 'EDIT!'))
})

for (const link of ['[[my_note]]', '[[Q&A]]', '[[Notes ~ draft]]', '[[x*y]]']) {
  test(`${link} is written back as typed beside an edit`, async () => {
    const source = `See ${link} EDIT\n`
    expect(await typedAfterEdit(source)).toBe(`See ${link} EDIT!\n`)
  })
}

for (const link of [
  '[[a@b.com]]',
  '[[https://example.com/x]]',
  '[[A note#Part|shown]]',
  '![[A note]]',
  '![[#Heading]]',
  '![[#^abc123]]',
  '[[a]][[b]]',
]) {
  test(`${link} is written back as typed beside an edit`, async () => {
    const source = `See ${link} EDIT\n`
    expect(await typedAfterEdit(source)).toBe(`See ${link} EDIT!\n`)
  })
}

test('an escaped link stays escaped beside an edit', async () => {
  const source = 'See \\[\\[x]] EDIT\n'
  expect(await typedAfterEdit(source)).toBe('See \\[\\[x]] EDIT!\n')
})

test('a link reads as a link even where a definition names its inside', async () => {
  const source = '* one\n\nSee [[x]] EDIT\n\n[x]: https://example.com\n'
  expect(await typedAfterEdit(source)).toBe(source.replace('EDIT', 'EDIT!'))
})

async function withLoaded<T>(markdown: string, run: (editor: NoteEditor, view: EditorView) => T) {
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
    return run(
      editor,
      (editor as unknown as { editor: { ctx: Ctx } }).editor.ctx.get(editorViewCtx),
    )
  } finally {
    root.remove()
  }
}

/** Types text a character at a time at the end of the first paragraph, as input rules hear it. */
function type(view: EditorView, text: string): void {
  for (const character of text) {
    const at = view.state.selection.from
    const handled = view.someProp('handleTextInput', (handler) =>
      handler(view, at, at, character, () => view.state.tr.insertText(character, at)),
    )
    if (!handled) view.dispatch(view.state.tr.insertText(character, at))
  }
}

test('a link typed in a note defining its inside is written as typed, and the note keeps the rest', async () =>
  withLoaded('* one\n\nSee\n\n[x]: https://example.com\n', (editor, view) => {
    let end = -1
    view.state.doc.descendants((node, pos) => {
      if (end < 0 && node.isText && node.text === 'See') end = pos + 3
    })
    view.dispatch(view.state.tr.setSelection(TextSelection.create(view.state.doc, end)))
    type(view, ' [[x]]')
    expect(editor.markdown()).toBe('* one\n\nSee [[x]]\n\n[x]: https://example.com\n')
  }))

test('a file embed typed becomes the file shown', async () =>
  withLoaded('See\n', (editor, view) => {
    view.dispatch(view.state.tr.setSelection(TextSelection.create(view.state.doc, 4)))
    type(view, ' ![[Photo.png|200]]')
    let raw = ''
    view.state.doc.descendants((node) => {
      if (node.type.name === 'embed') raw = String(node.attrs.raw)
    })
    expect(raw).toBe('![[Photo.png|200]]')
    expect(editor.markdown()).toBe('See ![[Photo.png|200]]\n')
  }))

test('an edit inside a link keeps it a link', async () =>
  withLoaded('See [[Plan]] now\n', (editor, view) => {
    let at = -1
    view.state.doc.descendants((node, pos) => {
      if (at < 0 && node.isText && node.text?.includes('Plan'))
        at = pos + node.text.indexOf('Plan') + 4
    })
    view.dispatch(view.state.tr.insertText(' B', at))
    expect(editor.markdown()).toBe('See [[Plan B]] now\n')
  }))

test('a whole note written anew keeps its link definitions', async () =>
  withLoaded('- a\n\nMIDDLE\n\n- b\n\n[r]: https://example.com/r\n', (editor, view) => {
    let from = -1
    let to = -1
    view.state.doc.forEach((node, offset) => {
      if (node.textContent === 'MIDDLE') [from, to] = [offset, offset + node.nodeSize]
    })
    view.dispatch(view.state.tr.delete(from, to))
    const saved = editor.markdown()!
    expect(saved).toContain('[r]: https://example.com/r')
    expect(saved).toMatch(/^- a\n/)
  }))

// Brackets that are text, in code, escaped or around odd characters, read and write back as they were.
const literals = [
  '`[[x]]`',
  '`![[Photo.png]]`',
  '``a [[x`]] b``',
  '\\![[Photo.png]]',
  '\\\\[[x]]',
  '[[a|b]]',
  '![[Photo.png|200]]',
  '![[Photo.png|200x100]]',
  '![[Photo.png\\|200]]',
  '![[Photo.png#page=2|200]]',
  '[[a [b] c]]',
  '[[[x]]]',
  '[[x]]]',
  '![[[x]]]',
  '[[a]b]]',
  '[[a[[b]]',
  '[[a*b*]]',
  '[[_x_]]',
  '[[<b>]]',
  '[[a\\b]]',
  '[[a\\]]',
  '[[x&amp;]]',
  '[[a]] b]]',
  '[[a#b^c]]',
  '[[ x ]]',
  '[[a\tb]]',
  '![[😀.png]]',
  '![[a.b.c]]',
  '[[$x$]]',
  '[[a]] [[b|c\\|d]]',
  '<span>[[x]]</span>',
  '[see [[x]]](https://example.com)',
  '*[[x]]*',
  '**a [[x]] b**',
  '***[[x]]***',
  '~~[[x]]~~',
  '*[[x]] and [[y]]*',
  '**![[Photo.png]] b**',
  '[a ![[Photo.png]]](https://example.com)',
]

for (const literal of literals) {
  test(`${literal} is left alone when opened and written back as typed beside an edit`, async () => {
    await withLoaded(`See ${literal} end\n`, (editor) => expect(editor.markdown()).toBe(null))
    expect(await typedAfterEdit(`See ${literal} EDIT\n`)).toBe(`See ${literal} EDIT!\n`)
  })
}

test('links in a fence and in a table are written back as typed beside an edit', async () => {
  const fenced = '```\n![[Photo.png]] [[x]]\n```\n\nEDIT\n'
  expect(await typedAfterEdit(fenced)).toBe(fenced.replace('EDIT', 'EDIT!'))
  const table = '| a | b |\n| --- | --- |\n| ![[Photo.png\\|200]] | [[a\\|b]] EDIT |\n'
  expect(await typedAfterEdit(table)).toBe(table.replace('EDIT', 'EDIT!'))
})

// An edited paragraph is written in the canonical form, which may escape brackets differently; what it reads
// as must not change.
for (const literal of ['\\[[x]]', '[\\[x]]', '!\\[[Photo.png]]', '[[ ]]', '[[]]']) {
  test(`${literal} beside an edit still reads as the same text and no link`, async () => {
    const saved = (await typedAfterEdit(`See ${literal} EDIT\n`))!
    await withLoaded(saved, (_, view) => {
      expect(view.state.doc.textContent).toBe(`See ${literal.replace(/\\(.)/g, '$1')} EDIT!`)
      view.state.doc.descendants((node) => {
        expect(node.type.name).not.toBe('embed')
        expect(node.marks.map((mark) => mark.type.name)).not.toContain('wikiLink')
      })
    })
  })
}

test('emphasis given to part of a link keeps every character and reads back as it shows', async () =>
  withLoaded('See [[Plan]] now\n', (editor, view) => {
    let at = -1
    view.state.doc.descendants((node, pos) => {
      if (at < 0 && node.isText && node.text?.includes('Plan')) at = pos + node.text.indexOf('Plan')
    })
    view.dispatch(view.state.tr.addMark(at, at + 2, view.state.schema.marks.strong!.create()))
    expect(editor.markdown()).toBe('See \\[\\[**Pl**an]] now\n')
  }))
