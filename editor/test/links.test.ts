import { afterEach, beforeEach, expect, test, vi } from 'vitest'
import { InkKitEditor } from '@aicayzer/inkkit'
import { NoteEditor, wikiSuggest } from '../src/editor'
import type { EditorMessage, NoteRequest } from '../src/bridge'

const identity = '22222222-2222-4222-8222-222222222222'

interface Page {
  hosted: EditorMessage[]
  asked: NoteRequest[]
  /** Which links, as `target` or `target|alias`, the app says no note answers to. */
  missing: Set<string>
  /** The type icon key and tone the app says the note a link names has, by the link's inner text. */
  types: Map<string, { icon?: string; tone: string }>
  /** The bytes the app draws for each icon key. */
  drawn: Record<string, string>
  /** What each reply to a `resolve` carried in `icons`, to see what it sent. */
  sent: string[][]
  /** Set to make the app not answer. */
  silent: boolean
}
let page: Page

beforeEach(() => {
  page = {
    hosted: [],
    asked: [],
    missing: new Set(),
    types: new Map(),
    drawn: {},
    sent: [],
    silent: false,
  }
  Object.defineProperty(window, 'webkit', {
    configurable: true,
    value: {
      messageHandlers: {
        host: { postMessage: (message: EditorMessage) => page.hosted.push(message) },
        notes: {
          postMessage: async (request: NoteRequest) => {
            page.asked.push(request)
            if (page.silent) return null
            return request.type === 'resolve' ? answer(request) : null
          },
        },
      },
    },
  })
})
/** The app's answer to a `resolve`: each link's state and type, and the bytes of each distinct icon once. */
function answer(request: Extract<NoteRequest, { type: 'resolve' }>) {
  const icons: Record<string, string> = {}
  const links = request.links.map((link) => {
    const inner = link.raw.slice(2, -2)
    if (page.missing.has(inner)) return { missing: true }
    const type = page.types.get(inner)
    if (!type) return { missing: false }
    if (type.icon !== undefined) icons[type.icon] = page.drawn[type.icon] ?? ''
    return { missing: false, ...type }
  })
  page.sent.push(Object.keys(icons))
  return { links, icons }
}
afterEach(() => {
  delete (window as { webkit?: unknown }).webkit
})

async function withEditor(
  source: string,
  run: (editor: NoteEditor, root: HTMLElement) => Promise<void>,
  editable = true,
) {
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
  editor.load(source, 1, editable)
  try {
    await run(editor, root)
  } finally {
    await editor.destroy()
    root.remove()
  }
}
const settle = () => new Promise((done) => setTimeout(done, 0))
const links = (root: HTMLElement) => [...root.querySelectorAll<HTMLElement>('.inkkit-wiki-link')]
const mark = 'data:image/png;base64,AAAA'
const note = { icon: 'type:lucide:sticky-note', tone: 'yellow' }
const person = { icon: 'type:lucide:user', tone: 'purple' }
/** What Inkkit drew before a link: its icon's mask and color, and its tint, as set on the link. */
const drawn = (link: HTMLElement) => {
  const lead = link.querySelector<HTMLElement>('.inkkit-wiki-link-lead')
  return {
    icon: lead?.style.getPropertyValue('--_inkkit-wiki-icon') ?? '',
    color: lead?.style.getPropertyValue('--_inkkit-wiki-icon-color') ?? '',
    tint: link.style.getPropertyValue('--_inkkit-wiki-link-tint'),
  }
}
const marks = (root: HTMLElement) => links(root).map((link) => link.dataset.missing ?? null)
const modClick = (link: HTMLElement) =>
  link.dispatchEvent(new MouseEvent('click', { metaKey: true, button: 0, bubbles: true }))

