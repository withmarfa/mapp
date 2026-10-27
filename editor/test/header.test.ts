import { afterEach, beforeEach, expect, test } from 'vitest'
import type { EditorMessage } from '../src/bridge'
import { ItemHeader, type HeaderModel } from '../src/header'

let posted: EditorMessage[] = []
let root: HTMLElement
let header: ItemHeader

const ticket: HeaderModel = {
  item: 'ticket',
  hidden: false,
  title: 'Review the findings',
  draft: null,
  titleRejected: false,
  titleRefusal:
    'The title could not be saved. Use a unique file name without slashes or line breaks.',
  editable: true,
  type: 'Task',
  status: {
    label: 'In Progress',
    enabled: true,
    empty: false,
    opensMenu: true,
    mark: { tone: 'orange', fill: 'half' },
  },
  parent: { label: 'Field Research', enabled: true, empty: false, opensMenu: true },
  byline: { source: 'workbench-folder', date: 'Saturday' },
  properties: [
    { id: 'status', label: 'Status', symbol: 'circle.dotted', kind: 'status' },
    { id: 'child-of', label: 'Epic', symbol: 'square.stack', kind: 'parent' },
  ],
  foldAfter: 6,
  linked: [],
  linkedFoldAfter: 20,
  showMore: 'Show 0 More',
  showMoreLinked: 'Show 0 More',
  propertyRejected: false,
  parentRejected: false,
  interfaceTextSize: 13,
}

beforeEach(() => {
  posted = []
  window.webkit = { messageHandlers: { host: { postMessage: (message) => posted.push(message) } } }
  root = document.createElement('header')
  document.body.append(root)
  header = new ItemHeader(root, { untitled: 'Sans titre' })
})

afterEach(() => {
  root.remove()
  delete window.webkit
})

const title = () => root.querySelector<HTMLElement>('#ItemPageTitle')!
const pin = (id: string) => root.querySelector<HTMLElement>('#' + id)!
const label = (id: string) => pin(id).querySelector('.item-pin-label')!.textContent

test('the header shows the item it is given, and nothing before', () => {
  expect(root.hidden).toBe(true)
  header.set(ticket)
  expect(root.hidden).toBe(false)
  expect(title().textContent).toBe('Review the findings')
  expect(title().getAttribute('contenteditable')).toBe('plaintext-only')
  expect(title().getAttribute('aria-label')).toBe('Title')
  expect(title().dataset.placeholder).toBe('Sans titre')
  expect(label('ItemTypePin')).toBe('Task')
  expect(pin('ItemTypePin').title).toBe('Item Type')
  expect(label('ItemStatusPin')).toBe('In Progress')
  expect(pin('ItemStatusPin').getAttribute('aria-label')).toBe('Status')
  expect(label('ItemParentPin')).toBe('Field Research')
  expect(root.querySelector<HTMLElement>('.item-title-error')!.hidden).toBe(true)

  header.set({ ...ticket, type: null, status: null, parent: null, editable: false, draft: 'Draft' })
  expect(title().textContent).toBe('Draft')
  expect(title().getAttribute('contenteditable')).toBe('false')
  expect(pin('ItemTypePin').hidden).toBe(true)
  expect(pin('ItemStatusPin').hidden).toBe(true)
  expect(pin('ItemParentPin').hidden).toBe(true)

  header.set({ ...ticket, hidden: true })
  expect(root.hidden).toBe(true)
  header.set(null)
  expect(root.hidden).toBe(true)
})

