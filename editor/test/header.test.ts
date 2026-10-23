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
  propertyRejected: false,
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
const chip = (id: string) => root.querySelector<HTMLElement>('#' + id)!
const label = (id: string) => chip(id).querySelector('.item-pin-label')!.textContent

test('the header shows the item it is given, and nothing before', () => {
  expect(root.hidden).toBe(true)
  header.set(ticket)
  expect(root.hidden).toBe(false)
  expect(title().textContent).toBe('Review the findings')
  expect(title().getAttribute('contenteditable')).toBe('plaintext-only')
  expect(title().getAttribute('aria-label')).toBe('Title')
  expect(title().dataset.placeholder).toBe('Sans titre')
  expect(label('ItemTypeChip')).toBe('Task')
  expect(chip('ItemTypeChip').title).toBe('Item Type')
  expect(label('ItemStatusChip')).toBe('In Progress')
  expect(chip('ItemStatusChip').getAttribute('aria-label')).toBe('Status')
  expect(label('ItemParentChip')).toBe('Field Research')
  expect(root.querySelector<HTMLElement>('.item-title-error')!.hidden).toBe(true)

  header.set({ ...ticket, type: null, status: null, parent: null, editable: false, draft: 'Draft' })
  expect(title().textContent).toBe('Draft')
  expect(title().getAttribute('contenteditable')).toBe('false')
  expect(chip('ItemTypeChip').hidden).toBe(true)
  expect(chip('ItemStatusChip').hidden).toBe(true)
  expect(chip('ItemParentChip').hidden).toBe(true)

  header.set({ ...ticket, hidden: true })
  expect(root.hidden).toBe(true)
  header.set(null)
  expect(root.hidden).toBe(true)
})

test('a pin without a value is drawn empty, and a status pin carries its mark', () => {
  header.set(ticket)
  const mark = () => chip('ItemStatusChip').querySelector<HTMLElement>('.item-status-mark')!
  expect(chip('ItemParentChip').classList.contains('empty')).toBe(false)
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
  expect(chip('ItemParentChip').classList.contains('empty')).toBe(true)
  expect(label('ItemParentChip')).toBe('Parent')
  // The empty parent pin opens the app's chooser directly, so it has no chevron and is not announced as a menu.
  expect(chip('ItemParentChip').classList.contains('direct')).toBe(true)
  expect(chip('ItemParentChip').getAttribute('aria-haspopup')).toBe('dialog')
  expect(chip('ItemStatusChip').classList.contains('direct')).toBe(false)
  expect(chip('ItemStatusChip').getAttribute('aria-haspopup')).toBe('menu')
  chip('ItemParentChip').dispatchEvent(new MouseEvent('pointerdown', { button: 0 }))
  expect(posted.map((message) => message.type)).toEqual(['headerMenu'])
  header.set({
    ...ticket,
    status: { label: 'Status', enabled: true, empty: true, opensMenu: true },
  })
  expect(chip('ItemStatusChip').classList.contains('empty')).toBe(true)
  expect(chip('ItemStatusChip').getAttribute('aria-description')).toBe('')
})

test('every pin is one height and the icons the app draws reach the page as masks', () => {
  header.set(ticket)
  const icon = { url: 'data:image/png;base64,AAAA', width: 13, height: 12 }
  header.setIcons({ type: icon, parent: icon, plus: icon, indicator: icon })
  expect(root.style.getPropertyValue('--icon-plus')).toBe('url("data:image/png;base64,AAAA")')
  expect(root.style.getPropertyValue('--icon-type-width')).toBe('13px')
  expect(root.querySelectorAll('.item-pin').length).toBe(3)
})

test('a refused title shows why and offers to discard the draft', () => {
  header.set({ ...ticket, draft: 'A/B', titleRejected: true, propertyRejected: true })
  const error = root.querySelector<HTMLElement>('.item-title-error')!
  expect(error.hidden).toBe(false)
  expect(error.textContent).toContain('The title could not be saved.')
  expect([...root.querySelectorAll<HTMLElement>('.item-error')].every((e) => !e.hidden)).toBe(true)
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

test('a chip asks for its menu with its frame, from the mouse or the keyboard', () => {
  header.set(ticket)
  chip('ItemStatusChip').getBoundingClientRect = () => new DOMRect(48, 90, 126, 26)
  const down = new MouseEvent('pointerdown', { button: 0, cancelable: true })
  chip('ItemStatusChip').dispatchEvent(down)
  expect(down.defaultPrevented).toBe(true)
  chip('ItemParentChip').dispatchEvent(new MouseEvent('click', { detail: 0 }))
  chip('ItemParentChip').dispatchEvent(new MouseEvent('click', { detail: 1 }))
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
  chip('ItemStatusChip').dispatchEvent(new MouseEvent('pointerdown', { button: 0 }))
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
