import { readdirSync, readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { expect, test, vi } from 'vitest'
import { InkKitError } from '@aicayzer/inkkit'
import { pickNote, suggestNotes } from '../src/bridge'
import {
  NoteEditor,
  caretOffset,
  isPreviewDiagnostic,
  guardedCommand,
  splitLabels,
  type CaretState,
  type FindState,
} from '../src/editor'

async function withEditor(
  source: string,
  run: (editor: NoteEditor) => void | Promise<void>,
  changed: (text: string) => void = () => {},
) {
  const root = document.createElement('div')
  document.body.append(root)
  const editor = await NoteEditor.mount(root, {
    find() {},
    changed,
    stateChanged() {},
    openLink() {},
    copy() {},
  })
  editor.setItem('note')
  editor.load(source, 1)
  try {
    await run(editor)
  } finally {
    await editor.destroy()
    root.remove()
  }
}
const corpus = resolve(import.meta.dirname, '../fixtures/corpus')
for (const name of readdirSync(corpus).filter((name) => name.endsWith('.md'))) {
  const source = readFileSync(resolve(corpus, name), 'utf8')
  test(name + ' retains untouched source through a formatted edit and undo', async () =>
    withEditor(source, (editor) => {
      expect(editor.markdown()).toBeNull()
      const engine = (editor as unknown as { engine: import('@aicayzer/inkkit').InkKitEditor })
        .engine
      const text = engine.textSnapshot(1)
      const at = text.text.indexOf('EDIT HERE') + 'EDIT HERE'.length
      expect(at).toBeGreaterThan(8)
      engine.selectTextRange({ snapshotId: text.snapshotId, from: at, to: at })
      engine.insertText('!', 1)
      expect(editor.snapshot().text).toBe(source.replace('EDIT HERE', 'EDIT HERE!'))
      editor.undo()
      expect(editor.snapshot().text).toBe(source)
    }),
  )
}
test('native readable ranges reject stale generations and preserve formatted replacement history', async () =>
  withEditor('A **bold** line.\n', (editor) => {
    editor.findReplace(2, 6, 'strong', 1)
    expect(editor.snapshot().text).toBe('A **strong** line.\n')
    editor.undo()
    expect(editor.snapshot().text).toBe('A **bold** line.\n')
    editor.reload('External\n', 2)
    expect(() => editor.findReplace(0, 8, 'Wrong', 1)).toThrow()
    expect(editor.snapshot().text).toBe('External\n')
  }))
test('read-only rejects changes without losing text or history', async () =>
  withEditor('Original\n', (editor) => {
    editor.reload('Original\n', 2, false)
    expect(() => editor.findReplace(0, 8, 'Wrong', 2)).toThrow()
    expect(editor.snapshot().text).toBe('Original\n')
  }))

test('source edits share undo and reject stale mode changes', async () =>
  withEditor('A **bold** line.\n![[A note]]\n', (editor) => {
    editor.setEditingMode('source', 1)
    editor.findReplace(0, 1, 'The', 1)
    expect(editor.snapshot().text).toBe('The **bold** line.\n![[A note]]\n')
    editor.setEditingMode('formatted', 1)
    editor.undo(1)
    expect(editor.snapshot().text).toBe('A **bold** line.\n![[A note]]\n')
    editor.reload('Replacement\n', 2)
    expect(() => editor.setEditingMode('source', 1)).toThrow()
    expect(editor.snapshot().text).toBe('Replacement\n')
  }))

test('an embed asks the app by its text as written, and one the app does not answer is missing', async () => {
  const asked: unknown[] = []
  Object.defineProperty(window, 'webkit', {
    configurable: true,
    value: {
      messageHandlers: {
        embeds: {
          postMessage: async (request: unknown) => {
            asked.push(request)
            return null
          },
        },
      },
    },
  })
  try {
    await withEditor('![[A note]]\n\n![Section](note.md#part)\n', async (editor) => {
      await vi.waitFor(() => expect(asked).toHaveLength(2))
      expect(asked).toEqual([
        { item: 'note', text: '![[A note]]' },
        { item: 'note', text: '![Section](note.md#part)' },
      ])
      await vi.waitFor(() =>
        expect(
          [...document.querySelectorAll('.inkkit-file-status')].map((e) => e.textContent),
        ).toEqual(['File unavailable', 'File unavailable']),
      )
      expect(editor.snapshot().text).toBe('![[A note]]\n\n![Section](note.md#part)\n')
    })
  } finally {
    delete (window as { webkit?: unknown }).webkit
  }
})

test('embeds are asked by their text as written, once each, and asked again only when the app says they changed', async () => {
  const asked: { text: string }[] = []
  let name = 'one.png'
  Object.defineProperty(window, 'webkit', {
    configurable: true,
    value: {
      messageHandlers: {
        embeds: {
          postMessage: async (request: { text: string }) => {
            asked.push(request)
            return { kind: 'image', name, url: `mapp-embed:x/${name}` }
          },
        },
      },
    },
  })
  const source =
    '![[pic.png|400]]\n\n![[pic.png|400]]\n\n- ![[a.png]]\n\n> ![[b.png]]\n\n| a | b |\n| --- | --- |\n| ![[q.png\\|200]] | x |\n'
  const texts = ['![[a.png]]', '![[b.png]]', '![[pic.png|400]]', '![[q.png\\|200]]']
  try {
    await withEditor(source, async (editor) => {
      await vi.waitFor(() => expect(document.querySelectorAll('.inkkit-file img').length).toBe(5))
      expect(asked.map((r) => r.text).sort()).toEqual(texts)
      name = 'two.png'
      editor.embedsChanged(['![[pic.png|400]]'])
      await vi.waitFor(() =>
        expect(
          [...document.querySelectorAll('.inkkit-file img')].filter(
            (e) => e.getAttribute('src') === 'mapp-embed:x/two.png',
          ),
        ).toHaveLength(2),
      )
      expect(asked.filter((r) => r.text === '![[pic.png|400]]')).toHaveLength(2)
      expect(asked).toHaveLength(5)
      expect(editor.snapshot().text).toBe(source)
    })
  } finally {
    delete (window as { webkit?: unknown }).webkit
  }
})

test('cached native Find scopes reject same-note edits and ordered replacement batches stop at intervening edits', async () =>
  withEditor('one one\n', (editor) => {
    const engine = (editor as unknown as { engine: import('@aicayzer/inkkit').InkKitEditor }).engine
    const first = engine.textSnapshot(1)
    editor.findReplace(0, 3, 'two', 1, first.snapshotId, 'batch')
    editor.findReplace(4, 7, 'two', 1, first.snapshotId, 'batch')
    expect(editor.snapshot().text).toBe('two two\n')
    expect(() => editor.findSelect(0, 3, 1, first.snapshotId)).toThrow()
    expect(() => editor.findReplace(0, 3, 'bad', 1, first.snapshotId, 'new-batch')).toThrow()
    editor.setEditingMode('source', 1)
    editor.findReplace(0, 3, 'new', 1)
    expect(() => editor.findReplace(4, 7, 'bad', 1, first.snapshotId, 'batch')).toThrow()
    expect(editor.snapshot().text).toBe('new two\n')
  }))

test('one logical task-list command reports only final source while later turns still report separately', async () => {
  const root = document.createElement('div')
  document.body.append(root)
  const changes: string[] = []
  const editor = await NoteEditor.mount(root, {
    changed(text) {
      changes.push(text)
    },
    stateChanged() {},
    find() {},
    copy() {},
    openLink() {},
  })
  editor.setItem('note')
  editor.load('Milk\n', 1)
  try {
    editor.format('taskList')
    await Promise.resolve()
    expect(changes).toEqual(['- [ ] Milk\n'])
    editor.setEditingMode('source')
    editor.findReplace(6, 10, 'Bread')
    await Promise.resolve()
    expect(changes).toEqual(['- [ ] Milk\n', '- [ ] Bread\n'])
  } finally {
    await editor.destroy()
    root.remove()
  }
})

test('a flush of a generation the page has reloaded past hands back nothing, since the reload reported it', async () => {
  const root = document.createElement('div')
  document.body.append(root)
  const changes: [string, number][] = []
  const editor = await NoteEditor.mount(root, {
    changed(text, generation) {
      changes.push([text, generation])
    },
    stateChanged() {},
    find() {},
    copy() {},
    openLink() {},
  })
  editor.setItem('note')
  editor.load('Milk\n', 1)
  try {
    editor.format('taskList')
    editor.reload('Outside\n', 2)
    expect(changes).toEqual([['- [ ] Milk\n', 1]])
    expect(editor.flush(1)).toBeNull()
  } finally {
    await editor.destroy()
    root.remove()
  }
})

test('explicit flush returns a pending logical edit without a later duplicate report', async () => {
  const root = document.createElement('div')
  document.body.append(root)
  const changes: string[] = []
  const editor = await NoteEditor.mount(root, {
    changed(text) {
      changes.push(text)
    },
    stateChanged() {},
    find() {},
    copy() {},
    openLink() {},
  })
  editor.setItem('note')
  editor.load('Milk\n', 1)
  try {
    editor.format('taskList')
    expect(editor.flush(1)).toBe('- [ ] Milk\n')
    await Promise.resolve()
    expect(changes).toEqual([])
    expect(editor.flush(1)).toBeNull()
  } finally {
    await editor.destroy()
    root.remove()
  }
})

test('a rejected replacement poisons its batch rather than applying shifted later offsets', async () =>
  withEditor('one one\n', (editor) => {
    const snapshot = editor.readableSnapshot(1)
    expect(() => editor.findReplace(-1, 3, 'longer', 1, snapshot.snapshotId, 'failed')).toThrow()
    expect(() => editor.findReplace(4, 7, 'wrong', 1, snapshot.snapshotId, 'failed')).toThrow()
    expect(editor.snapshot().text).toBe('one one\n')
    editor.findReplace(0, 3, 'two', 1, snapshot.snapshotId, 'middle')
    expect(() => editor.findReplace(4, 100, 'longer', 1, snapshot.snapshotId, 'middle')).toThrow()
    expect(() => editor.findReplace(4, 7, 'wrong', 1, snapshot.snapshotId, 'middle')).toThrow()
    expect(editor.snapshot().text).toBe('two one\n')
  }))

test('preview fallbacks remain diagnostic and expected command rejections stay local', async () => {
  expect(isPreviewDiagnostic(new InkKitError('file-unavailable', 'Preview unavailable'))).toBe(true)
  expect(isPreviewDiagnostic(new InkKitError('diagram-unavailable', 'Bad diagram'))).toBe(true)
  expect(isPreviewDiagnostic(new InkKitError('preservation', 'Refused'))).toBe(false)
  expect(isPreviewDiagnostic(new Error('Preview unavailable'))).toBe(false)
  await withEditor('one\n', (editor) => {
    const snapshot = editor.readableSnapshot(1)
    editor.findReplace(0, 3, 'two', 1)
    expect(guardedCommand(() => editor.findSelect(0, 3, 1, snapshot.snapshotId))).toMatchObject({
      commandError: 'stale-document',
    })
    expect(editor.snapshot().text).toBe('two\n')
  })
})

test('Find batches visible geometry, retains UTF-16 offsets, and coalesces layout refreshes', async () => {
  const root = document.createElement('div')
  document.body.append(root)
  const reports: FindState[] = []
  let layoutChanged: () => void = () => {}
  const disconnect = vi.fn()
  vi.stubGlobal(
    'ResizeObserver',
    class {
      constructor(callback: () => void) {
        layoutChanged = callback
      }
      observe() {}
      disconnect = disconnect
    },
  )
  const editor = await NoteEditor.mount(root, {
    find: (state) => reports.push(state),
    changed() {},
    stateChanged() {},
    openLink() {},
    copy() {},
  })
  const frames = new Map<number, FrameRequestCallback>()
  let nextFrame = 1
  vi.spyOn(window, 'requestAnimationFrame').mockImplementation((callback) => {
    const id = nextFrame++
    frames.set(id, callback)
    return id
  })
  vi.spyOn(window, 'cancelAnimationFrame').mockImplementation((id) => {
    frames.delete(id)
  })
  try {
    editor.load('A😀B gap C\n', 1)
    await Promise.resolve()
    const engine = (editor as unknown as { engine: import('@aicayzer/inkkit').InkKitEditor }).engine
    const snapshotId = engine.textSnapshot(1).snapshotId
    vi.spyOn(engine, 'visibleTextRanges').mockReturnValue([
      { snapshotId, from: 0, to: 4 },
      { snapshotId, from: 9, to: 10 },
    ])
    const batch = vi.fn((ranges: { from: number }[]) =>
      ranges.map((range) => [{ left: range.from, top: 20, width: 8, height: 16 }]),
    )
    Object.defineProperty(engine, 'textRangesRects', { value: batch, configurable: true })
    editor.setFinding(true)
    expect(batch).toHaveBeenCalledTimes(1)
    expect(batch.mock.calls[0]![0].map((range) => range.from)).toEqual([0, 1, 3, 9])
    expect(reports[0]!.visible).toEqual([0, 10])
    expect(reports[0]!.boxes.slice(4, 8)).toEqual(reports[0]!.boxes.slice(8, 12))
    expect(reports[0]!.boxes.slice(16, 36)).toEqual(new Array(20).fill(0))
    window.dispatchEvent(new Event('resize'))
    root.dispatchEvent(new Event('load'))
    root.dispatchEvent(new Event('loadedmetadata'))
    layoutChanged()
    editor.invalidateFindGeometry()
    expect(frames.size).toBe(1)
    const [id, refresh] = [...frames.entries()][0]!
    frames.delete(id)
    refresh(0)
    expect(batch).toHaveBeenCalledTimes(2)
    editor.invalidateFindGeometry()
    editor.setFinding(false)
    expect(frames.size).toBe(0)
    window.dispatchEvent(new Event('resize'))
    layoutChanged()
    expect(frames.size).toBe(0)
  } finally {
    await editor.destroy()
    expect(disconnect).toHaveBeenCalledOnce()
    root.remove()
    vi.restoreAllMocks()
    vi.unstubAllGlobals()
  }
})

test("the words the app sends mount Inkkit, with the app's own kept out of its labels", async () => {
  const swift = readFileSync(
    resolve(import.meta.dirname, '../../MAPP/Editor/EditorController+PageSettings.swift'),
    'utf8',
  )
  const start = swift.indexOf('static var editorLabels')
  const block = swift.slice(start, swift.indexOf('\n        ]\n', start))
  const sent = Object.fromEntries(
    [...block.matchAll(/^\s+"(\w+)":\s*String\(localized: "([^"]*)"\)/gm)].map((match) => [
      match[1]!,
      match[2]!,
    ]),
  )
  expect(Object.keys(sent).length).toBeGreaterThan(30)
  const labels = splitLabels(sent)
  expect(Object.keys(labels.header).sort()).toEqual(
    [
      'discardChanges',
      'itemType',
      'linkedFrom',
      'parentRejected',
      'properties',
      'propertyRejected',
      'status',
      'title',
      'untitled',
    ].sort(),
  )
  expect(labels.words.linkToNote).toBeTruthy()
  expect(Object.keys(labels.editor)).not.toContain('linkToNote')
  expect(Object.keys(labels.editor)).not.toContain('untitled')

  const root = document.createElement('div')
  document.body.append(root)
  const editor = await NoteEditor.mount(
    root,
    { find() {}, changed() {}, stateChanged() {}, openLink() {}, copy() {} },
    labels.editor,
    labels.words,
  )
  try {
    await expect(
      NoteEditor.mount(
        document.createElement('div'),
        {
          find() {},
          changed() {},
          stateChanged() {},
          openLink() {},
          copy() {},
        },
        sent as never,
      ),
    ).rejects.toMatchObject({ code: 'invalid-argument' })
  } finally {
    await editor.destroy()
    root.remove()
  }
})

