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
  editable: true,
  type: 'Task',
  status: { label: 'In Progress', enabled: true },
  parent: { label: 'Field Research', enabled: true },
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
const label = (id: string) => chip(id).querySelector('.item-chip-label')!.textContent

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
  header.set({ ...ticket, status: { label: 'Set Status', enabled: false } })
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

test('text pasted, dropped or replaced into the title comes in on one line', () => {
  header.set(ticket)
  title().focus()
  const inserted: string[] = []
  document.execCommand = (command: string, _ui?: boolean, value?: string) => {
    if (command === 'insertText' && value != null) inserted.push(value)
    return true
  }
  for (const inputType of ['insertFromPaste', 'insertFromDrop', 'insertReplacementText']) {
    const event = new InputEvent('beforeinput', { inputType, cancelable: true })
    Object.defineProperty(event, 'dataTransfer', {
      value: { getData: (type: string) => (type === 'text/plain' ? 'Field\nnotes\r\nreview' : '') },
    })
    title().dispatchEvent(event)
    expect(event.defaultPrevented).toBe(true)
  }
  const typed = new InputEvent('beforeinput', {
    inputType: 'insertText',
    data: 'x',
    cancelable: true,
  })
  title().dispatchEvent(typed)
  expect(typed.defaultPrevented).toBe(false)
  const plain = new InputEvent('beforeinput', { inputType: 'insertFromPaste', cancelable: true })
  Object.defineProperty(plain, 'dataTransfer', { value: { getData: () => 'One line' } })
  title().dispatchEvent(plain)
  expect(plain.defaultPrevented).toBe(false)
  expect(inserted).toEqual(['Field notes review', 'Field notes review', 'Field notes review'])
})
