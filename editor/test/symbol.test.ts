import { expect, test } from 'vitest'
import { showSymbolButton } from '../src/symbol'

const xmark = { url: 'mapp-icon://xmark', width: 9, height: 9 }

function closeButton() {
  const button = document.createElement('button')
  const glyph = document.createElement('span')
  glyph.hidden = true
  button.append(glyph)
  return { button, glyph }
}

test('a button of only a symbol stays hidden until the symbol arrives, so it is never an empty circle', () => {
  const { button, glyph } = closeButton()
  button.hidden = true
  showSymbolButton(button, glyph, undefined)
  expect(button.hidden).toBe(true)
  expect(glyph.hidden).toBe(true)

  showSymbolButton(button, glyph, xmark)
  expect(button.hidden).toBe(false)
  expect(glyph.hidden).toBe(false)
  expect(glyph.style.width).toBe('9px')
  expect(glyph.style.maskImage || glyph.style.getPropertyValue('-webkit-mask-image')).toContain(
    'xmark',
  )
})

test('icons sent again without the symbol hide the button again', () => {
  const { button, glyph } = closeButton()
  showSymbolButton(button, glyph, xmark)
  showSymbolButton(button, glyph, undefined)
  expect(button.hidden).toBe(true)
  expect(glyph.hidden).toBe(true)
})
