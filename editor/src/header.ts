import { postToHost } from './bridge'

/** How a status pin draws its mark: the color the status carries and how much of the ring it fills. */
export type HeaderTone = 'neutral' | 'orange' | 'red' | 'green' | 'grey'
export type HeaderFill = 'none' | 'half' | 'full'

/** A pin under the title. An empty pin has no value yet and shows a plus in place of its symbol. */
export interface HeaderPin {
  label: string
  enabled: boolean
  empty: boolean
  /** False for a pin that opens the app's chooser directly: it has no chevron, as a pop-up button does. */
  opensMenu: boolean
  /** Only the status pin has a mark. */
  mark?: { tone: HeaderTone; fill: HeaderFill }
}

/** What the app says the header shows for the item on the page. */
export interface HeaderModel {
  item: string
  hidden: boolean
  title: string
  /** The title the person typed and the app has not saved, kept by the app for each item. */
  draft: string | null
  titleRejected: boolean
  /** Why the title was refused, in the words of the library the item is in. */
  titleRefusal: string
  editable: boolean
  type: string | null
  status: HeaderPin | null
  parent: HeaderPin | null
  propertyRejected: boolean
  /** The app could not remove the parent. */
  parentRejected: boolean
  /** The interface's text size in points, which the pins and messages follow. */
  interfaceTextSize: number
}

/** A symbol the app drew, as an image the page uses as a mask so it takes the text's color. */
export interface HeaderIcon {
  url: string
  width: number
  height: number
}

export interface HeaderIcons {
  type: HeaderIcon
  parent: HeaderIcon
  plus: HeaderIcon
  indicator: HeaderIcon
}

export interface HeaderLabels {
  untitled: string
  title: string
  itemType: string
  status: string
  discardChanges: string
  propertyRejected: string
  parentRejected: string
}

export type HeaderMenu = 'status' | 'parent'

const lineBreak = /[\r\n\u2028\u2029\u0085]/
const lineBreaks = /\s*[\r\n\u2028\u2029\u0085]+\s*/g

const englishLabels: HeaderLabels = {
  untitled: 'Untitled',
  title: 'Title',
  itemType: 'Item Type',
  status: 'Status',
  discardChanges: 'Discard Changes',
  propertyRejected: 'The value could not be saved. Please try again.',
  parentRejected: 'The connection could not be removed.',
}

function element<K extends keyof HTMLElementTagNameMap>(
  tag: K,
  className: string,
  parent?: HTMLElement,
): HTMLElementTagNameMap[K] {
  const node = document.createElement(tag)
  node.className = className
  parent?.append(node)
  return node
}

/** The item's title and pinned properties, drawn in the page above the note so they scroll with it as one
 *  surface. What they do is the app's: the title is saved as the item's property, and each pin opens a native
 *  menu. */
export class ItemHeader {
  private model?: HeaderModel
  private readonly labels: HeaderLabels
  private readonly title: HTMLDivElement
  private readonly titleError: HTMLDivElement
  private readonly titleRefusal: HTMLParagraphElement
  private readonly pins: HTMLDivElement
  private readonly typePin: HTMLSpanElement
  private readonly statusPin: HTMLButtonElement
  private readonly parentPin: HTMLButtonElement
  private readonly propertyError: HTMLParagraphElement
  private readonly parentError: HTMLParagraphElement
  /** The item whose title is being edited, so a blur after the page moved to another item commits nothing. */
  private editing?: string

