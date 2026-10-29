import { afterEach, beforeEach, expect, test, vi } from 'vitest'
import type { PictureAnswer, PictureRequest } from '../src/bridge'
import { NoteEditor } from '../src/editor'
import { sameAddress, WebPictures } from '../src/pictures'

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

const bar: { count: number; sentence: string; button: string }[] = []
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
      picturesWaiting: (count, sentence, button) => bar.push({ count, sentence, button }),
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
    await vi.waitFor(() => expect(bar.at(-1)?.count).toBe(1))
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
    await vi.waitFor(() => expect(bar.at(-1)?.count).toBe(1))
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
    await vi.waitFor(() => expect(bar.at(-1)?.count).toBe(1))
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
      await vi.waitFor(() =>
        expect(bar.at(-1)).toEqual({
          count: 2,
          sentence: '2 pictures from other websites aren’t loaded.',
          button: 'Load Pictures',
        }),
      )
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
    '![](https://example.com/a.png)\n',
    async () => {
      await vi.waitFor(() =>
        expect(bar.at(-1)).toEqual({
          count: 1,
          sentence: '1 image d’un autre site n’est pas chargée.',
          button: 'Charger l’image',
        }),
      )
      expect(labels()).toEqual(['Image de example.com'])
    },
    {
      pictureFrom: 'Image de %@',
      loadOnePicture: 'Charger l’image',
      loadPictures: 'Charger les images',
      pictureNotLoaded: '1 image d’un autre site n’est pas chargée.',
      picturesNotLoaded: '%lld images d’autres sites ne sont pas chargées.',
    },
  )
})

test('a picture with no alt text is named by its website', async () => {
  app(() => ({ state: 'waiting' }))
  await withNote('![](https://example.com/a.png)\n', async () => {
    await vi.waitFor(() => expect(labels()).toEqual(['Picture from example.com']))
    expect(bar.at(-1)).toEqual({
      count: 1,
      sentence: '1 picture from another website isn’t loaded.',
      button: 'Load Picture',
    })
  })
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
      await vi.waitFor(() => expect(bar.at(-1)?.count).toBe(1))
      setting = 'off'
      editor.picturesChanged()
      await vi.waitFor(() => expect(labels()[0]).toBe('example.com: Remote Pictures Are Off'))
      expect(asked.filter((request) => request.address.includes('kept'))).toHaveLength(1)
      await vi.waitFor(() => expect(bar.at(-1)?.count).toBe(0))
    },
  )
})

test('a picture saved as a file on the item is asked about again, loaded or not, but not one being chosen', async () => {
  let saved = false
  let finish: (answer: PictureAnswer) => void = () => {}
  const { asked } = app((request) => {
    if (request.address.includes('chosen')) {
      if (request.ask !== 'chosen') return { state: 'waiting' }
      return new Promise<PictureAnswer>((resolve) => (finish = resolve)) as unknown as PictureAnswer
    }
    return saved ? loaded : { state: 'refused', reason: 'No', retry: 'true' }
  })
  await withNote(
    '![a](https://example.com/a.png)\n\n![b](https://chosen.example.com/b.png)\n',
    async (editor) => {
      await vi.waitFor(() => expect(labels()[0]).toBe('example.com: No'))
      expect(asked.filter((request) => request.address.includes('example.com/a'))).toHaveLength(1)
      open(1)
      await vi.waitFor(() => expect(labels()[1]).toBe('chosen.example.com: Loading Picture…'))
      saved = true
      editor.savedPicturesChanged(['https://example.com/a.png', 'https://chosen.example.com/b.png'])
      await vi.waitFor(() =>
        expect(asked.filter((request) => request.address.includes('example.com/a'))).toHaveLength(
          2,
        ),
      )
      await vi.waitFor(() => expect(labels()).not.toContain('example.com: No'))
      expect(asked.filter((request) => request.address.includes('chosen.example.com'))).toEqual([
        { item: 'note', address: 'https://chosen.example.com/b.png', ask: 'drawing' },
        { item: 'note', address: 'https://chosen.example.com/b.png', ask: 'chosen' },
      ])
      finish(loaded)
    },
  )
})