test('an alias repeating the name keeps its own binding and opening request', () =>
  withEditor('[[Plan]] and [[Plan|Plan]]\n', async (editor, root) => {
    page.missing.add('Plan|Plan')
    await settle()
    expect(marks(root)).toEqual([null, 'true'])
    const request = page.asked.find((request) => request.type === 'resolve')
    expect(request?.type === 'resolve' && request.links.map((link) => link.raw)).toEqual([
      '[[Plan]]',
      '[[Plan|Plan]]',
    ])
    page.hosted.length = 0
    modClick(links(root)[1]!)
    expect(page.hosted).toEqual([
      { type: 'openNote', item: 'note', raw: '[[Plan|Plan]]', target: 'Plan' },
    ])
    expect(editor.snapshot().text).toBe('[[Plan]] and [[Plan|Plan]]\n')
  }))

test('a backslash in a link is part of its text, as in Marfa, and the link reaches the host as authored', () =>
  withEditor('\\[[x]] and [[Plan\\]] and [[A\\|B]]\n', async (editor, root) => {
    await settle()
    const request = page.asked.find((request) => request.type === 'resolve')
    expect(request?.type === 'resolve' && request.links).toEqual([
      { raw: '[[x]]', target: 'x' },
      { raw: '[[Plan\\]]', target: 'Plan\\' },
      { raw: '[[A\\|B]]', target: 'A\\', alias: 'B' },
    ])
    page.hosted.length = 0
    modClick(links(root)[1]!)
    expect(page.hosted[0]).toMatchObject({ type: 'openNote', raw: '[[Plan\\]]', target: 'Plan\\' })
    expect(editor.snapshot().text).toBe('\\[[x]] and [[Plan\\]] and [[A\\|B]]\n')
  }))

const forms: [string, { target: string; heading?: string; alias?: string }][] = [
  ['[[Plan]]', { target: 'Plan' }],
  ['[[Plan|alias]]', { target: 'Plan', alias: 'alias' }],
  ['[[Plan#Heading]]', { target: 'Plan', heading: 'Heading' }],
  ['[[Plan#Heading|soil]]', { target: 'Plan', heading: 'Heading', alias: 'soil' }],
  [`[[${identity}]]`, { target: identity }],
  [`[[${identity}|Plan]]`, { target: identity, alias: 'Plan' }],
]
for (const [link, named] of forms) {
  test(`command-clicking ${link} asks the app to open the note it names`, () =>
    withEditor(`See ${link}\n`, async (_editor, root) => {
      await settle()
      page.hosted.length = 0
      modClick(links(root)[0]!)
      expect(page.hosted).toEqual([{ type: 'openNote', item: 'note', raw: link, ...named }])
    }))
}

test('two links with one name but different spellings are told apart', () =>
  withEditor('[[Plan]] and [[Plan|new]]\n', async (_editor, root) => {
    page.missing.add('Plan|new')
    await settle()
    expect(page.asked).toEqual([
      {
        type: 'resolve',
        item: 'note',
        links: [
          { raw: '[[Plan]]', target: 'Plan' },
          { raw: '[[Plan|new]]', target: 'Plan', alias: 'new' },
        ],
      },
    ])
    expect(marks(root)).toEqual([null, 'true'])
    page.hosted.length = 0
    modClick(links(root)[1]!)
    expect(page.hosted).toEqual([
      { type: 'openNote', item: 'note', raw: '[[Plan|new]]', target: 'Plan', alias: 'new' },
    ])
  }))

test('a plain click on a note link opens nothing', () =>
  withEditor('See [[Plan]]\n', async (_editor, root) => {
    await settle()
    links(root)[0]!.dispatchEvent(new MouseEvent('click', { button: 0, bubbles: true }))
    expect(page.hosted.filter((m) => m.type === 'openNote')).toEqual([])
  }))

test('a link to a heading of its own note is scrolled to in the page and asks the app for nothing', () =>
  withEditor('# Soil\n\nSee [[#Soil]]\n', async (editor, root) => {
    await settle()
    const reveal = vi.spyOn(editor, 'revealHeading')
    modClick(links(root)[0]!)
    expect(reveal).toHaveBeenCalledWith('Soil')
    expect(page.hosted.filter((m) => m.type === 'openNote')).toEqual([])
  }))

