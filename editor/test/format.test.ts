import { expect, test } from 'vitest'
import { editorViewCtx } from '@milkdown/kit/core'
import type { Ctx } from '@milkdown/kit/ctx'
import { AllSelection, NodeSelection, TextSelection } from '@milkdown/kit/prose/state'
import { Slice } from '@milkdown/kit/prose/model'
import { serialize } from '../src/dialect'
import { NoteEditor, type CaretState } from '../src/editor'

async function withNoteEditor<T>(
  markdown: string,
  run: (editor: NoteEditor, states: CaretState[]) => T,
) {
  const root = document.createElement('div')
  document.body.append(root)
  const states: CaretState[] = []
  const editor = await NoteEditor.mount(root, {
    find() {},
    changed() {},
    stateChanged(state) {
      states.push(state)
    },
    openLink() {},
    copy() {},
  })
  editor.load(markdown, 1)
  try {
    return run(editor, states)
  } finally {
    root.remove()
  }
}

function ctxOf(editor: NoteEditor): Ctx {
  return (editor as unknown as { editor: { ctx: Ctx } }).editor.ctx
}

function placeCaret(editor: NoteEditor, pos: number) {
  const view = ctxOf(editor).get(editorViewCtx)
  view.dispatch(view.state.tr.setSelection(TextSelection.create(view.state.doc, pos)))
}

test('a loaded note opens with the caret at its end', async () =>
  withNoteEditor('# Heading\n\nA line.\n', (editor) => {
    const { doc, selection } = ctxOf(editor).get(editorViewCtx).state
    expect(selection.empty).toBe(true)
    expect(selection.from).toBe(doc.content.size - 1)
  }))

test('a note ending in a rule still opens with a caret', async () =>
  withNoteEditor('A line.\n\n---\n', (editor) => {
    expect(ctxOf(editor).get(editorViewCtx).state.selection.empty).toBe(true)
  }))

test('a loaded note is not yet changed, and an edit is, told once with its generation', async () => {
  const told: [string, number][] = []
  const root = document.createElement('div')
  document.body.append(root)
  const editor = await NoteEditor.mount(root, {
    find() {},
    changed(markdown, generation) {
      told.push([markdown, generation])
    },
    stateChanged() {},
    openLink() {},
    copy() {},
  })
  try {
    editor.load('# Heading\n\nA line.\n', 7)
    expect(editor.markdown()).toBe(null)
    expect(told).toEqual([])
    const view = ctxOf(editor).get(editorViewCtx)
    view.dispatch(view.state.tr.insertText(' More.', view.state.doc.content.size - 1))
    expect(editor.markdown()).toBe('# Heading\n\nA line. More.\n')
    await new Promise((resolve) => setTimeout(resolve, 400))
    expect(told).toEqual([['# Heading\n\nA line. More.\n', 7]])
  } finally {
    root.remove()
  }
})

test('quote toggles rather than nesting', async () => {
  await withNoteEditor('A line\n', (editor, states) => {
    placeCaret(editor, 2)
    const ctx = ctxOf(editor)
    editor.format('quote')
    expect(serialize(ctx)).toBe('> A line\n')
    expect(states.at(-1)?.quoted).toBe(true)
    expect(states.at(-1)?.block).toEqual({ type: 'paragraph' })
    editor.format('quote')
    expect(serialize(ctx)).toBe('A line\n')
    expect(states.at(-1)?.quoted).toBe(false)
  })
})

test('a list inside a quote reports both', async () => {
  await withNoteEditor('> - item\n', (editor, states) => {
    placeCaret(editor, 4)
    expect(states.at(-1)?.quoted).toBe(true)
    expect(states.at(-1)?.block).toEqual({ type: 'bulletList' })
    editor.format('quote')
    expect(serialize(ctxOf(editor))).toBe('- item\n')
  })
})

test('quote wraps the whole list when the caret is in an item', async () => {
  await withNoteEditor('- one\n- two\n', (editor, states) => {
    placeCaret(editor, 3)
    editor.format('quote')
    expect(serialize(ctxOf(editor))).toBe('> - one\n> - two\n')
    expect(states.at(-1)?.quoted).toBe(true)
    editor.format('quote')
    expect(serialize(ctxOf(editor))).toBe('- one\n- two\n')
  })
})