  constructor(
    readonly root: HTMLElement,
    labels: Partial<HeaderLabels> = {},
  ) {
    this.labels = { ...englishLabels, ...labels }
    root.hidden = true
    this.title = element('div', 'item-title', root)
    this.title.id = 'ItemPageTitle'
    this.title.setAttribute('role', 'textbox')
    this.title.setAttribute('aria-label', this.labels.title)
    this.title.setAttribute('aria-placeholder', this.labels.untitled)
    this.title.dataset.placeholder = this.labels.untitled
    this.title.spellcheck = false
    this.titleError = element('div', 'item-title-error', root)
    this.titleError.hidden = true
    this.titleRefusal = element('p', 'item-error', this.titleError)
    this.titleRefusal.setAttribute('role', 'alert')
    const discard = element('button', 'item-discard', this.titleError)
    discard.type = 'button'
    discard.textContent = this.labels.discardChanges
    discard.addEventListener('click', () => {
      if (this.model) postToHost({ type: 'titleDiscard', item: this.model.item })
    })
    this.pins = element('div', 'item-pins', root)
    this.typePin = element('span', 'item-pin', this.pins)
    this.typePin.id = 'ItemTypePin'
    this.typePin.title = this.labels.itemType
    element('span', 'item-pin-icon item-icon-type', this.typePin).setAttribute(
      'aria-hidden',
      'true',
    )
    element('span', 'item-pin-label', this.typePin)
    this.statusPin = this.menuPin('ItemStatusPin', 'status')
    this.statusPin.setAttribute('aria-label', this.labels.status)
    this.parentPin = this.menuPin('ItemParentPin', 'parent')
    this.propertyError = element('p', 'item-error', root)
    this.propertyError.setAttribute('role', 'alert')
    this.propertyError.textContent = this.labels.propertyRejected
    this.propertyError.hidden = true
    this.parentError = element('p', 'item-error', root)
    this.parentError.setAttribute('role', 'alert')
    this.parentError.textContent = this.labels.parentRejected
    this.parentError.hidden = true

    this.title.addEventListener('focus', () => {
      this.editing = this.model?.item
      postToHost({ type: 'titleFocus', focused: true })
    })
    this.title.addEventListener('blur', () => {
      postToHost({ type: 'titleFocus', focused: false })
      const item = this.editing
      this.editing = undefined
      if (item && item === this.model?.item)
        postToHost({ type: 'titleCommit', item, text: this.text, startWriting: false })
      this.showTitle()
    })
    this.title.addEventListener('beforeinput', (event) => {
      if (event.inputType === 'insertParagraph' || event.inputType === 'insertLineBreak')
        event.preventDefault()
    })
    // A title is one line, so text brought in with line breaks comes in with spaces instead, as one change that
    // one Undo takes out. WebKit does not always pass the breaks on to `beforeinput`, so the paste and the drop
    // themselves are read.
    this.title.addEventListener('paste', (event) => {
      if (this.insertOnOneLine(event.clipboardData)) event.preventDefault()
    })
    this.title.addEventListener('drop', (event) => {
      const caret = document.caretRangeFromPoint?.(event.clientX, event.clientY)
      const text = event.dataTransfer?.getData('text/plain') ?? ''
      if (!lineBreak.test(text)) return
      event.preventDefault()
      // A drop the page makes itself does not move the keyboard; the title takes it so that leaving saves it.
      this.title.focus()
      const selection = document.getSelection()
      if (caret && selection) {
        selection.removeAllRanges()
        selection.addRange(caret)
      }
      this.insertOnOneLine(event.dataTransfer)
    })
    this.title.addEventListener('keydown', (event) => {
      // The Return that confirms an input method's conversion belongs to the input method.
      if (event.key !== 'Enter' || event.isComposing || event.keyCode === 229) return
      event.preventDefault()
      // Return saves the title, so moving on from it afterwards does not save it again.
      this.editing = undefined
      if (this.model)
        postToHost({
          type: 'titleCommit',
          item: this.model.item,
          text: this.text,
          startWriting: true,
        })
    })
    this.title.addEventListener('input', () => {
      // An emptied editable keeps a line break, which would hide the placeholder.
      if (this.text === '' && this.title.childNodes.length) this.title.replaceChildren()
      this.title.classList.toggle('empty', this.text === '')
      if (!this.model) return
      this.editing = this.model.item
      postToHost({ type: 'titleInput', item: this.model.item, text: this.text })
    })
  }

  /** Inserts the text with its line breaks as spaces, if it has any; whether it did. */
  private insertOnOneLine(data: DataTransfer | null): boolean {
    const text = data?.getData('text/plain') ?? ''
    if (!lineBreak.test(text)) return false
    document.execCommand('insertText', false, text.replace(lineBreaks, ' '))
    return true
  }

  /** The title as typed. */
  get text(): string {
    return this.title.textContent ?? ''
  }

  get isEditingTitle(): boolean {
    return document.activeElement === this.title
  }

  get isHidden(): boolean {
    return this.root.hidden !== false
  }

  /** Where the header ends in the document, which the toolbar's title waits for. */
  get bottom(): number {
    return this.isHidden ? 0 : this.root.offsetTop + this.root.offsetHeight
  }

