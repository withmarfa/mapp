import { beforeEach, expect, test } from 'vitest'
import { LinkStyle } from '../src/link-style'

let style: CSSStyleDeclaration
let links: LinkStyle
beforeEach(() => {
  style = document.createElement('div').style
  links = new LinkStyle(style)
})

test('a style is set as variables on the page', () => {
  expect(
    links.set({ '--inkkit-wiki-link-underline': 'underline', '--link-tint-blue': 'red' }),
  ).toBe(true)
  expect(style.getPropertyValue('--inkkit-wiki-link-underline')).toBe('underline')
  expect(style.getPropertyValue('--link-tint-blue')).toBe('red')
})

test('a variable the next style does not name is taken off, so a look leaves nothing of the one before', () => {
  links.set({ '--inkkit-wiki-link-radius': '4px', '--inkkit-wiki-link-underline': 'underline' })
  links.set({ '--inkkit-wiki-link-underline': 'underline' })
  expect(style.getPropertyValue('--inkkit-wiki-link-radius')).toBe('')
  expect(style.getPropertyValue('--inkkit-wiki-link-underline')).toBe('underline')
  links.set({})
  expect(style.getPropertyValue('--inkkit-wiki-link-underline')).toBe('')
})

test('the same style again changes nothing and says so', () => {
  const look = { '--inkkit-wiki-link-radius': '4px' }
  expect(links.set(look)).toBe(true)
  expect(links.set({ ...look })).toBe(false)
})

test('a name that is not a link variable is not set', () => {
  links.set({ color: 'red', '--other': '1', 'font-size': '90px', '--link-icon-red': 'blue' })
  expect(style.getPropertyValue('color')).toBe('')
  expect(style.getPropertyValue('--other')).toBe('')
  expect(style.getPropertyValue('font-size')).toBe('')
  expect(style.getPropertyValue('--link-icon-red')).toBe('blue')
})
