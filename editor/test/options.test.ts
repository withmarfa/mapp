import { expect, test } from 'vitest'
import { InkKitError } from '@aicayzer/inkkit'
import { ItemEditor, guardedCommand } from '../src/editor'

async function withEditor(source: string, run: (editor: ItemEditor, root: HTMLElement) => void) {
  const root = document.createElement('div')
  document.body.append(root)
  const editor = await ItemEditor.mount(root, {
    find() {},
    changed() {},
    stateChanged() {},
    openLink() {},
    copy() {},
  })
  editor.setItem('note')
  editor.load(source, 1)
  try {
    await run(editor, root)
  } finally {
    await editor.destroy()
    root.remove()
  }
}

const frames = (count: number) =>
  new Promise<void>((done) => {
    const next = (left: number) => requestAnimationFrame(() => (left ? next(left - 1) : done()))
    next(count)
  })

test('an edit that touched hidden text is run again after the next paint, so it is not lost', async () => {
  let runs = 0
  const edit = () => {
    runs += 1
    if (runs === 1) throw new InkKitError('hidden-text', 'The section was folded.')
    return true
  }
  expect(guardedCommand(edit, { retry: true })).toEqual({
    commandError: 'hidden-text',
    message: 'The section was folded.',
  })
  expect(runs).toBe(1)
  await frames(3)
  expect(runs).toBe(2)
})

test('a command not marked to retry is refused once and not run again', async () => {
  let runs = 0
  const edit = () => {
    runs += 1
    throw new InkKitError('hidden-text', 'The section was folded.')
  }
  guardedCommand(edit)
  await frames(3)
  expect(runs).toBe(1)
})

test('a retry that is refused again is not repeated for ever', async () => {
  let runs = 0
  const edit = () => {
    runs += 1
    throw new InkKitError('hidden-text', 'Still hidden.')
  }
  guardedCommand(edit, { retry: true })
  await frames(6)
  expect(runs).toBe(2)
})

test('options reach a page that is already open, as one set that replaces the last', async () =>
  withEditor('# Title\n\ntext\n\n```js\nlet a = 1\nlet b = 2\n```\n', async (editor, root) => {
    expect(root.querySelector('pre[data-inkkit-line-numbers]')).toBeNull()
    editor.setOptions({ textInput: {}, display: { codeLineNumbers: true, foldHeadings: true } })
    expect(root.querySelector('pre[data-inkkit-line-numbers]')).not.toBeNull()
    expect(root.querySelector('[aria-label^="Fold section"]')).not.toBeNull()
    // The next set replaces the whole of the last: a field left out is back at its default.
    editor.setOptions({ textInput: { spellcheck: false }, display: {} })
    expect(root.querySelector('pre[data-inkkit-line-numbers]')).toBeNull()
  }))
