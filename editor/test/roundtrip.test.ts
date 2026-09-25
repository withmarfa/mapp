import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { expect, test } from 'vitest'
import { editorViewCtx } from '@milkdown/kit/core'
import { TextSelection } from '@milkdown/kit/prose/state'
import { insertTableCommand } from '@milkdown/kit/preset/gfm'
import { callCommand } from '@milkdown/kit/utils'
import { serialize } from '../src/dialect'
import { roundTrip, withEditor } from './harness'

const fixture = readFileSync(resolve(__dirname, '../fixtures/dialect.md'), 'utf8')

test('the dialect fixture is written back byte for byte', async () => {
  expect(await roundTrip(fixture)).toBe(fixture)
})

test('a note written back is stable on a second pass', async () => {
  const once = await roundTrip(fixture)
  expect(await roundTrip(once)).toBe(once)
})

const variants: Array<[string, string, string]> = [
  ['underscore emphasis', '_italic_ and __bold__\n', '*italic* and **bold**\n'],
  ['star bullets', '* one\n* two\n', '- one\n- two\n'],
  ['two-space hard break', 'first  \nsecond\n', 'first\\\nsecond\n'],
  ['star rule', '***\n', '---\n'],
  ['bare url stays bare', 'See https://example.com now\n', 'See https://example.com now\n'],
  [
    'angle brackets become the bare url',
    'See <https://example.com> now\n',
    'See https://example.com now\n',
  ],
  [
    'a url with its own words keeps its form',
    '[a site](https://example.com)\n',
    '[a site](https://example.com)\n',
  ],
  ['indented code stays fenced', '    code\n', '```\ncode\n```\n'],
  ['heading with closing marks', '## Title ##\n', '## Title\n'],
]

for (const [name, input, canonical] of variants) {
  test(`non-canonical input is read and written in canonical form: ${name}`, async () => {
    expect(await roundTrip(input)).toBe(canonical)
  })
}

test('an empty paragraph is left out rather than written as html', async () => {
  const out = await withEditor('a\n\nb\n', (editor) => {
    const view = editor.ctx.get(editorViewCtx)
    const paragraph = view.state.schema.nodes.paragraph!
    view.dispatch(view.state.tr.insert(3, paragraph.create()))
    return serialize(editor.ctx)
  })
  expect(out).toBe('a\n\nb\n')
})

test('a note that is only an empty paragraph is written as nothing', async () => {
  expect(await roundTrip('')).toBe('')
})

test('a typed url becomes a link when a space follows it', async () => {
  const links = await withEditor('see', (editor) => {
    const view = editor.ctx.get(editorViewCtx)
    const hrefs = () => {
      const found: string[] = []
      view.state.doc.descendants((node) => {
        for (const mark of node.marks) if (mark.type.name === 'link') found.push(mark.attrs.href)
      })
      return found
    }
    view.dispatch(
      view.state.tr.insertText(' https://example.com/page', view.state.doc.content.size - 1),
    )
    const typed = hrefs()
    const end = view.state.doc.content.size - 1
    view.someProp('handleTextInput', (handler) => handler(view, end, end, ' ', () => view.state.tr))
    return [typed, hrefs()]
  })
  expect(links).toEqual([[], ['https://example.com/page']])
})

test('trailing punctuation is not swallowed into a bare url', async () => {
  expect(await roundTrip('See https://example.com, then stop.\n')).toBe(
    'See https://example.com, then stop.\n',
  )
})

test('a url that would read differently keeps its angle brackets', async () => {
  expect(await roundTrip('<https://example.com/page.>\n')).toBe('<https://example.com/page.>\n')
})

test('an image keeps its markdown though the page shows only its name', async () => {
  const markdown = '![A diagram](diagram.png "Plan")\n'
  expect(await roundTrip(markdown)).toBe(markdown)
})

test('a table made in the editor has no alignment until someone sets one', async () => {
  const out = await withEditor('Intro\n', (editor) => {
    editor.action(callCommand(insertTableCommand.key, { row: 2, col: 2 }))
    return serialize(editor.ctx)
  })
  expect(out).toContain('| --- | --- |')
  expect(out).not.toContain(':-')
})

test('table cells keep inline formatting and escaped pipes', async () => {
  const markdown = '| a | b |\n| --- | --- |\n| `x \\| y` | **bold** |\n'
  expect(await roundTrip(markdown)).toBe(markdown)
})