test('the page reports a heading by its level and applies the level the app asks for', async () => {
  const root = document.createElement('div')
  document.body.append(root)
  const states: CaretState[] = []
  const editor = await NoteEditor.mount(root, {
    find() {},
    changed() {},
    stateChanged: (state) => states.push(state),
    openLink() {},
    copy() {},
  })
  editor.setItem('note')
  editor.load('Milk\n', 1)
  try {
    const formats = states.at(-1)!.formats
    for (const level of [1, 2, 3, 4, 5, 6]) expect(formats['heading' + level]).toBe(true)
    expect('heading' in formats).toBe(false)
    editor.format('heading', 2)
    expect(editor.snapshot().text).toBe('## Milk\n')
    expect(states.at(-1)!.block).toEqual({ type: 'heading', level: 2 })
    editor.format('heading', '3')
    expect(editor.snapshot().text).toBe('### Milk\n')
    expect(() =>
      editor.setKeymap({
        'Mod-Alt-2': ['heading', '2'],
        'Mod-Alt-0': ['paragraph'],
        'Mod-Alt-t': ['table'],
      }),
    ).not.toThrow()
  } finally {
    await editor.destroy()
    root.remove()
  }
})

test('images go in at the caret or at a drop point, and blur leaves the focus off the text', async () => {
  await withEditor('Milk\n', (editor) => {
    expect(editor.insertImages([{ src: 'Attachments/a%201.png', alt: 'a' }])).toBe(true)
    expect(editor.snapshot().text).toContain('![a](Attachments/a%201.png)')
    expect(editor.insertImages([{ src: 'b.png', alt: 'b' }], 10, 20)).toBe(true)
    expect(editor.insertImages([{ src: 'c.png', alt: 'c' }], 10, null)).toBe(true)
    expect(editor.snapshot().text).toContain('![b](b.png)')
    expect(editor.snapshot().text).toContain('![c](c.png)')
    editor.focus()
    expect(document.activeElement?.matches('.ProseMirror')).toBe(true)
    editor.blur(1)
    expect(document.activeElement?.matches('.ProseMirror')).toBe(false)
    expect(() => editor.blur(2)).toThrow()
  })
})