test('revealing a heading finds it by its text, ignoring case, and answers whether it was there', () =>
  withEditor('# Soil\n\n## Light and Water\n\nText\n', async (editor) => {
    expect(editor.revealHeading('light and water')).toBe(true)
    expect(editor.revealHeading('  Soil ')).toBe(true)
    expect(editor.revealHeading('Missing heading')).toBe(false)
  }))

test('links that name no note are marked missing, asking the app once for every name', () =>
  withEditor('[[Here]] and [[Gone]] and [[Here]] again\n', async (_editor, root) => {
    page.missing.add('Gone')
    await settle()
    expect(page.asked).toEqual([
      {
        type: 'resolve',
        item: 'note',
        links: [
          { raw: '[[Here]]', target: 'Here' },
          { raw: '[[Gone]]', target: 'Gone' },
        ],
      },
    ])
    expect(marks(root)).toEqual([null, 'true', null])
  }))

test('a link that names a note by identity is asked about by that identity', () =>
  withEditor(`[[${identity}|Plan]]\n`, async (_editor, root) => {
    page.missing.add(`${identity}|Plan`)
    await settle()
    expect(page.asked).toEqual([
      {
        type: 'resolve',
        item: 'note',
        links: [{ raw: `[[${identity}|Plan]]`, target: identity, alias: 'Plan' }],
      },
    ])
    expect(marks(root)).toEqual(['true'])
  }))

test('a link is assumed to name a note until the app says otherwise, and when it cannot', () =>
  withEditor('[[Here]]\n', async (_editor, root) => {
    page.silent = true
    page.missing.add('Here')
    // Nothing answered yet, as in the first moment after a note is shown.
    expect(marks(root)).toEqual([null])
    await settle()
    expect(marks(root)).toEqual([null])
  }))

test('a library change asks again and a link becomes live or missing without the note being reopened', () =>
  withEditor('[[Here]] and [[Soon]]\n', async (editor, root) => {
    page.missing.add('Soon')
    await settle()
    expect(marks(root)).toEqual([null, 'true'])
    const before = editor.snapshot().text

    // A note named Soon is made and the one named Here is deleted.
    page.missing.delete('Soon')
    page.missing.add('Here')
    page.asked.length = 0
    editor.linksChanged()
    await settle()
    expect(page.asked).toEqual([
      {
        type: 'resolve',
        item: 'note',
        links: [
          { raw: '[[Here]]', target: 'Here' },
          { raw: '[[Soon]]', target: 'Soon' },
        ],
      },
    ])
    expect(marks(root)).toEqual(['true', null])
    expect(editor.snapshot().text).toBe(before)
    expect(editor.markdown()).toBeNull()
  }))

test('only the links whose answer changed are drawn again, by the notes they name', () =>
  withEditor('[[Here]] and [[Soon]] and [[Else]]\n', async (editor) => {
    const refresh = vi.spyOn(InkKitEditor.prototype, 'refreshReferences')
    try {
      page.missing.add('Soon')
      await settle()
      expect(refresh).toHaveBeenCalledTimes(1)
      expect(refresh).toHaveBeenLastCalledWith(['Soon'])
      // A change in the library that answers the same draws nothing.
      editor.linksChanged()
      await settle()
      expect(refresh).toHaveBeenCalledTimes(1)
      page.missing.delete('Soon')
      page.missing.add('Else')
      editor.linksChanged()
      await settle()
      expect(refresh).toHaveBeenCalledTimes(2)
      expect(new Set(refresh.mock.lastCall![0])).toEqual(new Set(['Soon', 'Else']))
    } finally {
      refresh.mockRestore()
    }
  }))

test('links of a note shown read-only are drawn missing, and again when the library changes', () =>
  withEditor(
    '[[Here]] and [[Soon]]\n',
    async (editor, root) => {
      page.missing.add('Soon')
      await settle()
      expect(marks(root)).toEqual([null, 'true'])
      page.missing.delete('Soon')
      page.missing.add('Here')
      editor.linksChanged()
      await settle()
      expect(marks(root)).toEqual(['true', null])
      expect(editor.markdown()).toBeNull()
    },
    false,
  ))

