import { expect, test } from 'vitest'
import type { InkKitEditor } from '@aicayzer/inkkit'
import { NoteEditor, type PageHeading } from '../src/editor'

interface Said {
  headings: PageHeading[]
  generation: number
}

async function withNote(
  source: string,
  run: (note: { editor: NoteEditor; said: Said[]; engine: InkKitEditor }) => Promise<void>,
) {
  const root = document.createElement('div')
  document.body.append(root)
  const said: Said[] = []
  const editor = await NoteEditor.mount(root, {
    find() {},
    changed() {},
    stateChanged() {},
    openLink() {},
    copy() {},
    headings: (headings, generation) => said.push({ headings, generation }),
  })
  editor.setItem('note')
  editor.load(source, 1)
  try {
    await run({ editor, said, engine: (editor as unknown as { engine: InkKitEditor }).engine })
  } finally {
    await editor.destroy()
    root.remove()
  }
}
const settle = () => new Promise((done) => setTimeout(done, 0))
const texts = (said: Said) => said.headings.map((heading) => heading.text)
/** Types at the end of `after`'s first appearance, as a person would. */
async function type(engine: InkKitEditor, after: string, text: string) {
  const snapshot = engine.textSnapshot(1)
  const at = snapshot.text.indexOf(after) + after.length
  engine.selectTextRange({ snapshotId: snapshot.snapshotId, from: at, to: at })
  engine.insertText(text, 1)
  await settle()
}

test('a load says the headings once, with its generation', () =>
  withNote('# Soil\n\ntext\n\n## Water\n', async ({ said }) => {
    await settle()
    expect(said).toEqual([
      {
        generation: 1,
        headings: [
          { level: 1, text: 'Soil' },
          { level: 2, text: 'Water' },
        ],
      },
    ])
  }))

test('a note with no headings says an empty list', () =>
  withNote('just words\n', async ({ said }) => {
    expect(said).toEqual([{ generation: 1, headings: [] }])
  }))

test('an edit that leaves the headings alone says nothing, and one that changes them says the new list once', () =>
  withNote('# Soil\n\ntext\n\n## Water\n', async ({ said, engine }) => {
    await settle()
    said.length = 0
    await type(engine, 'text', ' more')
    await type(engine, 'text more', ' still')
    expect(said).toEqual([])
    await type(engine, 'Water', 's')
    expect(said.map(texts)).toEqual([['Soil', 'Waters']])
    expect(said[0]!.generation).toBe(1)
  }))

test('another load says its list even when it equals the last one', () =>
  withNote('# Soil\n', async ({ editor, said }) => {
    await settle()
    editor.load('# Soil\n', 2)
    editor.reload('# Soil\n', 3)
    expect(said.map((entry) => entry.generation)).toEqual([1, 2, 3])
  }))

test('a list followed by a rule has no heading, as Inkkit counts', () =>
  withNote('- one\n- two\n\n---\n\n# Real\n', async ({ said }) => {
    expect(said.map(texts)).toEqual([['Real']])
  }))

test('a quote holding a fenced block with heading-like lines has none from the block', () =>
  withNote('> ```\n> # not a heading\n> ```\n\n# After\n', async ({ said }) => {
    expect(said.map(texts)).toEqual([['After']])
  }))

test('a longer fence is not closed by a shorter one', () =>
  withNote('````\n```\n# inside\n```\n````\n\n# Outside\n', async ({ said }) => {
    expect(said.map(texts)).toEqual([['Outside']])
  }))

test('a rule on the first line is not front matter and the next heading is listed', () =>
  withNote('---\n\n# Title\n', async ({ said }) => {
    expect(said.map(texts)).toEqual([['Title']])
  }))

test('setext headings count, and text is the words without marks', () =>
  withNote('Plain **bold** and `code`\n=========\n\nSecond [link](u)\n---\n', async ({ said }) => {
    expect(said[0]!.headings).toEqual([
      { level: 1, text: 'Plain bold and code' },
      { level: 2, text: 'Second link' },
    ])
  }))

test('a heading with no words is in the list, so the ordinals match Inkkit', () =>
  withNote('# \n\n# Next\n', async ({ editor, said }) => {
    const list = said[0]!.headings
    expect(list.map((heading) => heading.text)).toEqual(['', 'Next'])
    expect(editor.revealHeadingAt(1)).toBe(true)
  }))

test('two headings that read the same are two entries', () =>
  withNote('# Soil\n\n## Soil\n', async ({ said }) => {
    expect(said.map(texts)).toEqual([['Soil', 'Soil']])
  }))