test('files attached in quick add go at the end of the text and leave the caret where it was', async () => {
  await withEditor('Buy milk\n\nand eggs\n', (editor) => {
    const engine = (editor as unknown as { engine: import('@aicayzer/inkkit').InkKitEditor }).engine
    editor.focusText('Buy')
    expect(
      editor.appendImages([
        { src: 'a%201.pdf', alt: 'a 1.pdf' },
        { src: 'b.png', alt: 'b.png' },
      ]),
    ).toBe(true)
    const text = editor.markdown() ?? ''
    expect(text.startsWith('Buy milk\n\nand eggs\n')).toBe(true)
    expect(text.indexOf('![a 1.pdf](a%201.pdf)')).toBeGreaterThan(text.indexOf('and eggs'))
    expect(text.indexOf('![b.png](b.png)')).toBeGreaterThan(text.indexOf('![a 1.pdf]'))
    expect(engine.textSnapshot(1).selection).toMatchObject({ from: 3, to: 3 })
    expect(() => editor.appendImages([{ src: 'c.png', alt: 'c' }], 2)).toThrow()
  })
  await withEditor('', (editor) => {
    expect(editor.appendImages([{ src: 'a.png', alt: 'a' }])).toBe(true)
    expect(editor.markdown()).toContain('![a](a.png)')
  })
})