test('select all then quote toggles once', async () => {
  await withNoteEditor('one\n\ntwo\n', (editor, states) => {
    const view = ctxOf(editor).get(editorViewCtx)
    view.dispatch(view.state.tr.setSelection(new AllSelection(view.state.doc)))
    editor.format('quote')
    expect(serialize(ctxOf(editor))).toBe('> one\n>\n> two\n')
    view.dispatch(view.state.tr.setSelection(new AllSelection(view.state.doc)))
    expect(states.at(-1)?.quoted).toBe(true)
    editor.format('quote')
    expect(serialize(ctxOf(editor))).toBe('one\n\ntwo\n')
  })
})

test('a selection reaching out of a quote is not reported as quoted', async () => {
  await withNoteEditor('> one\n\ntwo\n', (editor, states) => {
    const view = ctxOf(editor).get(editorViewCtx)
    view.dispatch(view.state.tr.setSelection(TextSelection.create(view.state.doc, 2, 9)))
    expect(states.at(-1)?.quoted).toBe(false)
  })
})

test('inline code at a caret applies to what is typed next', async () => {
  await withNoteEditor('A line\n', (editor, states) => {
    placeCaret(editor, 3)
    editor.format('code')
    expect(states.at(-1)?.marks).toEqual(['code'])
    const view = ctxOf(editor).get(editorViewCtx)
    view.dispatch(view.state.tr.insertText('xy'))
    expect(serialize(ctxOf(editor))).toBe('A `xy`line\n')
    // The mark is not inclusive, so typing on leaves the code span.
    expect(states.at(-1)?.marks).toEqual([])
    placeCaret(editor, 4)
    expect(states.at(-1)?.marks).toEqual(['code'])
    editor.format('code')
    expect(serialize(ctxOf(editor))).toBe('A xyline\n')
  })
})

test('inline code toggled on and off again at a caret leaves nothing behind', async () => {
  await withNoteEditor('A line\n', (editor, states) => {
    placeCaret(editor, 3)
    editor.format('code')
    editor.format('code')
    expect(states.at(-1)?.marks).toEqual([])
    const view = ctxOf(editor).get(editorViewCtx)
    view.dispatch(view.state.tr.insertText('x'))
    expect(serialize(ctxOf(editor))).toBe('A xline\n')
  })
})

test('canceling a pending code mark leaves the span next to the caret alone', async () => {
  await withNoteEditor('A `foo` b\n', (editor, states) => {
    placeCaret(editor, 6)
    editor.format('code')
    expect(states.at(-1)?.marks).toEqual(['code'])
    editor.format('code')
    expect(states.at(-1)?.marks).toEqual([])
    expect(serialize(ctxOf(editor))).toBe('A `foo` b\n')
  })
})

test('code off inside a span puts the caret back', async () => {
  await withNoteEditor('A `foo` b\n', (editor) => {
    placeCaret(editor, 5)
    editor.format('code')
    expect(serialize(ctxOf(editor))).toBe('A foo b\n')
    const view = ctxOf(editor).get(editorViewCtx)
    expect(view.state.selection.empty).toBe(true)
    expect(view.state.selection.from).toBe(5)
  })
})

test('a list command toggles its own kind and converts the other', async () => {
  await withNoteEditor('- one\n- two\n', (editor, states) => {
    placeCaret(editor, 3)
    expect(states.at(-1)?.block).toEqual({ type: 'bulletList' })
    editor.format('orderedList')
    expect(serialize(ctxOf(editor))).toBe('1. one\n2. two\n')
    expect(states.at(-1)?.block).toEqual({ type: 'orderedList' })
    editor.format('bulletList')
    expect(serialize(ctxOf(editor))).toBe('- one\n- two\n')
    editor.format('bulletList')
    expect(serialize(ctxOf(editor))).toBe('one\n\n- two\n')
    expect(states.at(-1)?.block).toEqual({ type: 'paragraph' })
  })
})

test('backspace at the start of a quote leaves it', async () => {
  await withNoteEditor('> A line\n', (editor) => {
    placeCaret(editor, 2)
    const view = ctxOf(editor).get(editorViewCtx)
    const event = new KeyboardEvent('keydown', { key: 'Backspace', code: 'Backspace' })
    const handled = view.someProp('handleKeyDown', (handler) => handler(view, event))
    expect(handled).toBe(true)
    expect(serialize(ctxOf(editor))).toBe('A line\n')
  })
})