  set(model: HeaderModel | null) {
    const previous = this.model
    this.model = model ?? undefined
    if (!model) {
      if (this.isEditingTitle) this.title.blur()
      this.root.hidden = true
      return
    }
    // Another item's title is never edited as this one's.
    if (previous?.item !== model.item && this.isEditingTitle) {
      this.editing = undefined
      this.title.blur()
    }
    this.root.hidden = model.hidden
    this.root.style.setProperty('--interface-text-size', `${model.interfaceTextSize}px`)
    const editable = model.editable ? 'plaintext-only' : 'false'
    if (this.title.getAttribute('contenteditable') !== editable) {
      this.title.setAttribute('contenteditable', editable)
      this.title.setAttribute('aria-readonly', String(!model.editable))
    }
    if (!this.isEditingTitle) this.showTitle()
    this.titleError.hidden = !model.titleRejected
    this.titleRefusal.textContent = model.titleRefusal
    this.propertyError.hidden = !model.propertyRejected
    this.parentError.hidden = !model.parentRejected
    this.typePin.hidden = model.type == null
    this.typePin.querySelector('.item-pin-label')!.textContent = model.type ?? ''
    this.showPin(this.statusPin, model.status)
    this.showPin(this.parentPin, model.parent)
    // The status pin is named for what it sets; what it is set to is read after.
    this.statusPin.setAttribute(
      'aria-description',
      model.status && !model.status.empty ? model.status.label : '',
    )
  }

  setIcons(icons: HeaderIcons) {
    const style = this.root.style
    for (const [name, icon] of Object.entries(icons) as [keyof HeaderIcons, HeaderIcon][]) {
      style.setProperty(`--icon-${name}`, `url("${icon.url}")`)
      style.setProperty(`--icon-${name}-width`, `${icon.width}px`)
      style.setProperty(`--icon-${name}-height`, `${icon.height}px`)
    }
  }

  /** The person's draft where there is one, otherwise the saved title; never while they are typing it. */
  private showTitle() {
    if (!this.model) return
    const text = this.model.draft ?? this.model.title
    if (this.text !== text) this.title.textContent = text
    this.title.classList.toggle('empty', text === '')
  }

  private showPin(pin: HTMLButtonElement, model: HeaderPin | null) {
    pin.hidden = model == null
    pin.disabled = !(model?.enabled ?? false)
    pin.classList.toggle('empty', model?.empty ?? false)
    const opensMenu = model?.opensMenu ?? true
    pin.classList.toggle('direct', !opensMenu)
    pin.setAttribute('aria-haspopup', opensMenu ? 'menu' : 'dialog')
    pin.querySelector('.item-pin-label')!.textContent = model?.label ?? ''
    // The status ring is drawn here, from the tone and fill the app chose, since the catalogue holds no colors.
    const mark = pin.querySelector<HTMLElement>('.item-status-mark')
    if (mark) {
      mark.dataset.tone = model?.mark?.tone ?? 'neutral'
      mark.dataset.fill = model?.mark?.fill ?? 'none'
    }
  }

  private menuPin(id: string, menu: HeaderMenu): HTMLButtonElement {
    const pin = element('button', 'item-pin item-menu-pin', this.pins)
    pin.type = 'button'
    pin.id = id
    // An empty pin shows a plus where a filled one shows its symbol.
    const symbol =
      menu === 'status'
        ? element('span', 'item-pin-symbol item-status-mark', pin)
        : element('span', 'item-pin-symbol item-pin-icon item-icon-parent', pin)
    symbol.setAttribute('aria-hidden', 'true')
    element('span', 'item-pin-icon item-icon-plus', pin).setAttribute('aria-hidden', 'true')
    element('span', 'item-pin-label', pin)
    element('span', 'item-pin-icon item-icon-indicator', pin).setAttribute('aria-hidden', 'true')
    // A native pop-up button opens as the mouse goes down, and from the keyboard on Space or Return.
    pin.addEventListener('pointerdown', (event) => {
      if (event.button !== 0 || pin.disabled) return
      event.preventDefault()
      this.openMenu(pin, menu)
    })
    // As with an AppKit button, a click leaves the keyboard where it was, in the title say.
    pin.addEventListener('mousedown', (event) => event.preventDefault())
    pin.addEventListener('click', (event) => {
      if (event.detail === 0) this.openMenu(pin, menu)
    })
    return pin
  }

  private openMenu(pin: HTMLElement, menu: HeaderMenu) {
    if (!this.model) return
    const rect = pin.getBoundingClientRect()
    postToHost({
      type: 'headerMenu',
      item: this.model.item,
      menu,
      rect: [rect.left, rect.top, rect.width, rect.height],
      viewportHeight: window.innerHeight,
    })
  }
}
