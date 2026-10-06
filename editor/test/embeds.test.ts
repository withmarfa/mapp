import { afterEach, expect, test } from 'vitest'
import { editorViewCtx } from '@milkdown/kit/core'
import type { Ctx } from '@milkdown/kit/ctx'
import type { Node as ProseNode } from '@milkdown/kit/prose/model'
import { TextSelection } from '@milkdown/kit/prose/state'
import type { EditorMessage, EmbedRequest, EmbeddedFile } from '../src/bridge'
import { NoteEditor } from '../src/editor'
import { embedAt, pathRequest, setItem } from '../src/embeds'
import { namesFile, readNamed, withWidth } from '../src/wikiembeds'
import { roundTrip, withEditor } from './harness'

function nodesOf(doc: ProseNode, name: string): ProseNode[] {
  const found: ProseNode[] = []
  doc.descendants((node) => {
    if (node.type.name === name) found.push(node)
  })
  return found
}

const embedForms = [
  '![[Photo.png]]',
  '![[Photo.png|400]]',
  '![[Photo.png|400x300]]',
  '![[Photo.png| 400 ]]',
  '![[Plan.pdf#page=2]]',
  '![[Plan.pdf#page=2|600]]',
  '![[Attachments/Clip.mp3]]',
  '![[./Clip.mp3]]',
  '![[../Attachments/Walkthrough.mov]]',
  '![[/Attachments/Walkthrough.mov]]',
  '![[Budget sheet 2026.xlsx]]',
  '![[Café.heic]]',
  '![[odd]name.zip]]',
]

for (const form of embedForms) {
  test(`${form} is an embed and is written back unchanged`, async () => {
    const markdown = `Before ${form} after\n`
    expect(await roundTrip(markdown)).toBe(markdown)
    await withEditor(markdown, (editor) => {
      const embeds = nodesOf(editor.ctx.get(editorViewCtx).state.doc, 'embed')
      expect(embeds.map((node) => node.attrs.raw)).toEqual([form])
    })
  })
}

const pathForms = [
  '![](Photo.png)',
  '![A photo|320](../Attachments/Photo%201.png)',
  '![](<Attachments/Budget sheet.xlsx>)',
  '![Plan](Plan.pdf#page=2 "The plan")',
  '![](/Attachments/Clip.mp3)',
]

for (const form of pathForms) {
  test(`${form} is written back unchanged`, async () => {
    const markdown = `Before ${form} after\n`
    expect(await roundTrip(markdown)).toBe(markdown)
  })
}

const textForms = [
  '![[A note]]',
  '![[A note.md]]',
  '![[Notes.markdown]]',
  '![[Notes.txt]]',
  '![[Dr. Smith]]',
  '![[Minutes 2026.10.06]]',
  '![[A note#Heading|shown]]',
  '[[A link]]',
  '[[A link|shown]]',
  '[[A link#Heading]]',
]

for (const form of textForms) {
  test(`${form} stays text and is written back unchanged`, async () => {
    const markdown = `Before ${form} after\n`
    expect(await roundTrip(markdown)).toBe(markdown)
    await withEditor(markdown, (editor) => {
      const doc = editor.ctx.get(editorViewCtx).state.doc
      expect(nodesOf(doc, 'embed')).toEqual([])
      expect(doc.textContent).toBe(`Before ${form} after`)
    })
  })
}

test('an embed in code stays code', async () => {
  const markdown = 'See `![[Photo.png]]` here\n\n```\n![[Photo.png]]\n```\n\n    ![[Photo.png]]\n'
  await withEditor(markdown, (editor) => {
    expect(nodesOf(editor.ctx.get(editorViewCtx).state.doc, 'embed')).toEqual([])
  })
  expect(await roundTrip('See `![[Photo.png]]` here\n')).toBe('See `![[Photo.png]]` here\n')
})