test('backspace at the start of a first list item that holds more lifts the whole item', async () => {
  const cases: [string, number, string][] = [
    ['- A\n  - a1\n- B\n', 3, 'A\n\n- a1\n- B\n'],
    ['Intro\n\n- A\n  - a1\n', 10, 'Intro\n\nA\n\n- a1\n'],
    ['- x\n  - A\n    - a1\n  - B\n', 8, '- x\n\n  A\n  - a1\n  - B\n'],
    ['1. A\n   1. a1\n2. B\n', 3, 'A\n\n1. a1\n2. B\n'],
    ['- [ ] A\n  - [ ] a1\n', 3, 'A\n\n- [ ] a1\n'],
    ['> - A\n>   - a1\n', 4, '> A\n>\n> - a1\n'],
    ['- A\n\n  ```\n  code\n  ```\n', 3, 'A\n\n```\ncode\n```\n'],
    ['- A\n\n  more\n- B\n', 3, 'A\n\nmore\n\n- B\n'],
    ['- A\n  1. a1\n- B\n', 3, 'A\n\n1. a1\n\n- B\n'],
  ]
  for (const [markdown, caret, expected] of cases) {
    await withNoteEditor(markdown, (editor) => {
      placeCaret(editor, caret)
      const view = ctxOf(editor).get(editorViewCtx)
      expect(view.state.selection.$from.parent.textContent).toBe('A')
      const event = new KeyboardEvent('keydown', { key: 'Backspace', code: 'Backspace' })
      expect(view.someProp('handleKeyDown', (handler) => handler(view, event))).toBe(true)
      expect(serialize(ctxOf(editor))).toBe(expected)
      const { $from } = view.state.selection
      expect([$from.parent.textContent, $from.parentOffset]).toEqual(['A', 0])
    })
  }
})

test('lifting a list item that holds a nested list leaves one list, not two', async () => {
  const cases: [string, number, string][] = [
    ['- A\n  - a1\n- B\n', 3, 'A\n\n- a1\n- B\n'],
    ['- x\n- A\n  - a1\n- B\n', 8, '- x\n\nA\n\n- a1\n- B\n'],
    ['- x\n  - A\n    - a1\n  - B\n', 8, '- x\n- A\n  - a1\n  - B\n'],
    ['1. A\n   1. a1\n2. B\n', 3, 'A\n\n1. a1\n2. B\n'],
    ['- [ ] A\n  - [ ] a1\n- [ ] B\n', 3, 'A\n\n- [ ] a1\n- [ ] B\n'],
    ['- A\n  1. a1\n- B\n', 3, 'A\n\n1. a1\n\n- B\n'],
    ['> - A\n>   - a1\n> - B\n', 4, '> A\n>\n> - a1\n> - B\n'],
  ]
  const lifts: [string, (editor: NoteEditor) => void][] = [
    [
      'Shift-Tab',
      (editor) => {
        const view = ctxOf(editor).get(editorViewCtx)
        const event = new KeyboardEvent('keydown', { key: 'Tab', shiftKey: true })
        expect(view.someProp('handleKeyDown', (handler) => handler(view, event))).toBe(true)
      },
    ],
    [
      'the list command',
      (editor) => {
        const view = ctxOf(editor).get(editorViewCtx)
        const list = view.state.selection.$from.node(-2).type.name
        editor.format(list === 'ordered_list' ? 'orderedList' : 'bulletList')
      },
    ],
  ]
  for (const [name, lift] of lifts) {
    for (const [markdown, caret, expected] of cases) {
      await withNoteEditor(markdown, (editor) => {
        placeCaret(editor, caret)
        const view = ctxOf(editor).get(editorViewCtx)
        expect(view.state.selection.$from.parent.textContent).toBe('A')
        lift(editor)
        expect([name, serialize(ctxOf(editor))]).toEqual([name, expected])
        expect(view.state.selection.$from.parent.textContent).toBe('A')
      })
    }
  }
})

test('a fenced block with a known language is colored, one without stays plain', async () => {
  await withNoteEditor('```js\nconst x = 1\n```\n\n```\nplain\n```\n', (editor) => {
    const view = ctxOf(editor).get(editorViewCtx)
    const spans = view.dom.querySelectorAll('pre [class*="hljs-"]')
    expect(spans.length).toBeGreaterThan(0)
    expect(view.dom.querySelectorAll('pre')[1]?.querySelector('[class*="hljs-"]')).toBeNull()
    expect(serialize(ctxOf(editor))).toBe('```js\nconst x = 1\n```\n\n```\nplain\n```\n')
  })
})

