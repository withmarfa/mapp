import { afterEach, expect, test } from 'vitest'
import { linkAddressAtSelection } from '../src/linkAddress'

afterEach(() => {
  document.body.innerHTML = ''
  window.getSelection()?.removeAllRanges()
})

function page(): HTMLElement {
  const root = document.createElement('div')
  root.innerHTML = '<p>Read the <a href="https://example.com:8080/a">docs</a> now</p>'
  document.body.append(root)
  return root
}

function select(node: Node, offset: number): void {
  const range = document.createRange()
  range.setStart(node, offset)
  range.collapse(true)
  window.getSelection()?.removeAllRanges()
  window.getSelection()?.addRange(range)
}

test('the address of the link the caret is in', () => {
  const root = page()
  select(root.querySelector('a')!.firstChild!, 2)
  expect(linkAddressAtSelection(root)).toBe('https://example.com:8080/a')
})

test('the address of a link whose text is selected from the text before it', () => {
  const root = page()
  const range = document.createRange()
  range.setStart(root.querySelector('p')!.firstChild!, 9)
  range.setEnd(root.querySelector('a')!.firstChild!, 4)
  window.getSelection()?.addRange(range)
  expect(linkAddressAtSelection(root)).toBe('https://example.com:8080/a')
})

test('no address outside a link, or with no selection', () => {
  const root = page()
  expect(linkAddressAtSelection(root)).toBeNull()
  select(root.querySelector('p')!.firstChild!, 2)
  expect(linkAddressAtSelection(root)).toBeNull()
})
