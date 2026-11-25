import { afterEach, beforeEach, expect, test } from 'vitest'
import type { EditorMessage } from '../src/bridge'
import { ItemHeader, type HeaderModel } from '../src/header'

let posted: EditorMessage[] = []
let root: HTMLElement
let footer: HTMLElement
let header: ItemHeader

const ticket: HeaderModel = {
  item: 'ticket',
  focused: false,
  title: 'Review the findings',
  draft: null,
  titleRejected: false,
  titleRefusal:
    'The title could not be saved. Use a unique file name without slashes or line breaks.',
  editable: true,
  kicker: {
    type: 'Task',
    icon: 'square.stack',
    tone: 'blue',
    changesType: true,
    flags: [],
    spoken: 'Task',
  },
  status: {
    label: 'In Progress',
    enabled: true,
    mark: { symbol: 'circle.lefthalf.filled', tint: 'blue' },
  },
  parent: { label: 'Field Research', enabled: true },
  pins: [],
  rows: [
    { id: 'status', label: 'Status', symbol: 'circle.dotted', kind: 'status' },
    { id: 'child-of', label: 'Epic', symbol: 'square.stack', kind: 'parent' },
  ],
  linked: [],
  linkedFoldAfter: 20,
  showsText: true,
  showMore: 'Show 0 More',
  showMoreLinked: 'Show 0 More',
  interfaceTextSize: 13,
  titleLines: 2,
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

const icon = { url: 'data:image/png;base64,AAAA', width: 13, height: 13 }
const icons = {
  indicator: icon,
  symbols: { 'square.stack': icon },
}

const title = () => root.querySelector<HTMLElement>('#ItemPageTitle')!
const pin = (id: string) => root.querySelector<HTMLElement>('#' + id)!
const label = (id: string) => pin(id).querySelector('.item-pin-label')!.textContent
const pinned = (id: string) => root.querySelector<HTMLElement>(`[data-pin="${id}"]`)!

test('the header shows the item it is given, and nothing before', () => {
  expect(root.hidden).toBe(true)
  header.set(ticket)
  expect(root.hidden).toBe(false)
  expect(title().textContent).toBe('Review the findings')
  expect(title().getAttribute('contenteditable')).toBe('plaintext-only')
  expect(title().getAttribute('aria-label')).toBe('Title')
  expect(title().dataset.placeholder).toBe('Sans titre')
  expect(label('ItemStatusPin')).toBe('In Progress')
  expect(pin('ItemStatusPin').getAttribute('aria-label')).toBe('Status')
  expect(label('ItemParentPin')).toBe('Field Research')
  expect(root.querySelector<HTMLElement>('.item-title-error')!.hidden).toBe(true)

  header.set({ ...ticket, status: null, parent: null, editable: false, draft: 'Draft' })
  expect(title().textContent).toBe('Draft')
  expect(title().getAttribute('contenteditable')).toBe('false')
  expect(pin('ItemStatusPin').hidden).toBe(true)
  expect(pin('ItemParentPin').hidden).toBe(true)

  header.set(null)
  expect(root.hidden).toBe(true)
})

test('a refused title shows why and offers to discard the draft', () => {
  header.set({
    ...ticket,
    draft: 'A/B',
    titleRejected: true,
  })
  const error = root.querySelector<HTMLElement>('.item-title-error')!
  expect(error.hidden).toBe(false)
  expect(error.textContent).toContain('The title could not be saved.')
  error.querySelector('button')!.click()
  expect(posted).toEqual([{ type: 'titleDiscard', item: 'ticket' }])
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
    status: { label: 'Status', enabled: false },
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

const rows = (count: number): HeaderModel['rows'] =>
  Array.from({ length: count }, (_, index) => ({
    id: `field-${index}`,
    label: `Field ${index}`,
    symbol: 'text.alignleft',
    kind: 'text' as const,
    text: `Value ${index}`,
  }))

test('the pins follow the title with nothing drawn between them', () => {
  header.set({ ...ticket, pins: [pinRows[1]!] })
  const order = [...root.children].map((child) => child.className)
  expect(order.indexOf('item-pins')).toBe(order.indexOf('item-title') + 2)
  expect(root.querySelector<HTMLElement>('.item-pins')!.hidden).toBe(false)
})

test('the property block reads as label and value pairs, each drawn by its kind', () => {
  header.set({
    ...ticket,
    rows: [
      { id: 'status', label: 'Status', symbol: 'circle.dotted', kind: 'status' },
      { id: 'child-of', label: 'Epic', symbol: 'square.stack', kind: 'parent' },
      {
        id: 'blocks',
        label: 'Blocks',
        symbol: 'link',
        kind: 'items',
        items: [
          { title: 'Ship it', item: 'other', symbol: 'square.stack', kind: 'link', tone: 'blue' },
        ],
      },
      { id: '#tags', label: 'Tags', symbol: 'tag', kind: 'tags', texts: ['marfa-mac', 'storage'] },
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
    'marfa-mac',
    'storage',
  ])
  expect(pairs[6]!.querySelector('dd')!.textContent).toBe('Yes')
  posted = []
  pairs[2]!.querySelector<HTMLElement>('.item-chip')!.click()
  pairs[4]!.querySelector<HTMLElement>('.item-link')!.click()
  pairs[5]!.querySelector<HTMLElement>('.item-link')!.click()
  expect(posted).toEqual([
    { type: 'openItem', item: 'other' },
    { type: 'openLink', href: 'https://example.com/a' },
    { type: 'openLink', href: 'mailto:a@example.com' },
  ])
})

test('an item a row links to is a chip in its own tone, with the icon of its type before the title', () => {
  header.setIcons(icons)
  header.set({
    ...ticket,
    rows: [
      {
        id: 'blocks',
        label: 'Blocks',
        symbol: 'link',
        kind: 'items',
        items: [
          { title: 'Ship it', item: 'other', symbol: 'square.stack', kind: 'link', tone: 'blue' },
        ],
      },
    ],
  })
  const chip = root.querySelector<HTMLElement>('.item-prop-value .item-chip')!
  expect(chip.dataset.kind).toBe('link')
  expect(chip.style.getPropertyValue('--tone')).toBe('var(--tone-blue)')
  expect(chip.querySelector('.item-chip-mark')).not.toBeNull()
  expect(chip.querySelector('.item-chip-text')!.textContent).toBe('Ship it')
  posted = []
  chip.click()
  expect(posted).toEqual([{ type: 'openItem', item: 'other' }])
})

test('a value the item does not have yet reads Empty and opens its editor', () => {
  header.set({
    ...ticket,
    rows: [{ id: 'due', label: 'Due', symbol: 'calendar', kind: 'empty', editable: true }],
    pins: [{ id: 'due', label: 'Due', symbol: 'calendar', kind: 'empty', editable: true }],
  })
  const text = root.querySelector<HTMLElement>('.item-props .item-prop-value .item-empty')!
  expect(text.textContent).toBe('Empty')
  expect(root.querySelector('.item-chip.empty, .item-icon-plus')).toBeNull()
  const value = root.querySelector<HTMLElement>('.item-prop-value')!
  expect(value.getAttribute('aria-label')).toBe('Due: Empty')
  expect(root.querySelector('.item-pin-value .item-empty')!.textContent).toBe('Empty')
  text.click()
  expect(posted.map((message) => message.type)).toEqual(['editValue'])
  expect(posted[0]).toMatchObject({ item: 'ticket', row: 'due' })
})

test('a label opens the field menu, and only a value that is not a link opens the editor', () => {
  header.set({
    ...ticket,
    rows: [
      { id: 'due', label: 'Due', symbol: 'calendar', kind: 'empty', editable: true },
      {
        id: 'source',
        label: 'Source',
        symbol: 'link',
        kind: 'text',
        text: 'Mail',
        editable: false,
      },
    ],
  })
  const labels = root.querySelectorAll<HTMLElement>('.item-prop-label')
  labels[0]!.click()
  labels[1]!.click()
  expect(posted.map((message) => message.type)).toEqual(['fieldMenu', 'fieldMenu'])
  expect(posted[0]!).toMatchObject({ item: 'ticket', row: 'due', editsValue: false })
  expect(posted[1]!).toMatchObject({ row: 'source', editsValue: false })
  const values = root.querySelectorAll<HTMLElement>('.item-prop-value')
  expect(values[0]!.getAttribute('role')).toBe('button')
  expect(values[1]!.getAttribute('role'), 'a value nothing edits is no button').toBeNull()
})

test('the app is told where the value its editor is open under has moved to, once for each move', () => {
  header.set({
    ...ticket,
    rows: [
      { id: 'due', label: 'Due', symbol: 'calendar', kind: 'empty', text: 'Due', editable: true },
    ],
  })
  const value = root.querySelector<HTMLElement>('.item-prop-value')!
  let frame = { left: 10, top: 20, width: 100, height: 24, right: 110, bottom: 44 }
  value.getBoundingClientRect = () => frame as DOMRect
  window.dispatchEvent(new Event('resize'))
  expect(posted, 'nothing is open, so nothing is told').toEqual([])
  root.querySelector<HTMLElement>('.item-empty')!.click()
  expect(posted.map((message) => message.type)).toEqual(['editValue'])
  window.dispatchEvent(new Event('resize'))
  expect(posted, 'it has not moved').toHaveLength(1)
  frame = { left: 10, top: 60, width: 100, height: 24, right: 110, bottom: 84 }
  window.dispatchEvent(new Event('resize'))
  window.dispatchEvent(new Event('resize'))
  expect(posted.map((message) => message.type)).toEqual(['editValue', 'valueMoved'])
  expect(posted[1]).toMatchObject({ item: 'ticket', row: 'due', rect: [10, 60, 100, 24] })
})

test('each kind of value has its own chip, and its text is never read as markup', () => {
  header.set({
    ...ticket,
    rows: [
      {
        id: 'priority',
        label: 'Priority',
        symbol: 'list.bullet',
        kind: 'options',
        options: [
          { label: 'High', tone: 'pink' },
          { label: '<img src=x onerror=alert(1)>', tone: 'blue' },
        ],
      },
      { id: '#tags', label: 'Tags', symbol: 'tag', kind: 'tags', texts: ['a', '<b>b</b>'] },
    ],
  })
  const chips = [...root.querySelectorAll<HTMLElement>('.item-prop-value .item-chip')]
  expect(chips.map((chip) => chip.dataset.kind)).toEqual(['option', 'option', 'tag', 'tag'])
  expect(chips[0]!.querySelector('.item-chip-dot')).not.toBeNull()
  expect(chips[0]!.style.getPropertyValue('--tone')).toBe('var(--tone-pink)')
  expect(chips[2]!.querySelector('.item-chip-dot')).toBeNull()
  expect(chips[2]!.querySelector('.item-chip-hash')!.getAttribute('aria-hidden')).toBe('true')
  expect(chips[2]!.querySelector('.item-chip-hash')!.textContent).toBe('')
  expect(chips[1]!.querySelector('.item-chip-text')!.textContent).toBe(
    '<img src=x onerror=alert(1)>',
  )
  expect(root.querySelector('.item-prop-value img')).toBeNull()
  expect(root.querySelector('.item-prop-value b')).toBeNull()
})

test('a person is initials in a circle and a name, and a name with nothing in it has no circle', () => {
  header.set({
    ...ticket,
    rows: [
      {
        id: 'assignee',
        label: 'Assignee',
        symbol: 'link',
        kind: 'items',
        items: [
          { title: 'Mira Castell', item: 'mira', symbol: 'person', kind: 'person', initials: 'MC' },
          { title: '   ', item: 'blank', symbol: 'person', kind: 'person' },
        ],
      },
    ],
  })
  const people = [...root.querySelectorAll<HTMLElement>('.item-prop-value .item-person')]
  expect(people).toHaveLength(2)
  expect(people[0]!.querySelector('.item-person-initials')!.textContent).toBe('MC')
  expect(people[0]!.querySelector('.item-chip-text')!.textContent).toBe('Mira Castell')
  expect(people[1]!.querySelector('.item-person-initials')).toBeNull()
  expect(people[0]!.classList.contains('item-chip')).toBe(false)
  posted = []
  people[0]!.click()
  expect(posted).toEqual([{ type: 'openItem', item: 'mira' }])
})

test('the people a list names are all drawn as person chips that open nothing, and a name is text only', () => {
  const twenty = Array.from({ length: 20 }, (_, index) => ({
    title: `Person ${index}`,
    initials: `P${index}`.slice(0, 2),
  }))
  header.set({
    ...ticket,
    rows: [
      {
        id: 'assignees',
        label: 'Assignees',
        symbol: 'person.2',
        kind: 'people',
        people: [
          { title: 'Mira Castell', initials: 'MC' },
          { title: 'r@example.com', initials: 'R' },
          { title: '<img src=x onerror=alert(1)><b>Bold</b>', initials: '<I' },
          ...twenty,
        ],
      },
    ],
  })
  const people = [...root.querySelectorAll<HTMLElement>('.item-prop-value .item-person')]
  expect(people).toHaveLength(23)
  expect(people[0]!.querySelector('.item-person-initials')!.textContent).toBe('MC')
  expect(people[1]!.querySelector('.item-chip-text')!.textContent).toBe('r@example.com')
  expect(people[2]!.querySelector('.item-chip-text')!.textContent).toBe(
    '<img src=x onerror=alert(1)><b>Bold</b>',
  )
  expect(root.querySelector('.item-prop-value img')).toBeNull()
  expect(root.querySelector('.item-prop-value b')).toBeNull()
  expect(root.querySelector('.item-prop-value button')).toBeNull()
  posted = []
  people[0]!.click()
  expect(posted).toEqual([])
})

test('the looks the app sent are set on the header for the appearance the page is in', () => {
  header.set({
    ...ticket,
    pins: [pinRows[1]!],
    interfaceTextSize: 26,
    chips: {
      light: { '--chip-height': '22px', '--tone-orange': 'rgb(1, 2, 3)' },
      dark: { '--chip-height': '30px', '--tone-orange': 'rgb(4, 5, 6)' },
    },
  })
  expect(root.style.getPropertyValue('--chip-height')).toBe('22px')
  expect(root.style.getPropertyValue('--tone-orange')).toBe('rgb(1, 2, 3)')
  expect(root.style.getPropertyValue('--chip-scale')).toBe('2')
  expect(footer.style.getPropertyValue('--chip-height')).toBe('22px')
})

test('a parent chip takes the icon and tone of its own type, and a read-only status has no menu to open', () => {
  header.setIcons(icons)
  header.set({
    ...ticket,
    status: { ...ticket.status!, enabled: false },
    parent: {
      label: 'Field Research',
      enabled: true,
      icon: 'square.stack',
      tone: 'teal',
    },
  })
  expect(pin('ItemParentPin').dataset.kind).toBe('link')
  expect(pin('ItemParentPin').style.getPropertyValue('--tone')).toBe('var(--tone-teal)')
  expect(pin('ItemParentPin').querySelector<HTMLElement>('.item-icon-parent')!.hidden).toBe(false)
  expect((pin('ItemStatusPin') as HTMLButtonElement).disabled).toBe(true)
  expect(pin('ItemStatusPin').dataset.kind).toBe('status')
  pin('ItemParentPin').dispatchEvent(new MouseEvent('pointerdown', { button: 0 }))
  expect(posted.map((message) => message.type)).toEqual(['headerMenu'])
})

test('the Linked From heading is a row the menu can name', () => {
  const mention = { item: 'm', title: 'Mention', symbol: 'link', type: 'Note', date: 'Today' }
  header.set({ ...ticket, linked: [mention] })
  expect(header.hasFooterItems).toBe(true)
  const toggle = footer.querySelector('.item-linked-from .item-linked-toggle')!
  expect(header.rowAt(toggle)).toEqual({ item: 'ticket', row: '#linked' })
})

test('a URL that is not web is shown as text, not as a link', () => {
  header.set({
    ...ticket,
    rows: [{ id: 'u', label: 'Url', symbol: 'globe', kind: 'url', text: 'javascript:alert(1)' }],
  })
  expect(root.querySelector('.item-link')).toBeNull()
  expect(root.querySelector('.item-prop dd')!.textContent).toBe('javascript:alert(1)')
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

test('the title is told how many lines to show', () => {
  header.set({ ...ticket, titleLines: 4 })
  expect(root.style.getPropertyValue('--title-lines')).toBe('4')
})

test('an item nothing links to has no Linked From section', () => {
  header.set(ticket)
  expect(footer.querySelector<HTMLElement>('.item-linked-from')!.hidden).toBe(true)
})

const phone = { id: 'tel', label: 'Phone', symbol: 'phone', kind: 'phone' as const }

test('a phone number is a link that dials its digits', () => {
  header.set({
    ...ticket,
    rows: [{ ...phone, text: '+44 (0)20 7946-0000' }],
  })
  const link = root.querySelector<HTMLAnchorElement>('.item-prop-value a')!
  expect(link.textContent).toBe('+44 (0)20 7946-0000')
  expect(link.getAttribute('href')).toBe('tel:+4402079460000')
  link.click()
  expect(posted).toContainEqual({ type: 'openLink', href: link.getAttribute('href') })

  header.set({ ...ticket, rows: [{ ...phone, text: 'ask Ruth' }] })
  expect(root.querySelector('.item-prop-value a')).toBeNull()
})

test('a text value is drawn in a span of its own, so it can shrink to its column and wrap', () => {
  header.set({
    ...ticket,
    rows: [{ id: 'note', label: 'Note', symbol: 'text.alignleft', kind: 'text', text: 'plain' }],
  })
  const value = root.querySelector('.item-prop-value')!
  expect(value.children).toHaveLength(1)
  expect(value.children[0]!.tagName).toBe('SPAN')
  expect(value.textContent).toBe('plain')
})

test('rows first drawn where the page has no width are drawn again once it has one', () => {
  const rows: HeaderModel['rows'] = [
    { id: 'note', label: 'Note', symbol: 'text.alignleft', kind: 'text', text: 'plain' },
  ]
  const width = window.innerWidth
  try {
    window.innerWidth = 0
    const narrow = new ItemHeader(
      document.createElement('header'),
      document.createElement('footer'),
    )
    narrow.set({ ...ticket, rows })
    const row = narrow.root.querySelector('.item-prop')!
    window.dispatchEvent(new Event('resize'))
    expect(narrow.root.querySelector('.item-prop')).toBe(row)

    window.innerWidth = 700
    window.dispatchEvent(new Event('resize'))
    const drawn = narrow.root.querySelector('.item-prop')!
    expect(drawn).not.toBe(row)
    expect(drawn.textContent).toContain('plain')

    window.dispatchEvent(new Event('resize'))
    expect(narrow.root.querySelector('.item-prop')).toBe(drawn)
  } finally {
    window.innerWidth = width
  }
})

test('an item titled by its text draws no title, and one with a title of its own does', () => {
  header.set({ ...ticket, showsTitle: false, editable: false })
  expect(root.querySelector<HTMLElement>('.item-title')!.hidden).toBe(true)
  expect(root.dataset.title).toBe('derived')
  header.set(ticket)
  expect(root.querySelector<HTMLElement>('.item-title')!.hidden).toBe(false)
  expect(root.dataset.title).toBe('own')
})

test('a title read from the text still ends where the header ends, so the toolbar names the item as it scrolls', () => {
  header.set({ ...ticket, showsTitle: false, editable: false })
  expect(header.bottom).toBe(root.offsetTop + root.offsetHeight)
  expect(header.isEditingTitle).toBe(false)
})

const pinRows: HeaderModel['pins'] = [
  { id: 'due', label: 'Due', symbol: 'calendar', kind: 'date', text: '12 Dec' },
  { id: 'status', label: 'Status', symbol: 'circle.dotted', kind: 'status' },
  {
    id: 'child-of',
    label: 'Epic',
    symbol: 'square.stack',
    kind: 'items',
    items: [{ title: 'Field Research', item: 'parent', symbol: 'square.stack', kind: 'link' }],
  },
  { id: 'done', label: 'Done', symbol: 'calendar', kind: 'date', text: 'Today' },
]

test('pins are drawn in the order sent, each with its key above its value and no symbol on the key', () => {
  header.setIcons(icons)
  header.set({ ...ticket, pins: pinRows, rows: [] })
  const entries = [...root.querySelectorAll<HTMLElement>('.item-pin-item')]
  expect(entries.map((entry) => entry.dataset.pin)).toEqual(['due', 'status', 'child-of', 'done'])
  expect(entries.map((entry) => entry.querySelector('dt')!.textContent)).toEqual([
    'Due',
    'Status',
    'Epic',
    'Done',
  ])
  expect(root.querySelector('.item-pin-key .item-glyph')).not.toBeNull()
  expect(entries[3]!.querySelector('dd')!.textContent).toBe('Today')
  expect(entries[3]!.querySelector('dd')!.title).toBe('Today')
  expect(entries[2]!.querySelector('dt')!.title).toBe('Epic')
  // The key is above the value in the document, which the stylesheet stacks.
  expect(entries[3]!.firstElementChild!.tagName).toBe('DT')
})

test('a pinned status is the status button itself, with its menu, and a read-only one has none to open', () => {
  header.set({ ...ticket, pins: pinRows, rows: [] })
  expect(pinned('status').contains(pin('ItemStatusPin'))).toBe(true)
  pin('ItemStatusPin').dispatchEvent(new MouseEvent('pointerdown', { button: 0 }))
  expect(posted.map((message) => message.type)).toEqual(['headerMenu'])
  posted = []
  header.set({
    ...ticket,
    pins: pinRows,
    rows: [],
    status: { ...ticket.status!, enabled: false },
  })
  expect((pin('ItemStatusPin') as HTMLButtonElement).disabled).toBe(true)
  pin('ItemStatusPin').dispatchEvent(new MouseEvent('pointerdown', { button: 0 }))
  expect(posted).toEqual([])
})

test('a pinned parent is a chip that opens it, and a pinned value is read only', () => {
  header.set({ ...ticket, pins: pinRows, rows: [] })
  posted = []
  pinned('child-of').querySelector<HTMLElement>('.item-chip')!.click()
  expect(posted).toEqual([{ type: 'openItem', item: 'parent' }])
  posted = []
  pinned('done')
    .querySelector('dd')!
    .dispatchEvent(new MouseEvent('click', { bubbles: true }))
  expect(posted).toEqual([])
  expect(pinned('done').querySelector('button')).toBeNull()
})

test("a pinned list shows what the app sent and the app's words for what it left out", () => {
  header.set({
    ...ticket,
    pins: [
      {
        id: '#tags',
        label: 'Tags',
        symbol: 'tag',
        kind: 'tags',
        texts: ['one'],
        more: '+3 more',
      },
    ],
  })
  expect(
    [...pinned('#tags').querySelectorAll('.item-chip')].map((chip) => chip.textContent),
  ).toEqual(['one'])
  expect(pinned('#tags').querySelector('.item-pin-more')!.textContent).toBe('+3 more')
  header.set({ ...ticket, pins: [{ ...pinRows[3]!, text: 'Today' }] })
  expect(root.querySelector('.item-pin-more')).toBeNull()
})

test("a pinned list's hover names every value the app says it holds, not only the one it draws", () => {
  header.set({
    ...ticket,
    pins: [
      {
        id: 'labels',
        label: 'Labels',
        symbol: 'list.bullet',
        kind: 'options',
        options: [{ label: 'amber', tone: 'amber' }],
        more: '+4 more',
        help: 'amber, blue, green, red, violet',
      },
    ],
  })
  expect(pinned('labels').querySelector<HTMLElement>('.item-pin-value')!.title).toBe(
    'amber, blue, green, red, violet',
  )
})

test('a header with no pins draws none', () => {
  header.set(ticket)
  expect(root.querySelector<HTMLElement>('.item-pins')!.hidden).toBe(true)
})

/** Draws three rows of 30 points with a fourth folded away, and returns a drag of the first by its name. */
function draggable(
  ids = ['a', 'b', 'c', 'd'],
  folded = ['d'],
): {
  key: HTMLElement
  drag: (y: number) => void
  drop: () => void
} {
  const rows = ids.map((id) => ({
    id,
    label: id,
    symbol: 'text.alignleft',
    kind: 'text' as const,
    text: id,
    editable: true,
    folded: folded.includes(id),
  }))
  header.set({ ...ticket, rows })
  const list = root.querySelector<HTMLElement>('.item-props')!
  list.getBoundingClientRect = () => ({ top: 0, height: 90 }) as DOMRect
  ;[...list.children].forEach((row, index) => {
    row.getBoundingClientRect = () => ({ top: index * 30, height: 30 }) as DOMRect
  })
  const key = list.querySelector<HTMLElement>('.item-prop-label')!
  key.dispatchEvent(new MouseEvent('pointerdown', { bubbles: true, button: 0, clientY: 15 }))
  return {
    key,
    drag: (y) => window.dispatchEvent(new MouseEvent('pointermove', { clientY: y })),
    drop: () => window.dispatchEvent(new MouseEvent('pointerup')),
  }
}

test('a row dragged by its key sends the whole order the page shows after the move', () => {
  const { drag, drop } = draggable()
  drag(50)
  drop()
  expect(posted).toEqual([
    { type: 'moveRow', item: 'ticket', row: 'a', order: ['b', 'a', 'c', 'd'] },
  ])
})

test('a row dropped last among those shown stays above the rows folded away', () => {
  const { drag, drop } = draggable()
  drag(80)
  drop()
  expect(posted).toEqual([
    { type: 'moveRow', item: 'ticket', row: 'a', order: ['b', 'c', 'a', 'd'] },
  ])
})

test('a row folded away keeps its place in the order a drag sends', () => {
  const { drag, drop } = draggable(['a', 'x', 'b', 'c'], ['x'])
  drag(80)
  drop()
  expect(posted).toEqual([
    { type: 'moveRow', item: 'ticket', row: 'a', order: ['b', 'x', 'c', 'a'] },
  ])
})

test('a drag whose rows were redrawn before the release saves nothing', () => {
  const { drag, drop } = draggable()
  drag(50)
  // The app sends a new head between the last pointer move and the release.
  header.set({
    ...ticket,
    rows: ['b', 'a', 'c', 'd'].map((id) => ({
      id,
      label: id,
      symbol: 'text.alignleft',
      kind: 'text' as const,
      text: id,
      editable: true,
      folded: id === 'd',
    })),
  })
  drop()
  expect(posted).toEqual([])
})

test('a drag of rows whose model changed without a redraw of them saves nothing', () => {
  const { drag, drop } = draggable()
  drag(50)
  header.set({ ...ticket, rows: [] })
  drop()
  expect(posted).toEqual([])
})

test('a dragged key opens no menu, and a press that does not move still does', () => {
  const { key, drag, drop } = draggable()
  drag(50)
  drop()
  key.click()
  expect(posted.map((message) => message.type)).toEqual(['moveRow'])

  posted = []
  const press = draggable()
  press.drag(16)
  press.drop()
  press.key.click()
  expect(posted.map((message) => message.type)).toEqual(['fieldMenu'])
})

test('Escape puts a dragged row back', () => {
  const { key, drag, drop } = draggable()
  drag(50)
  window.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape' }))
  drop()
  expect(posted).toEqual([])
  expect(key.parentElement!.style.transform).toBe('')
  expect(root.querySelector('.item-props')!.classList.contains('dragging')).toBe(false)
})

const tick = () => new Promise((resolve) => setTimeout(resolve))

test('the click from letting go after Escape ended a drag opens no menu, and a later press still does', async () => {
  const { key, drag } = draggable()
  drag(50)
  window.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape' }))
  // Escape ends the drag with the button still down; the click comes only when it is released.
  await tick()
  window.dispatchEvent(new MouseEvent('pointerup'))
  key.click()
  expect(posted, 'the release after Escape').toEqual([])

  key.dispatchEvent(new MouseEvent('pointerdown', { bubbles: true, button: 0, clientY: 15 }))
  window.dispatchEvent(new MouseEvent('pointerup'))
  key.click()
  expect(
    posted.map((message) => message.type),
    'the next press',
  ).toEqual(['fieldMenu'])
})

test('a drop swallows its own click however late it comes, and nothing after it', async () => {
  const { key, drag, drop } = draggable()
  drag(50)
  drop()
  await tick()
  key.click()
  expect(posted.map((message) => message.type)).toEqual(['moveRow'])

  posted = []
  key.click()
  expect(
    posted.map((message) => message.type),
    'a second click',
  ).toEqual(['fieldMenu'])
})

test('a press that starts after a cancelled drag is not swallowed', () => {
  const { key, drag } = draggable()
  drag(50)
  window.dispatchEvent(new MouseEvent('pointercancel'))
  key.dispatchEvent(new MouseEvent('pointerdown', { bubbles: true, button: 0, clientY: 15 }))
  window.dispatchEvent(new MouseEvent('pointerup'))
  key.click()
  expect(posted.map((message) => message.type)).toEqual(['fieldMenu'])
})

test('the kicker is a heading of the type and its flags, and the type name asks for Change Type', () => {
  header.setIcons(icons)
  header.set({
    ...ticket,
    kicker: {
      ...ticket.kicker,
      flags: [{ id: 'readOnly', words: 'Read Only', symbol: 'lock' }],
      spoken: 'Task, Read Only',
    },
  })
  const kicker = root.querySelector<HTMLElement>('.item-kicker')!
  expect(kicker.getAttribute('role')).toBe('heading')
  expect(kicker.getAttribute('aria-label')).toBe('Task, Read Only')
  expect(kicker.textContent).toBe('TaskRead Only')
  expect(root.firstElementChild).toBe(kicker)
  const type = root.querySelector<HTMLButtonElement>('#ItemKickerType')!
  type.click()
  expect(posted).toEqual([
    { type: 'changeType', item: 'ticket', rect: [0, 0, 0, 0], viewportHeight: window.innerHeight },
  ])
  header.set({ ...ticket, kicker: { ...ticket.kicker, changesType: false } })
  expect(root.querySelector('#ItemKickerType')!.tagName).toBe('SPAN')
})

test('folded rows wait behind Show More, and a hidden one is grey once shown', () => {
  const folded = { ...rows(1)[0]!, id: 'hidden', folded: true, muted: true }
  header.set({ ...ticket, rows: [...rows(2), folded], showMore: 'Show 1 More' })
  const more = root.querySelector<HTMLButtonElement>('.item-rows > .item-more')!
  expect(root.querySelectorAll('.item-prop')).toHaveLength(2)
  expect(more.textContent).toBe('Show 1 More')
  more.click()
  expect(root.querySelectorAll('.item-prop')).toHaveLength(3)
  expect(root.querySelector('[data-row="hidden"]')!.classList.contains('muted')).toBe(true)
  expect(more.textContent).toBe('Show Less')
  header.set({ ...ticket, rows: rows(2) })
  expect(more.hidden).toBe(true)
})

test("a long text is a row cut after two lines, and an event's When says how far off it is in grey", () => {
  header.set({
    ...ticket,
    rows: [
      {
        id: '#when',
        label: 'When',
        symbol: 'clock',
        kind: 'when',
        text: 'Thu 29 Oct',
        note: 'In 4 days',
      },
      {
        id: 'notes',
        label: 'Notes',
        symbol: 'text.alignleft',
        kind: 'text',
        text: 'One\nTwo\nThree',
        long: true,
      },
    ],
  })
  expect(root.querySelector('[data-row="#when"] .item-note')!.textContent).toBe('In 4 days')
  const notes = root.querySelector<HTMLElement>('[data-row="notes"]')!
  expect(notes.classList.contains('long')).toBe(true)
  expect(notes.querySelector<HTMLElement>('.item-prop-value')!.title).toBe('One\nTwo\nThree')
})

test("a right-click on a row opens the row's menu, and anywhere else is left to WebKit", () => {
  header.set(ticket)
  posted = []
  const name = root.querySelector('[data-row="status"] .item-prop-name')!
  expect(header.openRowMenuAt(name)).toBe(true)
  expect(posted).toMatchObject([{ type: 'fieldMenu', item: 'ticket', row: 'status' }])
  expect(header.openRowMenuAt(title())).toBe(false)
  expect(header.rowAt(name)).toEqual({ item: 'ticket', row: 'status' })
})