test('files attached in quick add go after a table that ends the text, not into its last cell', async () => {
  const table = 'Costs\n\n| Item | Cost |\n| --- | --- |\n| Train | 40 |\n'
  await withEditor(table, (editor) => {
    const engine = (editor as unknown as { engine: import('@aicayzer/inkkit').InkKitEditor }).engine
    editor.focusText('Cos')
    expect(editor.appendImages([{ src: 'ticket.pdf', alt: 'ticket.pdf' }])).toBe(true)
    expect(editor.markdown()).toBe(table + '\n![ticket.pdf](ticket.pdf)\n')
    expect(engine.textSnapshot(1).selection).toMatchObject({ from: 3, to: 3 })
  })
})

test('files attached in quick add go after a list that ends the text, not into its last item', async () => {
  for (const list of ['- Pack\n- Book', '1. Pack\n2. Book\n', '- [ ] Pack\n  - Book\n\n']) {
    await withEditor(list, (editor) => {
      expect(editor.appendImages([{ src: 'map.png', alt: 'map' }])).toBe(true)
      const text = editor.markdown() ?? ''
      expect(text.startsWith(list)).toBe(true)
      expect(text.slice(list.length).replace(/^\n+/, '')).toBe('![map](map.png)\n')
      expect(text).toMatch(/\n\n!\[map\]/)
    })
  }
})

