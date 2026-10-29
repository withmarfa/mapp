import { afterEach, beforeEach, expect, test } from 'vitest'
import type { EditorMessage } from '../src/bridge'
import { ItemHeader, type HeaderModel } from '../src/header'

let posted: EditorMessage[] = []
let root: HTMLElement
let footer: HTMLElement
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
  kind: 'general',
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
  contents: [],
  linked: [],
  linkedFoldAfter: 20,
  showsText: true,
  showMore: 'Show 0 More',
  showMoreContents: 'Show 0 More',
  showMoreLinked: 'Show 0 More',
  propertyRejected: false,
  parentRejected: false,
  interfaceTextSize: 13,
}

beforeEach(() => {
  posted = []
  window.webkit = { messageHandlers: { host: { postMessage: (message) => posted.push(message) } } }
  root = document.createElement('header')
  footer = document.createElement('footer')
  document.body.append(root, footer)
  header = new ItemHeader(root, footer, { untitled: 'Sans titre' })
})

afterEach(() => {
  root.remove()
  footer.remove()
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
  // The same button folds them again.
  expect(more.hidden).toBe(false)
  expect(more.textContent).toBe('Show Less')
  more.click()
  expect(root.querySelectorAll('.item-prop')).toHaveLength(6)
  expect(more.textContent).toBe('Show 3 More')
  more.click()
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
  const toggle = footer.querySelector<HTMLButtonElement>('.item-linked-from .item-linked-toggle')!
  expect(toggle.textContent).toBe('Linked From2')
  expect(toggle.getAttribute('aria-expanded')).toBe('false')
  expect(footer.querySelector<HTMLElement>('.item-linked-from .item-linked-list')!.hidden).toBe(
    true,
  )
  toggle.click()
  expect(toggle.getAttribute('aria-expanded')).toBe('true')
  const rowsShown = [...footer.querySelectorAll('.item-linked-from .item-linked-row')]
  expect(rowsShown.map((row) => row.querySelector('.item-linked-name')!.textContent)).toEqual([
    'Wiring',
    'Decision',
  ])
  expect(rowsShown[0]!.querySelector('.item-linked-detail')!.textContent).toBe('Session2 Oct')
  posted = []
  rowsShown[1]!.querySelector<HTMLElement>('button')!.click()
  expect(posted).toEqual([{ type: 'openItem', item: 'b' }])
})

test('a long list of linked items expands, and folds again', () => {
  const linked = Array.from({ length: 5 }, (_, index) => ({
    item: `i${index}`,
    title: `Item ${index}`,
    symbol: 'doc',
    type: 'Note',
    date: 'Today',
  }))
  header.set({ ...ticket, linked, linkedFoldAfter: 3, showMoreLinked: 'Show 2 More' })
  const section = footer.querySelector<HTMLElement>('.item-linked-from')!
  section.querySelector<HTMLButtonElement>('.item-linked-toggle')!.click()
  expect(section.querySelectorAll('.item-linked-row')).toHaveLength(3)
  const more = section.querySelector<HTMLButtonElement>('.item-more')!
  expect(more.textContent).toBe('Show 2 More')
  more.click()
  expect(section.querySelectorAll('.item-linked-row')).toHaveLength(5)
  expect(more.textContent).toBe('Show Less')
  more.click()
  expect(section.querySelectorAll('.item-linked-row')).toHaveLength(3)
})

test('the byline keeps one dot between its parts however often it is drawn again', () => {
  const dots = () => root.querySelectorAll('.item-byline-dot').length
  header.set({ ...ticket, byline: { source: 'GitHub', date: 'Today' } })
  const first = dots()
  expect(first).toBe(2)
  header.set({ ...ticket, byline: { source: 'GitHub', date: 'Yesterday' } })
  header.set({ ...ticket, byline: { source: 'GitHub', date: 'Today' } })
  expect(dots()).toBe(first)
})

test('a collection lists what it holds under its text, open, apart from what links to it', () => {
  const member = { item: 'f', title: 'README', symbol: 'doc', type: 'GitHub File', date: 'Today' }
  const mention = { item: 'n', title: 'Notes', symbol: 'doc', type: 'Note', date: 'Today' }
  header.set({ ...ticket, contents: [member], linked: [mention], showsText: false })
  const contents = footer.querySelector<HTMLElement>('.item-contents')!
  expect(contents.querySelector('.item-linked-title')!.textContent).toBe('Contents')
  expect(contents.querySelector<HTMLElement>('.item-linked-list')!.hidden).toBe(false)
  expect(contents.querySelector('.item-linked-name')!.textContent).toBe('README')
  expect(footer.querySelector<HTMLElement>('.item-linked-from .item-linked-list')!.hidden).toBe(
    true,
  )
  expect(document.body.dataset.text).toBe('none')
  header.set({ ...ticket, item: 'other' })
  expect(contents.hidden).toBe(true)
  expect(document.body.dataset.text).toBe('shown')
})

test('an item nothing links to has no Linked From section', () => {
  header.set(ticket)
  expect(footer.querySelector<HTMLElement>('.item-linked-from')!.hidden).toBe(true)
})

const phone = { id: 'tel', label: 'Phone', symbol: 'phone', kind: 'phone' as const }