test('a pin without a value is drawn empty, and a status pin carries its mark', () => {
  header.set(ticket)
  const mark = () => pin('ItemStatusPin').querySelector<HTMLElement>('.item-status-mark')!
  expect(pin('ItemParentPin').classList.contains('empty')).toBe(false)
  expect(mark().dataset.tone).toBe('orange')
  expect(mark().dataset.fill).toBe('half')
  header.set({
    ...ticket,
    status: {
      label: 'Completed',
      enabled: true,
      empty: false,
      opensMenu: true,
      mark: { tone: 'green', fill: 'full' },
    },
    parent: { label: 'Parent', enabled: true, empty: true, opensMenu: false },
  })
  expect(mark().dataset.tone).toBe('green')
  expect(mark().dataset.fill).toBe('full')
  expect(pin('ItemParentPin').classList.contains('empty')).toBe(true)
  expect(label('ItemParentPin')).toBe('Parent')
  // The empty parent pin opens the app's chooser directly, so it has no chevron and is not announced as a menu.
  expect(pin('ItemParentPin').classList.contains('direct')).toBe(true)
  expect(pin('ItemParentPin').getAttribute('aria-haspopup')).toBe('dialog')
  expect(pin('ItemStatusPin').classList.contains('direct')).toBe(false)
  expect(pin('ItemStatusPin').getAttribute('aria-haspopup')).toBe('menu')
  pin('ItemParentPin').dispatchEvent(new MouseEvent('pointerdown', { button: 0 }))
  expect(posted.map((message) => message.type)).toEqual(['headerMenu'])
  header.set({
    ...ticket,
    status: { label: 'Status', enabled: true, empty: true, opensMenu: true },
  })
  expect(pin('ItemStatusPin').classList.contains('empty')).toBe(true)
  expect(pin('ItemStatusPin').getAttribute('aria-description')).toBe('')
})

test('a refused title shows why and offers to discard the draft', () => {
  header.set({
    ...ticket,
    draft: 'A/B',
    titleRejected: true,
    propertyRejected: true,
    parentRejected: true,
  })
  const error = root.querySelector<HTMLElement>('.item-title-error')!
  expect(error.hidden).toBe(false)
  expect(error.textContent).toContain('The title could not be saved.')
  expect([...root.querySelectorAll<HTMLElement>('.item-error')].every((e) => !e.hidden)).toBe(true)
  error.querySelector('button')!.click()
  expect(posted).toEqual([{ type: 'titleDiscard', item: 'ticket' }])
})

test('a parent that could not be removed says so, apart from a refused status', () => {
  const errors = () => [...root.querySelectorAll<HTMLElement>(':scope > .item-error')]
  header.set({ ...ticket, parentRejected: true })
  expect(errors().map((e) => e.hidden)).toEqual([true, false])
  expect(errors()[1]!.textContent).toBe('The connection could not be removed.')
  header.set(ticket)
  expect(errors().every((e) => e.hidden)).toBe(true)
})

test('typing and Return reach the app for the item the title belongs to', () => {
  header.set(ticket)
  title().focus()
  expect(header.isEditingTitle).toBe(true)
  title().textContent = 'Review the photographs'
  title().dispatchEvent(new InputEvent('input'))
  const enter = new KeyboardEvent('keydown', { key: 'Enter', cancelable: true })
  title().dispatchEvent(enter)
  expect(enter.defaultPrevented).toBe(true)
  // The app's answer to the typing never overwrites what is being typed.
  header.set({ ...ticket, draft: 'Review the' })
  expect(title().textContent).toBe('Review the photographs')
  title().blur()
  expect(posted).toEqual([
    { type: 'titleFocus', focused: true },
    { type: 'titleInput', item: 'ticket', text: 'Review the photographs' },
    { type: 'titleCommit', item: 'ticket', text: 'Review the photographs', startWriting: true },
    { type: 'titleFocus', focused: false },
  ])
  // Once the title is left, it shows what the app holds.
  header.set({ ...ticket, title: 'Review the photographs' })
  expect(title().textContent).toBe('Review the photographs')
})

test('a title left for another item is not saved as that item, and an emptied one shows its placeholder', () => {
  header.set(ticket)
  title().focus()
  title().textContent = ''
  title().append(document.createElement('br'))
  title().dispatchEvent(new InputEvent('input'))
  expect(title().childNodes.length).toBe(0)
  expect(title().classList.contains('empty')).toBe(true)
  posted = []
  header.set({ ...ticket, item: 'other', title: 'Other' })
  expect(header.isEditingTitle).toBe(false)
  expect(title().textContent).toBe('Other')
  expect(posted).toEqual([{ type: 'titleFocus', focused: false }])
})