test('links are drawn again while the person composes, without ending the composition', () =>
  withEditor('[[Here]] and [[Soon]]\n', async (editor, root) => {
    await settle()
    editor.focus()
    const surface = root.querySelector('.ProseMirror')!
    surface.dispatchEvent(new CompositionEvent('compositionstart', { bubbles: true }))
    expect(() => editor.setEditingMode('source')).toThrowError(/composition|compos/i)
    page.missing.add('Soon')
    editor.linksChanged()
    await settle()
    expect(marks(root)).toEqual([null, 'true'])
    surface.dispatchEvent(new CompositionEvent('compositionend', { bubbles: true, data: '' }))
    expect(editor.markdown()).toBeNull()
  }))

test('a library change that alters no answer leaves the links as they are', () =>
  withEditor('[[Here]]\n', async (editor, root) => {
    await settle()
    const link = links(root)[0]!
    editor.linksChanged()
    await settle()
    expect(links(root)[0]).toBe(link)
    expect(page.asked).toHaveLength(2)
  }))

test('answers are kept for the note on the page only', () =>
  withEditor('[[Here]]\n', async (editor) => {
    await settle()
    editor.setItem('other')
    editor.load('[[Here]]\n', 2)
    page.asked.length = 0
    await settle()
    expect(page.asked).toEqual([
      { type: 'resolve', item: 'other', links: [{ raw: '[[Here]]', target: 'Here' }] },
    ])
  }))

test('names queued for a note that is replaced before they are sent are never sent', () =>
  withEditor('[[Early]]\n', async (editor) => {
    // The links of the first note were queued while it rendered; the next note replaces it in the same task.
    editor.setItem('other')
    editor.load('[[Late]]\n', 2)
    await settle()
    expect(page.asked).toEqual([
      { type: 'resolve', item: 'other', links: [{ raw: '[[Late]]', target: 'Late' }] },
    ])
  }))

test('an answer that arrives after the note was replaced is dropped', () =>
  withEditor('[[Early]]\n', async (editor, root) => {
    const releases: ((answer: unknown) => void)[] = []
    window.webkit!.messageHandlers!.notes!.postMessage = ((request: NoteRequest) => {
      page.asked.push(request)
      return new Promise((done) => releases.push(done))
    }) as never
    editor.setItem('other')
    editor.load('[[Early]]\n', 2)
    await settle()
    expect(releases).toHaveLength(1)
    // The first note's request was sent before the handler was replaced; its answer is for a note gone.
    editor.setItem('third')
    editor.load('[[Early]]\n', 3)
    await settle()
    expect(releases).toHaveLength(2)
    releases[0]!({ links: [{ missing: true }], icons: {} })
    await settle()
    expect(marks(root)).toEqual([null])
    releases[1]!({ links: [{ missing: true }], icons: {} })
    await settle()
    expect(marks(root)).toEqual(['true'])
  }))

test('a suggestion request the person has typed past sends nothing', async () => {
  const aborted = new AbortController()
  aborted.abort()
  const context = { documentId: 'note', generation: 1, operationId: 'x', signal: aborted.signal }
  expect(await wikiSuggest('Pl', context)).toEqual([])
  expect(page.asked).toEqual([])
  await wikiSuggest('Pl', { ...context, signal: new AbortController().signal })
  expect(page.asked).toEqual([{ type: 'suggest', query: 'Pl', item: 'note' }])
})

// What a link looks like follows the type of the note it names, which only the app knows.

test('a link to a note of a type with an icon is drawn with that icon in the type tone, and tinted by it', () =>
  withEditor('[[Plan]] and [[Ana]] and [[Bare]]\n', async (_editor, root) => {
    page.drawn[note.icon] = mark
    page.drawn[person.icon] = mark
    page.types.set('Plan', note)
    page.types.set('Ana', person)
    await settle()
    const [plan, ana, bare] = links(root).map(drawn)
    expect(plan).toEqual({
      icon: `url("${mark}")`,
      color: 'var(--link-icon-yellow, currentcolor)',
      tint: 'var(--link-tint-yellow, transparent)',
    })
    expect(ana?.color).toBe('var(--link-icon-purple, currentcolor)')
    expect(ana?.tint).toBe('var(--link-tint-purple, transparent)')
    // A link the app gave no type is drawn as before.
    expect(bare).toEqual({ icon: '', color: '', tint: '' })
    expect(marks(root)).toEqual([null, null, null])
  }))

