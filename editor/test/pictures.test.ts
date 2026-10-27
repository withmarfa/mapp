import { afterEach, beforeEach, expect, test, vi } from 'vitest'
import type { PictureAnswer, PictureRequest } from '../src/bridge'
import { NoteEditor } from '../src/editor'
import { WebPictures } from '../src/pictures'

type Asked = Omit<PictureRequest, 'type'>

/** A stand-in for the app: it answers each question about a picture from `answer`, and records it. */
function app(answer: (request: PictureRequest) => PictureAnswer | null) {
  const asked: Asked[] = []
  const embeds: unknown[] = []
  Object.defineProperty(window, 'webkit', {
    configurable: true,
    value: {
      messageHandlers: {
        embeds: {
          postMessage: async (request: unknown) => {
            embeds.push(request)
            return null
          },
        },
        pictures: {
          postMessage: async (request: PictureRequest) => {
            asked.push({
              item: request.item,
              address: request.address,
              ask: request.ask,
              ...(request.export ? { export: true } : {}),
            })
            return answer(request)
          },
        },
      },
    },
  })
  return { asked, embeds }
}

afterEach(() => {
  delete (window as { webkit?: unknown }).webkit
  document.body.innerHTML = ''
})

const bar: { count: number; label: string }[] = []
const opened: string[] = []
beforeEach(() => {
  bar.length = 0
  opened.length = 0
})

async function withNote(
  source: string,
  run: (editor: NoteEditor) => void | Promise<void>,
  words = {},
) {
  const root = document.createElement('div')
  document.body.append(root)
  const editor = await NoteEditor.mount(
    root,
    {
      find() {},
      changed() {},
      stateChanged() {},
      copy() {},
      openLink: (href) => opened.push(href),
      picturesWaiting: (count, label) => bar.push({ count, label }),
    },
    {},
    words,
  )
  editor.setItem('note')
  editor.load(source, 1)
  try {
    await run(editor)
  } finally {
    await editor.destroy()
    root.remove()
  }
}

const cards = () => [...document.querySelectorAll('.inkkit-file')]
const labels = () => cards().map((card) => card.getAttribute('aria-label'))
const open = (index = 0) =>
  (document.querySelectorAll('.inkkit-file-open')[index] as HTMLButtonElement).click()
const settled = () => new Promise((resolve) => setTimeout(resolve, 20))
const loaded: PictureAnswer = { state: 'loaded', url: 'mapp-embed://picture/?address=x&v=1' }
const picture = '![A picture](https://example.com/a.png)\n'

test('with Ask, a picture at a web address is a card naming its website, and nothing is fetched', async () => {
  const { asked, embeds } = app(() => ({ state: 'waiting' }))
  await withNote(picture, async () => {
    await vi.waitFor(() => expect(labels()).toEqual(['example.com: Load Picture']))
    await settled()
    expect(asked).toEqual([{ item: 'note', address: 'https://example.com/a.png', ask: 'drawing' }])
    expect(embeds).toEqual([])
    expect(opened).toEqual([])
    expect(document.querySelector('img')).toBeNull()
  })
})

test('choosing a waiting picture asks the app to load it, and the card becomes the picture', async () => {
  const { asked } = app((request) => (request.ask === 'chosen' ? loaded : { state: 'waiting' }))
  await withNote(picture, async () => {
    await vi.waitFor(() => expect(labels()).toEqual(['example.com: Load Picture']))
    open()
    await vi.waitFor(() => expect(document.querySelector('.inkkit-file img')).not.toBeNull())
    expect(document.querySelector('.inkkit-file img')?.getAttribute('src')).toBe(loaded.url)
    expect(asked.map((request) => request.ask)).toEqual(['drawing', 'chosen'])
    expect(opened).toEqual([])
  })
})

test('the card says it is loading while the app fetches, and a second choice does not ask again', async () => {
  let finish: (answer: PictureAnswer) => void = () => {}
  const { asked } = app((request) => {
    if (request.ask !== 'chosen') return { state: 'waiting' }
    return new Promise<PictureAnswer>((resolve) => (finish = resolve)) as unknown as PictureAnswer
  })
  await withNote(picture, async () => {
    await vi.waitFor(() => expect(labels()).toEqual(['example.com: Load Picture']))
    open()
    await vi.waitFor(() => expect(labels()).toEqual(['example.com: Loading Picture…']))
    open()
    await settled()
    expect(asked.filter((request) => request.ask === 'chosen')).toHaveLength(1)
    finish(loaded)
    await vi.waitFor(() => expect(document.querySelector('.inkkit-file img')).not.toBeNull())
  })
})

test('the bar counts the pictures that wait, once for an address however often it appears', async () => {
  app((request) => (request.ask === 'chosen' ? loaded : { state: 'waiting' }))
  const source = `${picture}\n![again](https://example.com/a.png)\n\n![other](https://images.example.org/b.jpg)\n`
  await withNote(
    source,
    async (editor) => {
      await vi.waitFor(() => expect(bar.at(-1)).toEqual({ count: 2, label: 'Load 2 Pictures' }))
      editor.loadPictures()
      await vi.waitFor(() => expect(document.querySelectorAll('.inkkit-file img')).toHaveLength(3))
      await vi.waitFor(() => expect(bar.at(-1)?.count).toBe(0))
    },
    {},
  )
})