test('a pin asks for its menu with its frame, from the mouse or the keyboard', () => {
  header.set(ticket)
  pin('ItemStatusPin').getBoundingClientRect = () => new DOMRect(48, 90, 126, 26)
  const down = new MouseEvent('pointerdown', { button: 0, cancelable: true })
  pin('ItemStatusPin').dispatchEvent(down)
  expect(down.defaultPrevented).toBe(true)
  pin('ItemParentPin').dispatchEvent(new MouseEvent('click', { detail: 0 }))
  pin('ItemParentPin').dispatchEvent(new MouseEvent('click', { detail: 1 }))
  expect(posted).toEqual([
    {
      type: 'headerMenu',
      item: 'ticket',
      menu: 'status',
      rect: [48, 90, 126, 26],
      viewportHeight: window.innerHeight,
    },
    {
      type: 'headerMenu',
      item: 'ticket',
      menu: 'parent',
      rect: [0, 0, 0, 0],
      viewportHeight: window.innerHeight,
    },
  ])
  header.set({
    ...ticket,
    status: { label: 'Status', enabled: false, empty: true, opensMenu: true },
  })
  posted = []
  pin('ItemStatusPin').dispatchEvent(new MouseEvent('pointerdown', { button: 0 }))
  expect(posted).toEqual([])
})

test('Return saves the title once; moving on from it does not save it again, unless typed in since', () => {
  header.set(ticket)
  title().focus()
  title().textContent = 'Review the photographs'
  title().dispatchEvent(new InputEvent('input'))
  title().dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', cancelable: true }))
  title().blur()
  const commits = () => posted.filter((message) => message.type === 'titleCommit')
  expect(commits()).toEqual([
    { type: 'titleCommit', item: 'ticket', text: 'Review the photographs', startWriting: true },
  ])
  // A title the app refused is typed in again, and leaving it then saves it.
  header.set({ ...ticket, draft: 'Review the photographs', titleRejected: true })
  title().focus()
  title().dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', cancelable: true }))
  title().textContent = 'Review the notes'
  title().dispatchEvent(new InputEvent('input'))
  title().blur()
  expect(commits().slice(1)).toEqual([
    { type: 'titleCommit', item: 'ticket', text: 'Review the photographs', startWriting: true },
    { type: 'titleCommit', item: 'ticket', text: 'Review the notes', startWriting: false },
  ])
})

function clipboard(text: string) {
  return { getData: (type: string) => (type === 'text/plain' ? text : ''), types: ['text/plain'] }
}

test('text pasted or dropped into the title comes in on one line, as one change', () => {
  header.set(ticket)
  title().focus()
  const inserted: string[] = []
  document.execCommand = (command: string, _ui?: boolean, value?: string) => {
    if (command === 'insertText' && value != null) inserted.push(value)
    return true
  }
  const broken = [
    'one\ntwo',
    'one\r\ntwo',
    'one\u2028two',
    'one\u2029two',
    'one\u0085two',
    'one\n\n \ntwo',
  ]
  for (const text of broken) {
    const paste = new Event('paste', { cancelable: true })
    Object.defineProperty(paste, 'clipboardData', { value: clipboard(text) })
    title().dispatchEvent(paste)
    expect(paste.defaultPrevented).toBe(true)
  }
  const drop = new Event('drop', { cancelable: true })
  Object.defineProperty(drop, 'dataTransfer', { value: clipboard('dropped\nline') })
  title().dispatchEvent(drop)
  expect(drop.defaultPrevented).toBe(true)
  // Text on one line is left to WebKit.
  const plain = new Event('paste', { cancelable: true })
  Object.defineProperty(plain, 'clipboardData', { value: clipboard('One line') })
  title().dispatchEvent(plain)
  expect(plain.defaultPrevented).toBe(false)
  expect(inserted).toEqual([...broken.map(() => 'one two'), 'dropped line'])
})