test('control characters typed into the note are dropped', async () => {
  await withNoteEditor('Plan\n', (editor) => {
    const view = ctxOf(editor).get(editorViewCtx)
    placeCaret(editor, 1)
    const swallowed = view.someProp('handleTextInput', (handler) =>
      handler(view, 1, 1, '\u000e', () => view.state.tr),
    )
    expect(swallowed).toBe(true)
    const typed = view.someProp('handleTextInput', (handler) =>
      handler(view, 1, 1, 'a', () => view.state.tr),
    )
    expect(typed).not.toBe(true)
  })
})

test('list items indent with Tab or Command-] and outdent with Shift-Tab or Command-[, as in Notes', async () => {
  await withNoteEditor('- one\n- two\n', (editor) => {
    placeCaret(editor, 9)
    const view = ctxOf(editor).get(editorViewCtx)
    const press = (key: string, init: KeyboardEventInit = {}) =>
      view.someProp('handleKeyDown', (f) => f(view, new KeyboardEvent('keydown', { key, ...init })))
    expect(press('Tab')).toBe(true)
    expect(serialize(ctxOf(editor))).toBe('- one\n  - two\n')
    expect(press('Tab', { shiftKey: true })).toBe(true)
    expect(serialize(ctxOf(editor))).toBe('- one\n- two\n')
    expect(press(']', { metaKey: true })).toBe(true)
    expect(serialize(ctxOf(editor))).toBe('- one\n  - two\n')
    expect(press('[', { metaKey: true })).toBe(true)
    expect(serialize(ctxOf(editor))).toBe('- one\n- two\n')
  })
})

test('a deleted note takes no edit, whether formatted, toggled or undone', async () => {
  await withNoteEditor('- [ ] Old list\n', (editor) => {
    editor.setEditable(false)
    editor.load('- [ ] Old list\n', 2)
    editor.format('bold')
    editor.format('heading', 1)
    const view = ctxOf(editor).get(editorViewCtx)
    const item = view.dom.querySelector('li[data-item-type="task"]') as HTMLElement
    view.someProp('handleClickOn', (f) =>
      f(
        view,
        1,
        view.state.doc.child(0).child(0),
        1,
        { target: item } as unknown as MouseEvent,
        true,
      ),
    )
    editor.undo()
    expect(editor.markdown()).toBe(null)
  })
})

test('an edit still waiting to be reported goes to its own note when another loads', async () => {
  const told: [string, number][] = []
  const root = document.createElement('div')
  document.body.append(root)
  const editor = await NoteEditor.mount(root, {
    find() {},
    changed(markdown, generation) {
      told.push([markdown, generation])
    },
    stateChanged() {},
    openLink() {},
    copy() {},
  })
  try {
    editor.load('First\n', 1)
    const view = ctxOf(editor).get(editorViewCtx)
    view.dispatch(view.state.tr.insertText(' edited', view.state.doc.content.size - 1))
    editor.load('Second\n', 2)
    await new Promise((resolve) => setTimeout(resolve, 400))
    expect(told).toEqual([['First edited\n', 1]])
  } finally {
    root.remove()
  }
})

test('flushing hands over an edit not yet reported, once', async () => {
  await withNoteEditor('Draft\n', (editor) => {
    expect(editor.flush()).toBe(null)
    const view = ctxOf(editor).get(editorViewCtx)
    view.dispatch(view.state.tr.insertText('!', view.state.doc.content.size - 1))
    expect(editor.flush()).toBe('Draft!\n')
    expect(editor.flush()).toBe(null)
  })
})

test('the heading under the caret carries its marks, the others do not', async () => {
  await withNoteEditor('# One\n\nText\n\n## Two\n', (editor) => {
    const view = ctxOf(editor).get(editorViewCtx)
    placeCaret(editor, 2)
    expect(view.dom.querySelector('h1.editing')).not.toBeNull()
    expect(view.dom.querySelector('h2.editing')).toBeNull()
    placeCaret(editor, 9)
    expect(view.dom.querySelector('.editing')).toBeNull()
    expect(serialize(ctxOf(editor))).toBe('# One\n\nText\n\n## Two\n')
  })
  await withNoteEditor('> # Quoted\n', (editor) => {
    placeCaret(editor, 3)
    expect(
      ctxOf(editor).get(editorViewCtx).dom.querySelector('blockquote > h1.editing'),
    ).not.toBeNull()
  })
})