test('an event shows its calendar block, its time and its status together', () => {
  header.set({
    ...ticket,
    kind: 'event',
    type: 'Event',
    properties: [],
    event: {
      month: 'OCT',
      day: '29',
      weekday: 'Thursday',
      time: '10:00 to 11:00',
      zone: 'London time (BST)',
      relative: 'in 2 days',
    },
  })
  const when = root.querySelector<HTMLElement>('.item-when')!
  expect(when.hidden).toBe(false)
  expect(when.querySelector('.item-calendar-month')!.textContent).toBe('OCT')
  expect(when.querySelector('.item-calendar-day')!.textContent).toBe('29')
  expect(when.querySelector('.item-when-time')!.textContent).toBe('10:00 to 11:00')
  expect(when.querySelector('.item-when-detail')!.textContent).toBe(
    'ThursdayLondon time (BST)in 2 days',
  )
  expect(when.contains(pin('ItemStatusPin'))).toBe(true)
  expect(root.dataset.kind).toBe('event')

  header.set({ ...ticket, kind: 'general' })
  expect(when.hidden).toBe(true)
  expect(when.children.length).toBe(0)
})

test('a person shows initials or a picture, a subtitle, and a timeline that starts open', () => {
  const person = {
    ...ticket,
    item: 'ruth',
    kind: 'person' as const,
    type: 'Person',
    subtitle: 'Editor, Okonjo Press',
    person: { initials: 'RO' },
    linked: [{ item: 'note', title: 'Lunch', symbol: 'doc', type: 'Note', date: 'Today' }],
  }
  header.set(person)
  expect(root.querySelector<HTMLElement>('.item-avatar')!.textContent).toBe('RO')
  expect(root.querySelector<HTMLElement>('.item-subtitle')!.textContent).toBe(
    'Editor, Okonjo Press',
  )
  expect(footer.querySelector('.item-linked-from .item-linked-title')!.textContent).toBe('Timeline')
  expect(footer.querySelector<HTMLElement>('.item-linked-from .item-linked-list')!.hidden).toBe(
    false,
  )

  header.set({
    ...person,
    item: 'ruth2',
    person: { initials: 'RO', photo: 'data:image/png;base64,AA==' },
  })
  expect(root.querySelector('.item-avatar img')!.getAttribute('src')).toBe(
    'data:image/png;base64,AA==',
  )

  header.set({ ...ticket, item: 'plain', linked: person.linked })
  expect(root.querySelector<HTMLElement>('.item-avatar')!.hidden).toBe(true)
  expect(footer.querySelector('.item-linked-from .item-linked-title')!.textContent).toBe(
    'Linked From',
  )
  expect(footer.querySelector<HTMLElement>('.item-linked-from .item-linked-list')!.hidden).toBe(
    true,
  )
})

test('a phone number is a link that dials its digits', () => {
  header.set({
    ...ticket,
    kind: 'person',
    person: { initials: 'RO' },
    properties: [{ ...phone, text: '+44 (0)20 7946-0000' }],
  })
  const link = root.querySelector<HTMLAnchorElement>('.item-prop-value a')!
  expect(link.textContent).toBe('+44 (0)20 7946-0000')
  expect(link.getAttribute('href')).toBe('tel:+4402079460000')
  link.click()
  expect(posted).toContainEqual({ type: 'openLink', href: link.getAttribute('href') })

  header.set({ ...ticket, properties: [{ ...phone, text: 'ask Ruth' }] })
  expect(root.querySelector('.item-prop-value a')).toBeNull()
})

test('a page for reading puts the source and reading time in the byline, with no type', () => {
  header.set({
    ...ticket,
    kind: 'reading',
    type: null,
    subtitle: 'Why startups fail',
    byline: { source: 'Y Combinator Blog', date: '2 Oct 2025', detail: '6 min read' },
  })
  const parts = [...root.querySelectorAll('.item-byline-part')].map((part) => part.textContent)
  expect(parts).toEqual(['Y Combinator Blog', '2 Oct 2025', '6 min read'])
  // No dot leads the line when the type is not there.
  expect(root.querySelector('.item-byline')!.children[1]!.className).toBe('item-byline-part')
  expect(root.querySelector('.item-subtitle')!.textContent).toBe('Why startups fail')
  expect(document.body.dataset.header).toBe('reading')
})

test('the byline draws the icon of the item type, and none for a type with no icon', () => {
  const drawn = { url: 'data:image/png;base64,AAAA', width: 13, height: 13 }
  const icons = { parent: drawn, plus: drawn, indicator: drawn, symbols: { 'type:globe': drawn } }
  const node = () => pin('ItemTypePin').querySelector<HTMLElement>('.item-icon-type')!
  header.setIcons(icons)
  header.set({ ...ticket, icon: 'type:globe' })
  expect(node().hidden).toBe(false)
  expect(node().style.width).toBe('13px')
  header.set({ ...ticket, icon: 'type:' })
  expect(node().hidden).toBe(true)
})

test('an item titled by its text draws no title, and one with a title of its own does', () => {
  header.set({ ...ticket, showsTitle: false, editable: false })
  expect(root.querySelector<HTMLElement>('.item-title')!.hidden).toBe(true)
  expect(root.dataset.title).toBe('derived')
  expect(root.querySelector<HTMLElement>('.item-byline')).not.toBeNull()
  header.set(ticket)
  expect(root.querySelector<HTMLElement>('.item-title')!.hidden).toBe(false)
  expect(root.dataset.title).toBe('own')
})

test('a title read from the text still ends where the header ends, so the toolbar names the item as it scrolls', () => {
  header.set({ ...ticket, showsTitle: false, editable: false })
  expect(header.bottom).toBe(root.offsetTop + root.offsetHeight)
  expect(header.isEditingTitle).toBe(false)
})
