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
  /** Set to make the app not answer. */
  silent: boolean
}
let page: Page

beforeEach(() => {
  page = { hosted: [], asked: [], missing: new Set(), silent: false }
  Object.defineProperty(window, 'webkit', {
    configurable: true,
    value: {
      messageHandlers: {
        host: { postMessage: (message: EditorMessage) => page.hosted.push(message) },
        notes: {
          postMessage: async (request: NoteRequest) => {
            page.asked.push(request)
            if (page.silent) return null
            return request.type === 'resolve'
              ? request.links.map((l) => page.missing.has(l.raw.slice(2, -2)))
              : null
          },
        },
      },
    },
  })
})
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

test('escaped link separators reach the host exactly as authored', () =>
  withEditor('[[A\\|B]] and [[Plan#A\\#B|alias]]\n', async (editor, root) => {
    await settle()
    const request = page.asked.find((request) => request.type === 'resolve')
    expect(request?.type === 'resolve' && request.links.map((link) => link.raw)).toEqual([
      '[[A\\|B]]',
      '[[Plan#A\\#B|alias]]',
    ])
    page.hosted.length = 0
    modClick(links(root)[0]!)
    expect(page.hosted[0]).toMatchObject({ type: 'openNote', raw: '[[A\\|B]]', target: 'A|B' })
    expect(editor.snapshot().text).toBe('[[A\\|B]] and [[Plan#A\\#B|alias]]\n')
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
    const releases: ((answer: boolean[]) => void)[] = []
    window.webkit!.messageHandlers!.notes!.postMessage = ((request: NoteRequest) => {
      page.asked.push(request)
      return new Promise((done) => releases.push(done as (answer: boolean[]) => void))
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
    releases[0]!([true])
    await settle()
    expect(marks(root)).toEqual([null])
    releases[1]!([true])
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