test("files attached in quick add are written so they read back as embeds, in the note's own line endings", async () => {
  const images = [
    { src: 'a (1).png', alt: 'a [1]' },
    { src: 'b%201.png', alt: 'b' },
  ]
  const written = '![a \\[1\\]](<a (1).png>)'
  for (const [source, expected] of [
    ['```\ncode\n```', '```\ncode\n```\n\n' + written + '\n\n![b](b%201.png)\n'],
    ['- a\n  ```\n  code', '- a\n  ```\n  code\n\n' + written + '\n\n![b](b%201.png)\n'],
    ['One\r\nTwo', 'One\r\nTwo\r\n\r\n' + written + '\r\n\r\n![b](b%201.png)\r\n'],
    ['', written + '\n\n![b](b%201.png)\n'],
  ] as const) {
    await withEditor(source, (editor) => {
      expect(editor.appendImages(images)).toBe(true)
      expect(editor.snapshot().text).toBe(expected)
      editor.undo()
      expect(editor.snapshot().text).toBe(source)
    })
  }
})

test('files attached in quick add are refused, with the note untouched, when the text ends in an open code fence', async () => {
  for (const source of ['```\ncode', '```\ncode\n', '~~~~ js\n~~~\n']) {
    await withEditor(source, (editor) => {
      expect(guardedCommand(() => editor.appendImages([{ src: 'a.png', alt: 'a' }]))).toMatchObject(
        {
          commandError: 'preservation',
        },
      )
      expect(editor.snapshot().text).toBe(source)
      expect(editor.markdown()).toBeNull()
    })
  }
})

