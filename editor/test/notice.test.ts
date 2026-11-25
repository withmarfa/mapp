import { expect, test, vi } from 'vitest'
import { PageNoticeLine, type NoticeModel } from '../src/notice'

const icon = (name: string) => ({ url: `data:image/png;base64,${name}`, width: 13, height: 13 })
const icons = (...names: string[]) => ({
  indicator: icon('i'),
  symbols: Object.fromEntries([...names, 'xmark'].map((name) => [name, icon(name)])),
})

function line() {
  const root = document.createElement('div')
  const reason = document.createElement('p')
  const action = vi.fn()
  const notice = new PageNoticeLine(root, reason, { action, close: vi.fn() }, () => 'Close')
  return { root, reason, action, notice }
}

const deleted: NoticeModel = {
  kind: 'deleted',
  item: 'a',
  symbol: 'trash',
  words: 'Deleted.',
  action: 'Recover',
}
const held: NoticeModel = {
  kind: 'held',
  item: 'a',
  symbol: 'exclamationmark.triangle',
  words: 'Held.',
}

test('an action names the item the app made the notice for, with no item on the page', () => {
  const { root, action, notice } = line()
  notice.setIcons(icons('trash', 'exclamationmark.triangle'))
  notice.setApp([deleted, held])
  expect(root.querySelectorAll('.page-notice')).toHaveLength(2)
  root.querySelector<HTMLButtonElement>('.page-notice-action')?.click()
  expect(action).toHaveBeenCalledWith('deleted', 'a')
})

test('new symbols redraw the lines in place, so the live region is not read again', () => {
  const { root, notice } = line()
  notice.setIcons(icons('trash'))
  notice.setApp([deleted])
  const shown = root.querySelector('.page-notice')
  notice.setIcons(icons('trash', 'other'))
  expect(root.querySelector('.page-notice')).toBe(shown)
})

test('a line waits for its own symbol', () => {
  const { root, notice } = line()
  notice.setApp([deleted])
  expect(root.children).toHaveLength(0)
  notice.setIcons(icons('trash'))
  expect(root.children).toHaveLength(1)
})