test('an embed split across lines, or never closed, is text', async () => {
  for (const markdown of ['![[Photo\n.png]]\n', '![[Photo.png\n']) {
    await withEditor(markdown, (editor) => {
      expect(nodesOf(editor.ctx.get(editorViewCtx).state.doc, 'embed')).toEqual([])
    })
  }
})

test('an embed in a table keeps the escaped pipe a cell needs', async () => {
  const markdown = '| Picture |\n| --- |\n| ![[Photo.png\\|200]] and [[Plan\\|shown]] |\n'
  expect(await roundTrip(markdown)).toBe(markdown)
  await withEditor(markdown, (editor) => {
    const [embed] = nodesOf(editor.ctx.get(editorViewCtx).state.doc, 'embed')
    expect(readNamed(String(embed?.attrs.raw))).toEqual({
      name: 'Photo.png',
      fragment: '',
      width: 200,
    })
  })
})

test('a link with characters markdown reads is escaped as before', async () => {
  expect(await roundTrip('A \\[\\[*x*]] here\n')).toBe('A \\[\\[*x*]] here\n')
})

test('an embed is read as Marfa reads its name, size and fragment', () => {
  expect(readNamed('![[Attachments/Plan.pdf#page=2|600x400]]')).toEqual({
    name: 'Attachments/Plan.pdf',
    fragment: '#page=2',
    width: 600,
  })
  expect(readNamed('![[ Clip.mp3 ]]')).toEqual({ name: 'Clip.mp3', fragment: '', width: null })
  expect(namesFile('Clip.mp3')).toBe(true)
  expect(namesFile('Data.x7')).toBe(true)
  expect(namesFile('A note')).toBe(false)
  expect(namesFile('A note.md')).toBe(false)
  expect(namesFile('Readme.TXT')).toBe(false)
  expect(namesFile('v1.2')).toBe(false)
})

test('a new width replaces the one an embed had, or is added', () => {
  expect(withWidth('![[Photo.png]]', 250)).toBe('![[Photo.png|250]]')
  expect(withWidth('![[Photo.png|400x300]]', 250)).toBe('![[Photo.png|250]]')
  expect(withWidth('![[Photo.png\\|400]]', 250)).toBe('![[Photo.png\\|250]]')
  expect(withWidth('![[Plan.pdf#page=2]]', 250)).toBe('![[Plan.pdf#page=2|250]]')
})

test('only a path to a file in the folder is asked for', () => {
  expect(pathRequest('Attachments/Photo%201.png')).toBe('Attachments/Photo%201.png')
  expect(pathRequest('../Plan.pdf#page=2')).toBe('../Plan.pdf#page=2')
  expect(pathRequest('Other%20note.md')).toBe(null)
  expect(pathRequest('Notes.txt?x=1')).toBe(null)
  expect(pathRequest('https://example.com/a.png')).toBe(null)
  expect(pathRequest('//example.com/a.png')).toBe(null)
  expect(pathRequest('#heading')).toBe(null)
  expect(pathRequest('')).toBe(null)
})

// MARK: The page, with an app that answers

const files: Record<string, Omit<EmbeddedFile, 'url' | 'icon'>> = {
  'Photo.png': { kind: 'image', name: 'Photo.png', detail: '2 KB' },
  'Clip.mp3': { kind: 'audio', name: 'Clip.mp3', detail: '1 MB' },
  'Walkthrough.mov': { kind: 'video', name: 'Walkthrough.mov', detail: '9 MB' },
  'Plan.pdf': { kind: 'pdf', name: 'Plan.pdf', detail: '80 KB' },
  'Budget.xlsx': { kind: 'file', name: 'Budget.xlsx', detail: '12 KB' },
}

let asked: EmbedRequest[] = []
let posted: EditorMessage[] = []
const webkit = window.webkit