test('an empty note turned into a heading shows its marks', async () => {
  await withNoteEditor('', (editor) => {
    const view = ctxOf(editor).get(editorViewCtx)
    editor.format('heading', 1)
    expect(view.dom.querySelector('h1.editing')).not.toBeNull()
  })
})

test('formatting keys are the ones the app sets', async () => {
  await withNoteEditor('word\n', (editor) => {
    const view = ctxOf(editor).get(editorViewCtx)
    const press = (key: string, init: KeyboardEventInit = {}) =>
      view.someProp('handleKeyDown', (f) => f(view, new KeyboardEvent('keydown', { key, ...init })))
    view.dispatch(view.state.tr.setSelection(TextSelection.create(view.state.doc, 1, 5)))
    // The preset's own Mod-b is gone until the app binds something.
    expect(press('b', { metaKey: true })).toBeFalsy()
    editor.setKeymap({ 'Mod-b': ['bold'], 'Shift-Mod-h': ['heading', '2'] })
    expect(press('b', { metaKey: true })).toBe(true)
    expect(serialize(ctxOf(editor))).toBe('**word**\n')
    expect(press('h', { metaKey: true, shiftKey: true })).toBe(true)
    expect(serialize(ctxOf(editor))).toBe('## **word**\n')
    expect(press('u', { metaKey: true })).toBeFalsy()
    editor.setKeymap({ 'Shift-Mod-b': ['bold'] })
    expect(press('b', { metaKey: true })).toBeFalsy()
  })
})

function paste(editor: NoteEditor, data: Record<string, string>, files: File[] = []): boolean {
  const view = ctxOf(editor).get(editorViewCtx)
  const event = {
    clipboardData: { getData: (type: string) => data[type] ?? '', types: Object.keys(data), files },
  } as unknown as ClipboardEvent
  return view.someProp('handlePaste', (handler) => handler(view, event, Slice.empty)) ?? false
}

test('pasting a url over a selection links what is selected', async () => {
  await withNoteEditor('Read the notes\n', (editor) => {
    const view = ctxOf(editor).get(editorViewCtx)
    view.dispatch(view.state.tr.setSelection(TextSelection.create(view.state.doc, 10, 15)))
    expect(paste(editor, { 'text/plain': 'https://example.com' })).toBe(true)
    expect(serialize(ctxOf(editor))).toBe('Read the [notes](https://example.com)\n')
  })
})

// The app's own paste handler alone, since the preset's clipboard takes any paste it leaves.
function ownPaste(editor: NoteEditor, text: string): boolean {
  const view = ctxOf(editor).get(editorViewCtx)
  const plugin = view.state.plugins.find((plugin) =>
    (plugin as unknown as { key: string }).key.startsWith('paste$'),
  )
  const event = {
    clipboardData: { getData: () => text, types: ['text/plain'], files: [] },
  } as unknown as ClipboardEvent
  return plugin?.props.handlePaste?.call(plugin, view, event, Slice.empty) ?? false
}

test('pasting a url with nothing selected leaves the paste to the editor', async () => {
  await withNoteEditor('A line\n', (editor) => {
    placeCaret(editor, 3)
    expect(ownPaste(editor, 'https://example.com')).toBe(false)
    const view = ctxOf(editor).get(editorViewCtx)
    view.dispatch(view.state.tr.setSelection(TextSelection.create(view.state.doc, 3, 7)))
    expect(ownPaste(editor, 'https://example.com')).toBe(true)
    expect(serialize(ctxOf(editor))).toBe('A [line](https://example.com)\n')
  })
})

test('an image from the web is shown as its alt text, never fetched', async () => {
  await withNoteEditor('![Somewhere else](https://example.com/far.png)\n', (editor) => {
    const dom = ctxOf(editor).get(editorViewCtx).dom
    expect(dom.querySelector('.image img')).toBe(null)
    expect(dom.querySelector('.image-absent')?.textContent).toBe('Somewhere else')
  })
})