test('files attached in quick add never replace a note that Inkkit reads as one empty block', async () => {
  const images = [
    { src: 'a.png', alt: 'a' },
    { src: 'b.png', alt: 'b' },
  ]
  const posted: unknown[] = []
  window.webkit = { messageHandlers: { host: { postMessage: (message) => posted.push(message) } } }
  for (const source of [
    '***',
    '---\n',
    '___',
    '```\n```',
    '```\n```\n',
    '<br>',
    '![x](y.png)',
    '![x](y.png)\n',
    '[ref]: http://x.com',
    '[ref]: http://x.com\n',
  ]) {
    posted.length = 0
    const reported: string[] = []
    await withEditor(
      source,
      async (editor) => {
        expect(
          guardedCommand(() => editor.appendImages(images)),
          source,
        ).toMatchObject({
          commandError: 'preservation',
        })
        // The text is exactly as it was, and neither the replaced text nor the restored one reached the app.
        expect(editor.snapshot().text).toBe(source)
        expect(editor.markdown()).toBeNull()
        await Promise.resolve()
        expect(reported).toEqual([])
        expect(posted).toMatchObject([{ type: 'error' }])
      },
      (text) => reported.push(text),
    )
  }
})

test('files attached in quick add are appended to an ordinary note and reported once', async () => {
  const reported: string[] = []
  await withEditor(
    'Buy milk\n',
    async (editor) => {
      expect(guardedCommand(() => editor.appendImages([{ src: 'a.png', alt: 'a' }]))).toBe(true)
      expect(editor.snapshot().text).toBe('Buy milk\n\n![a](a.png)\n')
      await Promise.resolve()
      expect(reported).toEqual(['Buy milk\n\n![a](a.png)\n'])
    },
    (text) => reported.push(text),
  )
})

test('files attached in quick add are appended after trailing blank lines, which may collapse', async () => {
  for (const source of ['Hello\n\n\n', 'Hello\n\n', 'Hello  \n\n\n\n', '# Title\n\ntext\n\n\n\n']) {
    await withEditor(source, (editor) => {
      expect(guardedCommand(() => editor.appendImages([{ src: 'a.png', alt: 'a' }]))).toBe(true)
      const text = editor.snapshot().text
      expect(text.startsWith(source.trimEnd())).toBe(true)
      expect(text).toContain('![a](a.png)')
      expect(text.replace(/\s+$/, '').endsWith('![a](a.png)')).toBe(true)
    })
  }
})

test('appended files are taken in formatted editing only, and an empty list changes nothing', async () => {
  await withEditor('Pack\n', (editor) => {
    const engine = (editor as unknown as { engine: import('@aicayzer/inkkit').InkKitEditor }).engine
    expect(engine.commandState().commands.appendImages).toBe(true)
    engine.setEditingMode('source', 1)
    expect(engine.commandState().commands.appendImages).toBe(false)
    expect(editor.appendImages([{ src: 'a.png', alt: 'a' }])).toBe(false)
    expect(editor.appendImages([])).toBe(false)
  })
})

