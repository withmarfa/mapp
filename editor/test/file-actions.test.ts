import { afterEach, expect, test, vi } from 'vitest'
import { ItemEditor } from '../src/editor'
import { quickLookAction, quickLookIcon } from '../src/file-actions'

type Sent = { type: string; embed?: { item: string; text: string } }

/** A stand-in for the app: it answers every embed as the given file and records what the page posts to the host. */
function app(answer: unknown) {
  const host: Sent[] = []
  Object.defineProperty(window, 'webkit', {
    configurable: true,
    value: {
      messageHandlers: {
        host: { postMessage: (message: Sent) => host.push(message) },
        embeds: { postMessage: async () => answer },
      },
    },
  })
  return host
}

afterEach(() => {
  delete (window as { webkit?: unknown }).webkit
})

async function withItem(source: string, run: (editor: ItemEditor) => Promise<void>) {
  const root = document.createElement('div')
  document.body.append(root)
  const editor = await ItemEditor.mount(
    root,
    { find() {}, changed() {}, stateChanged() {}, openLink() {}, copy() {} },
    {},
    { quickLookNamed: 'Quick Look %@' },
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

const actions = () => [...document.querySelectorAll<HTMLElement>('.inkkit-file-actions button')]

test('a file card has Quick Look as an icon before Open, named for the file', async () => {
  app({ kind: 'file', name: 'report.txt', url: 'mapp-embed:x/report.txt' })
  await withItem('![[report.txt]]\n', async () => {
    await vi.waitFor(() => expect(actions()).toHaveLength(2))
    const [quickLook, open] = actions()
    expect(quickLook!.getAttribute('aria-label')).toBe('Quick Look report.txt')
    expect(quickLook!.title).toBe('Quick Look report.txt')
    expect(quickLook!.textContent).toBe('')
    expect(open!.classList.contains('inkkit-file-open')).toBe(true)
  })
})

test('Quick Look asks the app for the embed as written and changes no text', async () => {
  const host = app({ kind: 'file', name: 'report.txt', url: 'mapp-embed:x/report.txt' })
  const source = 'Before\n\n![[report.txt]]\n\nAfter\n'
  await withItem(source, async (editor) => {
    await vi.waitFor(() => expect(actions()).toHaveLength(2))
    actions()[0]!.click()
    expect(host).toEqual([
      { type: 'quickLookEmbed', embed: { item: 'note', text: '![[report.txt]]' } },
    ])
    expect(editor.snapshot().text).toBe(source)
  })
})

test('a PDF card has Quick Look too, and a card the app could not resolve has none', async () => {
  app({ kind: 'pdf', name: 'paper.pdf', url: 'mapp-embed:x/paper.pdf' })
  await withItem('![[paper.pdf]]\n', async () => {
    await vi.waitFor(() => expect(actions()).toHaveLength(2))
    expect(actions()[0]!.getAttribute('aria-label')).toBe('Quick Look paper.pdf')
  })
  app({ unavailable: 'Too large' })
  await withItem('![[huge.bin]]\n', async () => {
    await vi.waitFor(() => expect(document.querySelector('.inkkit-file-status')).not.toBeNull())
    expect(actions().map((button) => button.getAttribute('aria-label'))).not.toContain(
      'Quick Look huge.bin',
    )
  })
})

test("the action's name takes the app's words, and its icon is an image Inkkit can draw", () => {
  const action = quickLookAction('a$&b.txt', 'Look at %@', () => {})
  expect(action.label).toBe('Look at a$&b.txt')
  expect(quickLookAction('x', undefined, () => {}).label).toBe('Quick Look x')
  expect(action.icon).toBe(quickLookIcon)
  expect(quickLookIcon.startsWith('data:image/svg+xml,')).toBe(true)
  expect(decodeURIComponent(quickLookIcon.slice('data:image/svg+xml,'.length))).toContain('<svg')
})