test('the Return that confirms an input method conversion leaves the title as it is', () => {
  header.set(ticket)
  title().focus()
  for (const init of [{ isComposing: true }, { keyCode: 229 }]) {
    const event = new KeyboardEvent('keydown', { key: 'Enter', cancelable: true, ...init })
    title().dispatchEvent(event)
    expect(event.defaultPrevented).toBe(false)
  }
  expect(posted.filter((message) => message.type === 'titleCommit')).toEqual([])
})

test('text dropped on the title while it is not being edited is saved when the title is left', () => {
  header.set(ticket)
  document.execCommand = () => true
  const drop = new Event('drop', { cancelable: true })
  Object.defineProperty(drop, 'dataTransfer', { value: clipboard('dropped\nline') })
  title().dispatchEvent(drop)
  expect(header.isEditingTitle).toBe(true)
  title().textContent = 'Review the findings dropped line'
  title().dispatchEvent(new InputEvent('input'))
  title().blur()
  expect(posted.filter((message) => message.type === 'titleCommit')).toEqual([
    {
      type: 'titleCommit',
      item: 'ticket',
      text: 'Review the findings dropped line',
      startWriting: false,
    },
  ])
})

test('a title asked for before its header arrives takes the keyboard with its text selected', () => {
  header.focusTitle('ticket')
  expect(header.isEditingTitle).toBe(false)
  // The header of the item shown before is not the title asked for.
  header.set({ ...ticket, item: 'other', title: 'Other' })
  expect(header.isEditingTitle).toBe(false)
  header.set(ticket)
  expect(header.isEditingTitle).toBe(true)
  expect(document.getSelection()?.toString()).toBe('Review the findings')
  // The request is used once.
  title().blur()
  header.set(ticket)
  expect(header.isEditingTitle).toBe(false)
})

test('a title that cannot be edited, or a request the keyboard has since left, takes nothing', () => {
  header.focusTitle('ticket')
  header.set({ ...ticket, editable: false })
  expect(header.isEditingTitle).toBe(false)
  header.cancelTitleFocus()
  header.set(ticket)
  expect(header.isEditingTitle).toBe(false)
})

const rows = (count: number): HeaderModel['properties'] =>
  Array.from({ length: count }, (_, index) => ({
    id: `field-${index}`,
    label: `Field ${index}`,
    symbol: 'text.alignleft',
    kind: 'text' as const,
    text: `Value ${index}`,
  }))

test('the byline reads the type, the source and the date', () => {
  header.set(ticket)
  expect(root.querySelector('.item-byline')!.textContent).toBe('Taskworkbench-folderSaturday')
  header.set({ ...ticket, byline: { source: null, date: 'Today' } })
  expect(root.querySelector('.item-byline')!.textContent).toBe('TaskToday')
})