test('the bytes of one icon are sent once however many links name notes of that type', () =>
  withEditor('[[A]] [[B]] [[C]] [[D]]\n', async () => {
    page.drawn[note.icon] = mark
    for (const name of ['A', 'B', 'C', 'D']) page.types.set(name, note)
    await settle()
    expect(page.asked).toHaveLength(1)
    expect(page.sent).toEqual([[note.icon]])
  }))

test('a type with a tone and no icon is tinted and draws no icon', () =>
  withEditor('[[Plain]]\n', async (_editor, root) => {
    page.types.set('Plain', { tone: 'gray' })
    await settle()
    expect(drawn(links(root)[0]!)).toEqual({
      icon: '',
      color: '',
      tint: 'var(--link-tint-gray, transparent)',
    })
  }))

test('a link to a missing note keeps its dashed look and draws no icon or tint', () =>
  withEditor('[[Gone]]\n', async (_editor, root) => {
    page.missing.add('Gone')
    page.types.set('Gone', note)
    page.drawn[note.icon] = mark
    await settle()
    expect(marks(root)).toEqual(['true'])
    expect(drawn(links(root)[0]!)).toEqual({ icon: '', color: '', tint: '' })
  }))

test('a heading link and a link with an alias take the icon of the note they name', () =>
  withEditor('[[Plan#Soil]] and [[Plan|the plan]]\n', async (_editor, root) => {
    page.drawn[note.icon] = mark
    page.types.set('Plan#Soil', note)
    page.types.set('Plan|the plan', note)
    await settle()
    expect(links(root).map((link) => drawn(link).icon)).toEqual([
      `url("${mark}")`,
      `url("${mark}")`,
    ])
  }))

test('links in a heading and in a table cell are drawn with their icon', () =>
  withEditor('# [[Plan]]\n\n| Cell |\n| ---- |\n| [[Plan]] |\n', async (_editor, root) => {
    page.drawn[note.icon] = mark
    page.types.set('Plan', note)
    await settle()
    const inHeading = root.querySelector<HTMLElement>('h1 .inkkit-wiki-link')!
    const inCell = root.querySelector<HTMLElement>('td .inkkit-wiki-link')!
    expect(drawn(inHeading).icon).toBe(`url("${mark}")`)
    expect(drawn(inCell).icon).toBe(`url("${mark}")`)
  }))

test('a link whose note changes type is drawn again, and one whose type is the same is not', () =>
  withEditor('[[Plan]] and [[Other]]\n', async (editor, root) => {
    const refresh = vi.spyOn(InkKitEditor.prototype, 'refreshReferences')
    try {
      page.drawn[note.icon] = mark
      page.drawn[person.icon] = 'data:image/png;base64,BBBB'
      page.types.set('Plan', note)
      page.types.set('Other', note)
      await settle()
      refresh.mockClear()
      editor.linksChanged()
      await settle()
      expect(refresh).not.toHaveBeenCalled()
      // The type of Plan is given another icon and tone; Other keeps its own.
      page.types.set('Plan', person)
      editor.linksChanged()
      await settle()
      expect(refresh).toHaveBeenCalledTimes(1)
      expect(refresh).toHaveBeenLastCalledWith(['Plan'])
      expect(drawn(links(root)[0]!).icon).toBe('url("data:image/png;base64,BBBB")')
      expect(drawn(links(root)[1]!).icon).toBe(`url("${mark}")`)
    } finally {
      refresh.mockRestore()
    }
  }))

test('a type whose icon is drawn differently is drawn again', () =>
  withEditor('[[Plan]]\n', async (editor, root) => {
    page.drawn[note.icon] = mark
    page.types.set('Plan', note)
    await settle()
    page.drawn[note.icon] = 'data:image/png;base64,CCCC'
    editor.linksChanged()
    await settle()
    expect(drawn(links(root)[0]!).icon).toBe('url("data:image/png;base64,CCCC")')
  }))

