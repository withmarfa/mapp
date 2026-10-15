import { readdirSync, readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { expect, test, vi } from 'vitest'
import { InkKitError } from '@aicayzer/inkkit'
import {
  NoteEditor,
  isPreviewDiagnostic,
  guardedCommand,
  splitLabels,
  type CaretState,
  type FindState,
} from '../src/editor'

async function withEditor(source: string, run: (editor: NoteEditor) => void | Promise<void>) {
  const root = document.createElement('div')
  document.body.append(root)
  const editor = await NoteEditor.mount(root, {
    find() {},
    changed() {},
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

test('note embeds describe unsupported transclusion and open source without changing Markdown', async () =>
  withEditor('![[A note]]\n\n![Section](note.md#part)\n', async (editor) => {
    await new Promise((resolve) => setTimeout(resolve, 20))
    const labels = [...document.querySelectorAll('.inkkit-file-label')].map((e) => e.textContent)
    expect(labels).toContain('Note reference: A note. Open to edit source.')
    expect(labels).toContain('Note reference: Section. Open to edit source.')
    expect(labels.join(' ')).not.toContain('File unavailable')
    const button = document.querySelector<HTMLButtonElement>('.inkkit-file-control')!
    button.click()
    expect(document.querySelector('textarea')).not.toBeNull()
    expect(editor.markdown()).toBeNull()
  }))

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

test("the words the app sends mount InkKit, with the app's own kept out of its labels", async () => {
  const swift = readFileSync(
    resolve(import.meta.dirname, '../../MAPP/Editor/EditorController.swift'),
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
    ['discardChanges', 'itemType', 'propertyRejected', 'status', 'title', 'untitled'].sort(),
  )
  expect(labels.noteReference).toContain('%@')
  expect(Object.keys(labels.editor)).not.toContain('noteReference')
  expect(Object.keys(labels.editor)).not.toContain('untitled')

  const root = document.createElement('div')
  document.body.append(root)
  const editor = await NoteEditor.mount(
    root,
    { find() {}, changed() {}, stateChanged() {}, openLink() {}, copy() {} },
    labels.editor,
    labels.noteReference,
  )
  editor.setItem('note')
  editor.load('![[A note]]\n', 1)
  try {
    await new Promise((resolve) => setTimeout(resolve, 20))
    expect(document.querySelector('.inkkit-file-label')?.textContent).toBe(
      labels.noteReference!.replace('%@', 'A note'),
    )
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

test('the header and the text share one column, which InkKit reads from one token', () => {
  const css = readFileSync(resolve(import.meta.dirname, '../src/style.css'), 'utf8')
  expect(css).toMatch(/body\s*{[^}]*--inkkit-column-inset:/)
  expect(css).toMatch(/#item-header\s*{[^}]*padding:[^;]*var\(--inkkit-column-inset\)/)
  expect(css).not.toMatch(/\.ProseMirror[^{]*{[^}]*padding-inline/)
  for (const old of ['--accent', '--text', '--muted', '--rule', '--code-bg', '--mono'])
    expect(css).not.toMatch(new RegExp(`${old}\\b`))
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

test('a refused edit stays out of the note and reaches the host, from a command or from a shortcut', async () => {
  const posted: unknown[] = []
  window.webkit = { messageHandlers: { host: { postMessage: (message) => posted.push(message) } } }
  try {
    await withEditor('A <!--note--> B\n', (editor) => {
      // A code block cannot hold the hidden comment, so InkKit refuses the conversion.
      expect(guardedCommand(() => editor.format('codeBlock'))).toMatchObject({
        commandError: 'preservation',
      })
      expect(editor.snapshot().text).toBe('A <!--note--> B\n')
      expect(posted).toEqual([])

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