test('the property block reads as label and value pairs, each drawn by its kind', () => {
  header.set({
    ...ticket,
    foldAfter: 10,
    properties: [
      { id: 'status', label: 'Status', symbol: 'circle.dotted', kind: 'status' },
      { id: 'child-of', label: 'Epic', symbol: 'square.stack', kind: 'parent' },
      {
        id: 'blocks',
        label: 'Blocks',
        symbol: 'link',
        kind: 'items',
        items: [{ title: 'Ship it', item: 'other' }],
      },
      { id: '#tags', label: 'Tags', symbol: 'tag', kind: 'tags', texts: ['mapp', 'storage'] },
      { id: 'url', label: 'Url', symbol: 'globe', kind: 'url', text: 'https://example.com/a' },
      { id: 'mail', label: 'Email', symbol: 'envelope', kind: 'email', text: 'a@example.com' },
      { id: 'done', label: 'Done', symbol: 'text.alignleft', kind: 'text', text: 'Yes' },
    ],
  })
  const pairs = [...root.querySelectorAll('.item-props .item-prop')]
  expect(pairs.map((pair) => pair.querySelector('dt')!.textContent)).toEqual([
    'Status',
    'Epic',
    'Blocks',
    'Tags',
    'Url',
    'Email',
    'Done',
  ])
  expect(pairs[0]!.querySelector('dd #ItemStatusPin')).not.toBeNull()
  expect(pairs[1]!.querySelector('dd #ItemParentPin')).not.toBeNull()
  expect([...pairs[3]!.querySelectorAll('.item-chip')].map((chip) => chip.textContent)).toEqual([
    'mapp',
    'storage',
  ])
  expect(pairs[6]!.querySelector('dd')!.textContent).toBe('Yes')
  posted = []
  pairs[2]!.querySelector<HTMLElement>('.item-link')!.click()
  pairs[4]!.querySelector<HTMLElement>('.item-link')!.click()
  pairs[5]!.querySelector<HTMLElement>('.item-link')!.click()
  expect(posted).toEqual([
    { type: 'openItem', item: 'other' },
    { type: 'openLink', href: 'https://example.com/a' },
    { type: 'openLink', href: 'mailto:a@example.com' },
  ])
})

test('a URL that is not web is shown as text, not as a link', () => {
  header.set({
    ...ticket,
    properties: [
      { id: 'u', label: 'Url', symbol: 'globe', kind: 'url', text: 'javascript:alert(1)' },
    ],
  })
  expect(root.querySelector('.item-link')).toBeNull()
  expect(root.querySelector('.item-prop dd')!.textContent).toBe('javascript:alert(1)')
})

test('rows past the fold wait behind a button that expands them in place', () => {
  header.set({ ...ticket, properties: rows(9), showMore: 'Show 3 More' })
  expect(root.querySelectorAll('.item-prop')).toHaveLength(6)
  const more = root.querySelector<HTMLButtonElement>('.item-props + .item-more')!
  expect(more.hidden).toBe(false)
  expect(more.textContent).toBe('Show 3 More')
  more.click()
  expect(root.querySelectorAll('.item-prop')).toHaveLength(9)
  expect(more.hidden).toBe(true)
  // Another item starts folded again.
  header.set({ ...ticket, item: 'other', properties: rows(9), showMore: 'Show 3 More' })
  expect(root.querySelectorAll('.item-prop')).toHaveLength(6)
})

test('linked items are folded, then listed with their type and date, and open on a click', () => {
  const linked = [
    { item: 'a', title: 'Wiring', symbol: 'calendar', type: 'Session', date: '2 Oct' },
    { item: 'b', title: 'Decision', symbol: 'doc', type: 'Decision', date: '24 Oct' },
  ]
  header.set({ ...ticket, linked })
  const toggle = root.querySelector<HTMLButtonElement>('.item-linked-toggle')!
  expect(toggle.textContent).toBe('Linked From2')
  expect(toggle.getAttribute('aria-expanded')).toBe('false')
  expect(root.querySelector<HTMLElement>('.item-linked-list')!.hidden).toBe(true)
  toggle.click()
  expect(toggle.getAttribute('aria-expanded')).toBe('true')
  const rowsShown = [...root.querySelectorAll('.item-linked-row')]
  expect(rowsShown.map((row) => row.querySelector('.item-linked-name')!.textContent)).toEqual([
    'Wiring',
    'Decision',
  ])
  expect(rowsShown[0]!.querySelector('.item-linked-detail')!.textContent).toBe('Session2 Oct')
  posted = []
  rowsShown[1]!.querySelector<HTMLElement>('button')!.click()
  expect(posted).toEqual([{ type: 'openItem', item: 'b' }])
})

test('an item nothing links to has no Linked From section', () => {
  header.set(ticket)
  expect(root.querySelector<HTMLElement>('.item-linked')!.hidden).toBe(true)
})