test('one waiting picture is told in the singular, and in the words the app gave', async () => {
  app(() => ({ state: 'waiting' }))
  await withNote(
    picture,
    async () => {
      await vi.waitFor(() => expect(bar.at(-1)).toEqual({ count: 1, label: 'Charger 1 image' }))
      expect(labels()).toEqual(['example.com: Charger l’image'])
    },
    {
      loadPicture: 'Charger l’image',
      loadOnePicture: 'Charger 1 image',
      loadPictures: 'Charger %lld images',
    },
  )
})

test('a picture left out of the text leaves the count', async () => {
  app(() => ({ state: 'waiting' }))
  await withNote(picture, async (editor) => {
    await vi.waitFor(() => expect(bar.at(-1)?.count).toBe(1))
    editor.reload('Nothing here.\n', 2, true)
    await vi.waitFor(() => expect(bar.at(-1)?.count).toBe(0))
  })
})

test('with Never, the card stays and says so, opens the address, and is not counted', async () => {
  const { asked } = app(() => ({ state: 'off' }))
  await withNote(picture, async () => {
    await vi.waitFor(() => expect(labels()).toEqual(['example.com: Remote Pictures Are Off']))
    open()
    expect(opened).toEqual(['https://example.com/a.png'])
    expect(asked.map((request) => request.ask)).toEqual(['drawing'])
    expect(bar.filter((entry) => entry.count > 0)).toEqual([])
  })
})

test('a refused picture names the reason, and is tried again only where the app says that may differ', async () => {
  const { asked } = app((request) => ({
    state: 'refused',
    reason: request.address.includes('slow') ? 'The picture took too long to load.' : 'Private.',
    ...(request.address.includes('slow') ? { retry: 'true' } : {}),
  }))
  await withNote(
    '![a](https://slow.example.com/a.png)\n\n![b](https://private.example.com/b.png)\n',
    async () => {
      await vi.waitFor(() =>
        expect(labels()).toEqual([
          'slow.example.com: The picture took too long to load.',
          'private.example.com: Private.',
        ]),
      )
      open(1)
      expect(opened).toEqual(['https://private.example.com/b.png'])
      open(0)
      await vi.waitFor(() =>
        expect(asked.filter((request) => request.ask === 'chosen')).toEqual([
          { item: 'note', address: 'https://slow.example.com/a.png', ask: 'chosen' },
        ]),
      )
      expect(bar.filter((entry) => entry.count > 0)).toEqual([])
    },
  )
})

test('a changed setting asks again about pictures that waited or were off, and not those loaded', async () => {
  let setting: 'waiting' | 'off' = 'waiting'
  const { asked } = app((request) =>
    request.address.includes('kept') ? loaded : { state: setting },
  )
  await withNote(
    '![a](https://example.com/a.png)\n\n![b](https://kept.example.com/b.png)\n',
    async (editor) => {
      await vi.waitFor(() => expect(labels()[0]).toBe('example.com: Load Picture'))
      setting = 'off'
      editor.picturesChanged()
      await vi.waitFor(() => expect(labels()[0]).toBe('example.com: Remote Pictures Are Off'))
      expect(asked.filter((request) => request.address.includes('kept'))).toHaveLength(1)
      await vi.waitFor(() => expect(bar.at(-1)?.count).toBe(0))
    },
  )
})

test('another note forgets what it was told of the last one', async () => {
  const { asked } = app(() => ({ state: 'waiting' }))
  await withNote(picture, async (editor) => {
    await vi.waitFor(() => expect(asked).toHaveLength(1))
    editor.setItem('other')
    editor.load(picture, 2)
    await vi.waitFor(() => expect(asked).toHaveLength(2))
    expect(asked[1]).toEqual({
      item: 'other',
      address: 'https://example.com/a.png',
      ask: 'drawing',
    })
  })
})

test('printing fetches nothing, and leaves the cards as the screen had them', async () => {
  const { asked } = app(() => ({ state: 'waiting' }))
  await withNote(picture, async (editor) => {
    await vi.waitFor(() => expect(bar.at(-1)?.count).toBe(1))
    await editor.printable().catch(() => undefined)
    await settled()
    expect(asked.filter((request) => request.ask === 'chosen')).toEqual([])
    await vi.waitFor(() => expect(labels()).toEqual(['example.com: Load Picture']))
    expect(bar.at(-1)?.count).toBe(1)
  })
})

test('a picture a print needs is asked for from the cache only', async () => {
  const { asked } = app((request) => (request.ask === 'cached' ? loaded : { state: 'waiting' }))
  const pictures = new WebPictures(
    {},
    () => {},
    () => {},
    async (request) => {
      asked.push({ item: request.item, address: request.address, ask: request.ask })
      return loaded
    },
  )
  pictures.setItem('note')
  pictures.cacheOnly = true
  const card = await pictures.present('https://example.com/a.png', undefined, {
    documentId: 'note',
    signal: new AbortController().signal,
  })
  expect(card).toMatchObject({ kind: 'image', url: loaded.url })
  expect(asked.map((request) => request.ask)).toEqual(['cached'])
})

test('a portable export takes the bytes of a held picture from the app', async () => {
  const pictures = new WebPictures(
    {},
    () => {},
    () => {},
    async (request) => {
      expect(request).toMatchObject({ ask: 'cached', export: true })
      return { state: 'loaded', data: btoa('png'), mimeType: 'image/png' }
    },
  )
  const { bytes, mimeType } = await pictures.bytes('note', 'https://example.com/a.png')
  expect(new TextDecoder().decode(bytes)).toBe('png')
  expect(mimeType).toBe('image/png')
})