test('files attached in quick add wait while the note is edited as source', async () => {
  await withEditor('Pack\n', (editor) => {
    const engine = (editor as unknown as { engine: import('@aicayzer/inkkit').InkKitEditor }).engine
    engine.setEditingMode('source', 1)
    expect(editor.appendImages([{ src: 'a.png', alt: 'a' }])).toBe(false)
    expect(editor.markdown()).toBeNull()
    engine.setEditingMode('formatted', 1)
    expect(editor.appendImages([{ src: 'a.png', alt: 'a' }])).toBe(true)
    expect(editor.markdown()).toBe('Pack\n\n![a](a.png)\n')
  })
})

test('a refused edit stays out of the note and reaches the host, from a command or from a shortcut', async () => {
  const posted: unknown[] = []
  window.webkit = { messageHandlers: { host: { postMessage: (message) => posted.push(message) } } }
  try {
    await withEditor('A <!--note--> B\n', (editor) => {
      // A code block cannot hold the hidden comment, so Inkkit refuses the conversion.
      expect(guardedCommand(() => editor.format('codeBlock'))).toMatchObject({
        commandError: 'preservation',
      })
      expect(editor.snapshot().text).toBe('A <!--note--> B\n')
      expect(posted).toMatchObject([{ type: 'error' }])
      posted.length = 0

      editor.setKeymap({ 'Mod-Alt-c': ['codeBlock'] })
      document.querySelector('.ProseMirror')!.dispatchEvent(
        new KeyboardEvent('keydown', {
          key: 'c',
          metaKey: true,
          altKey: true,
          bubbles: true,
          cancelable: true,
        }),
      )
      expect(editor.snapshot().text).toBe('A <!--note--> B\n')
      expect(posted).toMatchObject([{ type: 'error' }])
    })
  } finally {
    delete window.webkit
  }
})

test('a Link to Note the app fails to answer reports an error to the host and leaves the line as typed', async () => {
  const posted: unknown[] = []
  Object.defineProperty(window, 'webkit', {
    configurable: true,
    value: {
      messageHandlers: {
        host: { postMessage: (message: unknown) => posted.push(message) },
        notes: { postMessage: () => Promise.reject(new Error('The app went away.')) },
      },
    },
  })
  try {
    await withEditor('', async (editor) => {
      const engine = (editor as unknown as { engine: import('@aicayzer/inkkit').InkKitEditor })
        .engine
      engine.insertText('/', 1)
      engine.insertText('link to', 1)
      expect(engine.keyDown({ key: 'Enter' }, 1)).toBe(true)
      await new Promise((done) => setTimeout(done, 0))
      expect(posted).toMatchObject([{ type: 'error' }])
      expect(editor.snapshot().text).toBe('/link to\n')
    })
  } finally {
    delete window.webkit
  }
})

test('load takes the focus off the text and focus after it restores it, with CRLF kept', async () =>
  withEditor('One\r\nTwo\r\n', (editor) => {
    editor.focus()
    expect(document.activeElement?.matches('.ProseMirror')).toBe(true)
    editor.load('Three\r\n\r\nFour\r\n', 2)
    expect(document.activeElement?.matches('.ProseMirror')).toBe(false)
    editor.focus()
    expect(document.activeElement?.matches('.ProseMirror')).toBe(true)
    expect(editor.markdown()).toBeNull()
    editor.format('heading', 1)
    expect(editor.snapshot().text).toBe('Three\r\n\r\n# Four\r\n')
    editor.undo()
    expect(editor.snapshot().text).toBe('Three\r\n\r\nFour\r\n')
    editor.reload('Five\r\n', 3, false)
    expect(guardedCommand(() => editor.format('bold'))).toMatchObject({
      commandError: 'read-only',
    })
    expect(editor.snapshot().text).toBe('Five\r\n')
  }))

test("the page asks the app's notes and falls back to nothing when it cannot", async () => {
  const requests: unknown[] = []
  const answer = { current: undefined as unknown }
  Object.defineProperty(window, 'webkit', {
    configurable: true,
    value: {
      messageHandlers: {
        notes: {
          postMessage: async (request: unknown) => {
            requests.push(request)
            return answer.current
          },
        },
      },
    },
  })
  try {
    answer.current = ['Garden ideas', 7, 'Bike service']
    expect(await suggestNotes('g', 'note')).toEqual(['Garden ideas', 'Bike service'])
    answer.current = null
    expect(await suggestNotes('g', 'note')).toEqual([])
    answer.current = '[[Garden ideas]]'
    expect(await pickNote('note')).toBe('[[Garden ideas]]')
    answer.current = null
    expect(await pickNote('note')).toBeUndefined()
    expect(requests).toEqual([
      { type: 'suggest', query: 'g', item: 'note' },
      { type: 'suggest', query: 'g', item: 'note' },
      { type: 'pick', item: 'note' },
      { type: 'pick', item: 'note' },
    ])
    delete (window as { webkit?: unknown }).webkit
    expect(await suggestNotes('g', 'note')).toEqual([])
    expect(await pickNote('note')).toBeUndefined()
  } finally {
    delete (window as { webkit?: unknown }).webkit
  }
})