test('images go on lines of their own from an empty line', async () =>
  withNoteEditor('', (editor) => {
    editor.insertImages([
      { src: 'Attachments/Photo%201.png', alt: 'Photo 1' },
      { src: 'Attachments/b.png', alt: 'b' },
    ])
    expect(editor.markdown()).toBe(
      '![Photo 1](Attachments/Photo%201.png)\n\n![b](Attachments/b.png)\n',
    )
  }))

test('an image goes inline within text', async () =>
  withNoteEditor('Before\n', (editor) => {
    placeCaret(editor, 4)
    editor.insertImages([{ src: 'Attachments/b.png', alt: 'b' }])
    expect(editor.markdown()).toBe('Bef![b](Attachments/b.png)ore\n')
  }))

test('a read-only note takes no images', async () =>
  withNoteEditor('Old\n', (editor) => {
    editor.setEditable(false)
    editor.insertImages([{ src: 'Attachments/a.png', alt: 'a' }])
    expect(editor.markdown()).toBeNull()
  }))

function posOf(editor: NoteEditor, text: string): number {
  let found = -1
  ctxOf(editor)
    .get(editorViewCtx)
    .state.doc.descendants((node, pos) => {
      if (found < 0 && node.isText && node.text?.includes(text))
        found = pos + node.text.indexOf(text)
    })
  return found
}

test('a checklist made in a nested item leaves the item around it alone', async () =>
  withNoteEditor('- Outer\n  - Inner\n', (editor) => {
    placeCaret(editor, posOf(editor, 'Inner') + 1)
    editor.format('taskList')
    expect(editor.markdown()).toBe('- Outer\n  - [ ] Inner\n')
  }))

test('spaces at the edges of a paragraph or heading are not written, so they never become entities', async () =>
  withNoteEditor('', (editor) => {
    const view = ctxOf(editor).get(editorViewCtx)
    view.dispatch(view.state.tr.insertText(' Hello  '))
    expect(editor.markdown()).toBe('Hello\n')
    editor.format('heading', 2)
    expect(editor.markdown()).toBe('## Hello\n')
  }))

test('an image is drawn at the width in its alt text, and shows its name without it', async () => {
  const webkit = window.webkit
  window.webkit = {
    messageHandlers: {
      embeds: {
        postMessage: async () => ({
          url: 'mapp-embed://file/a',
          kind: 'image' as const,
          name: 'a.png',
          detail: '1 KB',
          icon: 'mapp-embed://icon/a',
          opens: true,
        }),
      },
    },
  }
  try {
    await withNoteEditor(
      '![Dusk|320](Attachments/a.png) and ![Far|90](https://example.com/far.png)\n',
      async (editor) => {
        await new Promise((resolve) => setTimeout(resolve, 0))
        const dom = ctxOf(editor).get(editorViewCtx).dom
        const image = dom.querySelector('.image img') as HTMLImageElement
        expect(image.alt).toBe('Dusk')
        expect(image.style.width).toBe('320px')
        expect(dom.querySelector('.image .image-handle')).not.toBe(null)
        expect(dom.querySelector('.image-absent')?.textContent).toBe('Far')
        expect(editor.markdown()).toBe(null)
      },
    )
  } finally {
    window.webkit = webkit
  }
})

test('a width in a table cell is escaped where the cell needs it and read back', async () =>
  withNoteEditor('| A |\n| --- |\n| ![Photo\\|400](Attachments/a.png) |\n', (editor) => {
    const image = ctxOf(editor).get(editorViewCtx).dom.querySelector('.image-absent, .image')
    expect(image).not.toBe(null)
    let alt = ''
    ctxOf(editor)
      .get(editorViewCtx)
      .state.doc.descendants((node) => {
        if (node.type.name === 'image') alt = String(node.attrs.alt)
      })
    expect(alt).toBe('Photo|400')
    placeCaret(editor, posOf(editor, 'A') + 1)
    editor.format('alignColumn', 'center')
    expect(editor.markdown()).toContain('![Photo\\|400](Attachments/a.png)')
  }))

test('spelling is checked as typed unless the app turns it off', async () => {
  await withNoteEditor('Teh plan', (editor) => {
    const dom = ctxOf(editor).get(editorViewCtx).dom
    expect(dom.getAttribute('spellcheck')).toBe('true')
    editor.setSpellcheck(false)
    expect(dom.getAttribute('spellcheck')).toBe('false')
    editor.setSpellcheck(true)
    expect(dom.getAttribute('spellcheck')).toBe('true')
  })
})