function answer(): void {
  asked = []
  posted = []
  window.webkit = {
    messageHandlers: {
      host: { postMessage: (message) => posted.push(message) },
      embeds: {
        postMessage: async (request) => {
          asked.push(request)
          const key = 'name' in request ? request.name : request.path
          const file = files[key.slice(key.lastIndexOf('/') + 1)]
          return file
            ? { ...file, url: `mapp-embed://file/${key}`, icon: 'mapp-embed://icon/x' }
            : null
        },
      },
    },
  }
}

afterEach(() => {
  window.webkit = webkit
})

async function withPage<T>(markdown: string, run: (dom: HTMLElement, editor: NoteEditor) => T) {
  answer()
  setItem('item-1')
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
  await new Promise((resolve) => setTimeout(resolve, 0))
  try {
    return await run(root, editor)
  } finally {
    root.remove()
  }
}

test('each kind of file shows as what it is', async () =>
  withPage(
    '![[Photo.png|300]] ![[Clip.mp3]] ![[Walkthrough.mov]] ![[Plan.pdf#page=2]] ![](Budget.xlsx) ![[Gone.zip]] ![](Other.md)\n',
    (dom, editor) => {
      const image = dom.querySelector('.image img') as HTMLImageElement
      expect(image.src).toBe('mapp-embed://file/Photo.png')
      expect(image.style.width).toBe('300px')
      expect((dom.querySelector('.embed-audio audio') as HTMLAudioElement).controls).toBe(true)
      expect((dom.querySelector('.embed-video video') as HTMLVideoElement).src).toBe(
        'mapp-embed://file/Walkthrough.mov',
      )
      expect((dom.querySelector('.embed-pdf iframe') as HTMLIFrameElement).src).toBe(
        'mapp-embed://file/Plan.pdf#page=2',
      )
      const card = dom.querySelector('.embed-card') as HTMLElement
      expect(card.querySelector('.embed-name')?.textContent).toBe('Budget.xlsx')
      expect(card.querySelector('.embed-detail')?.textContent).toBe('12 KB')
      expect([...dom.querySelectorAll('.image-absent')].map((span) => span.textContent)).toEqual([
        'Gone.zip',
        'Other.md',
      ])
      // A note embedded by path is never asked for.
      expect(asked.map((request) => ('name' in request ? request.name : request.path))).toEqual([
        'Photo.png',
        'Clip.mp3',
        'Walkthrough.mov',
        'Plan.pdf',
        'Budget.xlsx',
        'Gone.zip',
      ])
      expect(asked.every((request) => request.item === 'item-1')).toBe(true)
      expect(editor.markdown()).toBe(null)
    },
  ))

test('a card opens its file, and the context menu over an embed names it', async () =>
  withPage('A sheet: ![](Budget.xlsx)\n', (dom) => {
    const card = dom.querySelector('.embed-card') as HTMLElement
    card.click()
    expect(posted).toContainEqual({
      type: 'openEmbed',
      embed: { item: 'item-1', path: 'Budget.xlsx' },
    })
    expect(embedAt(card.querySelector('.embed-name'))).toEqual({
      item: 'item-1',
      path: 'Budget.xlsx',
    })
    expect(embedAt(dom.querySelector('p'))).toBe(null)
  }))

test('typing beside an embed keeps the embed as written', async () =>
  withPage(
    'Listen ![[Clip.mp3]] and ![[Photo.png|400]], then [[A link]] and ![[A note]].\n',
    (dom, editor) => {
      const ctx = (editor as unknown as { editor: { ctx: Ctx } }).editor.ctx
      const view = ctx.get(editorViewCtx)
      view.dispatch(view.state.tr.setSelection(TextSelection.create(view.state.doc, 8)))
      view.dispatch(view.state.tr.insertText('now '))
      expect(editor.markdown()).toBe(
        'Listen now ![[Clip.mp3]] and ![[Photo.png|400]], then [[A link]] and ![[A note]].\n',
      )
      expect(dom.querySelector('.embed-audio audio')).not.toBe(null)
    },
  ))