test('a picture being chosen when a saved file comes still ends loaded with the answer', async () => {
  let finish: (answer: PictureAnswer) => void = () => {}
  app((request) => {
    if (request.ask !== 'chosen') return { state: 'waiting' }
    return new Promise<PictureAnswer>((resolve) => (finish = resolve)) as unknown as PictureAnswer
  })
  await withNote(picture, async (editor) => {
    await vi.waitFor(() => expect(bar.at(-1)?.count).toBe(1))
    open()
    await vi.waitFor(() => expect(labels()).toEqual(['example.com: Loading Picture…']))
    editor.savedPicturesChanged(['https://example.com/a.png'])
    await settled()
    finish(loaded)
    await vi.waitFor(() => expect(document.querySelector('.inkkit-file img')).not.toBeNull())
    expect(bar.at(-1)?.count).toBe(0)
  })
})

test('a picture being chosen when the setting changes still ends loaded with the answer', async () => {
  let finish: (answer: PictureAnswer) => void = () => {}
  app((request) => {
    if (request.ask !== 'chosen') return { state: 'waiting' }
    return new Promise<PictureAnswer>((resolve) => (finish = resolve)) as unknown as PictureAnswer
  })
  await withNote(picture, async (editor) => {
    await vi.waitFor(() => expect(bar.at(-1)?.count).toBe(1))
    open()
    await vi.waitFor(() => expect(labels()).toEqual(['example.com: Loading Picture…']))
    editor.picturesChanged()
    await settled()
    finish(loaded)
    await vi.waitFor(() => expect(document.querySelector('.inkkit-file img')).not.toBeNull())
  })
})

test('a saved file coming asks again only about the pictures at its address', async () => {
  const { asked } = app((request) =>
    request.address.includes('gone')
      ? { state: 'refused', reason: 'Not found.' }
      : request.address.includes('slow')
        ? { state: 'refused', reason: 'Too slow.', retry: 'true' }
        : request.address.includes('kept')
          ? loaded
          : { state: 'waiting' },
  )
  await withNote(
    '![a](https://gone.example.com/a.png)\n\n![b](https://slow.example.com/b.png)\n\n![c](https://kept.example.com/c.png)\n',
    async (editor) => {
      await vi.waitFor(() =>
        expect(labels()).toEqual([
          'gone.example.com: Not found.',
          'slow.example.com: Too slow.',
          'c',
        ]),
      )
      asked.length = 0
      // A refusal that stays is not asked about again when a file comes for another picture.
      editor.savedPicturesChanged(['https://slow.example.com/b.png'])
      await settled()
      expect(asked.map((request) => request.address)).toEqual(['https://slow.example.com/b.png'])
      // A file saved from the address of a refused picture can answer it, so that one is asked.
      asked.length = 0
      editor.savedPicturesChanged(['https://GONE.example.com:443/a.png#top'])
      await settled()
      expect(asked.map((request) => request.address)).toEqual(['https://gone.example.com/a.png'])
    },
  )
})

test('an address is compared as the app compares a saved file with a picture', () => {
  const same = (a: string, b: string) => sameAddress(a) === sameAddress(b)
  expect(same('HTTPS://Example.com:443/a.png#x', 'https://example.com/a.png')).toBe(true)
  expect(same('http://example.com:80', 'http://example.com/')).toBe(true)
  expect(same('https://example.com/a.png?x=1', 'https://example.com/a.png?x=1')).toBe(true)
  expect(same('https://example.com/A.png', 'https://example.com/a.png')).toBe(false)
  expect(same('https://example.com/a.png?x=1', 'https://example.com/a.png')).toBe(false)
  expect(same('https://example.com:8443/a.png', 'https://example.com/a.png')).toBe(false)
  expect(same('https://example.com/a/', 'https://example.com/a')).toBe(false)
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
    await vi.waitFor(() => expect(bar.at(-1)?.count).toBe(1))
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