test('a link by identity with an escaped title shows the title and is not rewritten', async () => {
  const identity = '22222222-2222-4222-8222-222222222222'
  const labels = ['A|B', 'A#B', 'A]B', '[Draft]', 'back\\slash', 'Café 日本語']
  const escape = (label: string) => label.replace(/[\\[\]|#]/g, (c) => '\\' + c)
  const source = labels.map((label) => `See [[${identity}|${escape(label)}]]\n`).join('\n')
  await withEditor(source, async (editor) => {
    expect(editor.markdown()).toBeNull()
    expect(editor.snapshot().text).toBe(source)
    const shown = document.querySelector('.ProseMirror')!.textContent!
    for (const label of labels) expect(shown).toContain('See ' + label)
    expect(shown).not.toContain(identity)
  })
})

test('a note link typed in double brackets becomes a link and is saved as typed', async () => {
  const identity = '22222222-2222-4222-8222-222222222222'
  const links = ['[[Garden ideas]]', `[[${identity}|Garden ideas]]`, '[[Garden ideas#Soil|soil]]']
  for (const link of links)
    await withEditor('See\n', (editor) => {
      const engine = (editor as unknown as { engine: import('@aicayzer/inkkit').InkKitEditor })
        .engine
      const text = engine.textSnapshot(1)
      engine.selectTextRange({
        snapshotId: text.snapshotId,
        from: text.text.length,
        to: text.text.length,
      })
      for (const character of link) engine.insertText(character, 1)
      expect(document.querySelectorAll('.inkkit-wiki-link')).toHaveLength(1)
      expect(editor.snapshot().text).toBe(`See${link}\n`)
    })
})

test('the caret from quick add lands after the same text the person typed before it', async () => {
  expect(caretOffset('Buy milk', 'Buy milk and eggs\n')).toBe(8)
  expect(caretOffset('# Plan\n\nFirst **step', 'Plan\nFirst step done\n')).toBe(15)
  expect(caretOffset('- one\n- tw', 'one\ntwo\n')).toBe(6)
  expect(caretOffset('', 'Text\n')).toBe(0)
})

test('the caret from quick add passes over the parts of a link the page does not show', async () => {
  // Each readable text is what Inkkit shows for the source before it.
  expect(caretOffset('[link](https://e.com)', 'link one two three\n')).toBe(4)
  expect(caretOffset('[link](https://e.com) one', 'link one two three\n')).toBe(8)
  expect(caretOffset('[link](https://e.c', 'link one two three\n')).toBe(4)
  expect(caretOffset('[ref][1] z', 'ref z\n')).toBe(5)
  expect(caretOffset('See [[Plan|the plan]]', 'See the plan today\n')).toBe(12)
  expect(caretOffset('See [[Plan|the pl', 'See the plan today\n')).toBe(10)
  expect(caretOffset('[[Plan#Goals]] z', 'Plan#Goals z\n')).toBe(12)
  expect(caretOffset('![photo](a.png) after', 'photo after\n')).toBe(11)
  expect(caretOffset('![photo|400](a.png) after', 'photo after\n')).toBe(11)
  expect(caretOffset('x ![[img.png|400]] after', 'x img.png after\n')).toBe(15)
})

test('the caret from quick add is placed in the page', async () => {
  await withEditor('Buy milk and eggs\n', (editor) => {
    editor.focusText('Buy milk')
    const engine = (editor as unknown as { engine: import('@aicayzer/inkkit').InkKitEditor }).engine
    expect(engine.textSnapshot(1).selection).toMatchObject({ from: 8, to: 8 })
    editor.focusText(null)
    expect(engine.textSnapshot(1).selection).toMatchObject({ from: 17, to: 17 })
  })
})