test('a link whose note becomes missing, or ambiguous, loses its icon', () =>
  withEditor('[[Plan]]\n', async (editor, root) => {
    page.drawn[note.icon] = mark
    page.types.set('Plan', note)
    await settle()
    expect(drawn(links(root)[0]!).icon).toBe(`url("${mark}")`)
    page.types.delete('Plan')
    editor.linksChanged()
    await settle()
    expect(drawn(links(root)[0]!)).toEqual({ icon: '', color: '', tint: '' })
  }))

test('an icon the answer did not send, or a tone that is not a word, is left out and nothing throws', () =>
  withEditor('[[A]] and [[B]]\n', async (editor, root) => {
    window.webkit!.messageHandlers!.notes!.postMessage = (async () => ({
      links: [
        { missing: false, icon: 'type:unsent', tone: 'blue' },
        { missing: false, icon: 'type:x', tone: 'blue); background: red' },
      ],
      icons: { 'type:x': mark },
    })) as never
    editor.linksChanged()
    await settle()
    const [unsent, odd] = links(root).map(drawn)
    expect(unsent).toEqual({ icon: '', color: '', tint: 'var(--link-tint-blue, transparent)' })
    expect(odd).toEqual({ icon: `url("${mark}")`, color: '', tint: '' })
    expect(marks(root)).toEqual([null, null])
  }))

test('an icon that is not an image is refused whole, and its links are drawn as before', () =>
  withEditor('[[A]]\n', async (_editor, root) => {
    page.drawn[note.icon] = 'https://example.com/x.png'
    page.types.set('A', note)
    await settle()
    expect(drawn(links(root)[0]!).icon).toBe('')
  }))

const engineOf = (editor: NoteEditor) => (editor as unknown as { engine: InkKitEditor }).engine

test('drawing an icon changes nothing in the saved text, through an edit, undo and redo', () =>
  withEditor('Intro [[Plan]] and [[Gone]].\n\nSecond\n', async (editor, root) => {
    page.drawn[note.icon] = mark
    page.types.set('Plan', note)
    page.missing.add('Gone')
    await settle()
    const source = 'Intro [[Plan]] and [[Gone]].\n\nSecond\n'
    expect(editor.snapshot().text).toBe(source)
    const engine = engineOf(editor)
    const text = engine.textSnapshot(1)
    const at = text.text.indexOf('Second') + 'Second'.length
    engine.selectTextRange({ snapshotId: text.snapshotId, from: at, to: at })
    engine.insertText('!', 1)
    expect(editor.snapshot().text).toBe(source.replace('Second', 'Second!'))
    editor.undo()
    expect(editor.snapshot().text).toBe(source)
    editor.redo()
    expect(editor.snapshot().text).toBe(source.replace('Second', 'Second!'))
    editor.undo()
    expect(editor.snapshot().text).toBe(source)
    expect(editor.markdown()).toBeNull()
    // Typing next to a link redraws nothing the text keeps.
    expect(drawn(links(root)[0]!).icon).toBe(`url("${mark}")`)
  }))

test('copying text that holds a link carries the link and not its icon', () =>
  withEditor('Intro [[Plan]] outro\n', async (editor, root) => {
    page.drawn[note.icon] = mark
    page.types.set('Plan', note)
    await settle()
    const engine = engineOf(editor)
    const text = engine.textSnapshot(1)
    engine.selectTextRange({ snapshotId: text.snapshotId, from: 0, to: text.text.length })
    const written: Record<string, string> = {}
    const event = new Event('copy', { bubbles: true, cancelable: true })
    Object.defineProperty(event, 'clipboardData', {
      value: { setData: (type: string, data: string) => (written[type] = data), getData: () => '' },
    })
    root.querySelector('.ProseMirror')!.dispatchEvent(event)
    const everything = Object.values(written).join('\n')
    expect(everything).not.toContain('data:image')
    expect(everything).not.toContain('--_inkkit')
    expect(written['text/plain'] ?? '').toContain('Plan')
  }))
