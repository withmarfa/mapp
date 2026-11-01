import { afterEach, beforeEach, expect, test } from 'vitest'
import { openLink, type EditorMessage } from '../src/bridge'

let hosted: EditorMessage[]
beforeEach(() => {
  hosted = []
  Object.defineProperty(window, 'webkit', {
    configurable: true,
    value: { messageHandlers: { host: { postMessage: (m: EditorMessage) => hosted.push(m) } } },
  })
})
afterEach(() => {
  delete (window as { webkit?: unknown }).webkit
})

test('only a web, mail or phone address is passed to the app to open', () => {
  for (const href of ['https://example.com/a', 'HTTP://example.com', 'mailto:a@b.co', 'tel:+4412'])
    openLink(href)
  expect(hosted.map((m) => m.type === 'openLink' && m.href)).toEqual([
    'https://example.com/a',
    'HTTP://example.com',
    'mailto:a@b.co',
    'tel:+4412',
  ])
  hosted.length = 0
  for (const href of [
    'file:///etc/passwd',
    'javascript:alert(1)',
    '/etc/hosts',
    'example.com',
    'https://a.co/\u0000',
  ])
    openLink(href)
  expect(hosted).toEqual([])
})
