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

/** One row of the property block. The status and parent rows hold the header's own pins, which keep their
 *  menus; every other value is read only, and a link opens its item or its address. */
export interface HeaderRow {
  id: string
  label: string
  /** The SF Symbol name of the row's icon, a key of `HeaderIcons.symbols`. */
  symbol: string
  kind: 'status' | 'parent' | 'items' | 'tags' | 'date' | 'url' | 'email' | 'phone' | 'text'
  text?: string
  texts?: string[]
  items?: { title: string; item: string }[]
}

/** An item that links to the one on the page. */
export interface HeaderLinked {
  item: string
  title: string
  symbol: string
  type: string
  date: string
}

/** Which header the page draws, chosen by the app from the core type the item's type builds on. */
export type HeaderKind = 'general' | 'event' | 'person' | 'reading'

/** An event's when, worked out by the app in the event's own time zone. */
export interface HeaderEvent {
  month: string
  day: string
  weekday: string
  time: string
  zone?: string | null
  relative: string
}

/** A person's initials, or the picture the item holds inline. */
export interface HeaderPerson {
  initials: string
  photo?: string | null
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
  /** The key of the type's icon in `HeaderIcons.symbols`, drawn before the type's name. */
  icon?: string | null
  kind: HeaderKind
  event?: HeaderEvent | null
  person?: HeaderPerson | null
  /** The line under the title: a person's work, or a reading item's description. */
  subtitle?: string | null
  status: HeaderPin | null
  parent: HeaderPin | null
  /** Who made the item, if the library knows, and when. */
  byline: { source?: string | null; date: string; detail?: string | null }
  properties: HeaderRow[]
  /** How many rows show before the rest wait behind a button. */
  foldAfter: number
  /** The items a collection holds, listed under its text. Empty for any other item. */
  contents: HeaderLinked[]
  linked: HeaderLinked[]
  linkedFoldAfter: number
  /** False where the page has no text to write, so the page draws no empty editor. */
  showsText: boolean
  /** "Show N More", worded by the app for the rows and for the items that are folded away. */
  showMore: string
  showMoreContents: string
  showMoreLinked: string
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
  parent: HeaderIcon
  plus: HeaderIcon
  indicator: HeaderIcon
  /** The symbols of the property rows and of the types, by SF Symbol name. */
  symbols: Record<string, HeaderIcon>
}

export interface HeaderLabels {
  untitled: string
  title: string
  itemType: string
  status: string
  discardChanges: string
  propertyRejected: string
  parentRejected: string
  linkedFrom: string
  /** What a collection's members are called. */
  contents: string
  showLess: string
  /** What Linked From is called on a person's page, where it reads as their timeline. */
  timeline: string
  properties: string
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
  linkedFrom: 'Linked From',
  contents: 'Contents',
  showLess: 'Show Less',
  timeline: 'Timeline',
  properties: 'Properties',
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

function moreButton(parent: HTMLElement, action: () => void): HTMLButtonElement {
  const button = element('button', 'item-more', parent)
  button.type = 'button'
  button.addEventListener('click', action)
  return button
}

/** A folded list of items under the text: its heading with a chevron and a count, then rows that open an item. */
class LinkedSection {
  private readonly root: HTMLElement
  private readonly toggle: HTMLButtonElement
  private readonly list: HTMLUListElement
  private readonly more: HTMLButtonElement
  private open = false
  private all = false

  constructor(
    parent: HTMLElement,
    className: string,
    private readonly changed: () => void,
    private readonly glyph: (name: string, parent: HTMLElement) => void,
  ) {
    this.root = element('section', `item-linked ${className}`, parent)
    this.toggle = element('button', 'item-linked-toggle', this.root)
    this.toggle.type = 'button'
    this.toggle.addEventListener('click', () => {
      this.open = !this.open
      this.changed()
    })
    this.list = element('ul', 'item-linked-list', this.root)
    this.more = moreButton(this.root, () => {
      this.all = !this.all
      this.changed()
    })
  }

  /** What the section was last drawn from, so a change of what the person opened is drawn. */
  get state(): [boolean, boolean] {
    return [this.open, this.all]
  }

  /** A new item starts folded, or open where its own content is the list. */
  reset(open: boolean) {
    this.open = open
    this.all = false
  }

  draw(
    name: string,
    items: HeaderLinked[],
    foldAfter: number,
    words: { more: string; less: string },
  ) {
    this.root.hidden = items.length === 0
    this.toggle.replaceChildren()
    this.toggle.setAttribute('aria-expanded', String(this.open))
    element('span', 'item-chevron', this.toggle).setAttribute('aria-hidden', 'true')
    this.root.setAttribute('aria-label', name)
    element('span', 'item-linked-title', this.toggle).textContent = name
    element('span', 'item-linked-count', this.toggle).textContent = String(items.length)
    const shown = this.all ? items : items.slice(0, foldAfter)
    this.list.hidden = !this.open
    this.list.replaceChildren(
      ...shown.map((linked) => {
        const entry = element('li', 'item-linked-row')
        const button = element('button', 'item-linked-open', entry)
        button.type = 'button'
        button.addEventListener('click', () => postToHost({ type: 'openItem', item: linked.item }))
        this.glyph(linked.symbol, button)
        element('span', 'item-linked-name', button).textContent = linked.title
        const detail = element('span', 'item-linked-detail', button)
        element('span', '', detail).textContent = linked.type
        element('span', 'item-byline-dot', detail).setAttribute('aria-hidden', 'true')
        element('span', '', detail).textContent = linked.date
        return entry
      }),
    )
    this.more.hidden = !this.open || items.length <= foldAfter
    this.more.textContent = this.all ? words.less : words.more
  }
}

/** The item's title and pinned properties, drawn in the page above the note so they scroll with it as one
 *  surface. What they do is the app's: the title is saved as the item's property, and each pin opens a native
 *  menu. */
export class ItemHeader {
  private model?: HeaderModel
  private readonly labels: HeaderLabels
  private readonly lead: HTMLDivElement
  private readonly avatar: HTMLSpanElement
  private readonly title: HTMLDivElement
  private readonly subtitle: HTMLParagraphElement
  private readonly when: HTMLDivElement
  private readonly titleError: HTMLDivElement
  private readonly titleRefusal: HTMLParagraphElement
  private readonly byline: HTMLDivElement
  private readonly properties: HTMLDListElement
  private readonly moreProperties: HTMLButtonElement
  private readonly contents: LinkedSection
  private readonly linked: LinkedSection
  private symbols: Record<string, HeaderIcon> = {}
  /** What the property block and the linked items were last drawn from, so an unchanged header is not drawn
   *  again under the pointer. */
  private drawn = ''
  /** Whether the person has expanded the rows, for the item on the page. */
  private expanded = { item: '', properties: false }
  private readonly typePin: HTMLSpanElement
  private readonly statusPin: HTMLButtonElement
  private readonly parentPin: HTMLButtonElement
  private readonly propertyError: HTMLParagraphElement
  private readonly parentError: HTMLParagraphElement
  /** The item whose title is being edited, so a blur after the page moved to another item commits nothing. */
  private editing?: string
  /** The item whose title is to take the keyboard as soon as the header shows it, since the app may ask before
   *  it has sent that item's header. */
  private wantedTitle?: string

  /** `footer` holds what follows the text, the contents of a collection and Linked From. */
  constructor(
    readonly root: HTMLElement,
    readonly footer: HTMLElement,
    labels: Partial<HeaderLabels> = {},
  ) {
    this.labels = { ...englishLabels, ...labels }
    root.hidden = true
    footer.hidden = true
    this.lead = element('div', 'item-lead', root)
    this.avatar = element('span', 'item-avatar', this.lead)
    this.avatar.setAttribute('aria-hidden', 'true')
    const heading = element('div', 'item-heading', this.lead)
    this.title = element('div', 'item-title', heading)
    this.title.id = 'ItemPageTitle'
    this.title.setAttribute('role', 'textbox')
    this.title.setAttribute('aria-label', this.labels.title)
    this.title.setAttribute('aria-placeholder', this.labels.untitled)
    this.title.dataset.placeholder = this.labels.untitled
    this.title.spellcheck = false
    this.subtitle = element('p', 'item-subtitle', heading)
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
    this.byline = element('div', 'item-byline', root)
    this.typePin = element('span', 'item-pin', this.byline)
    this.typePin.id = 'ItemTypePin'
    this.typePin.title = this.labels.itemType
    element('span', 'item-pin-icon item-icon-type', this.typePin).setAttribute(
      'aria-hidden',
      'true',
    )
    element('span', 'item-pin-label', this.typePin)
    this.when = element('div', 'item-when', root)
    const pins = document.createElement('div')
    this.statusPin = this.menuPin('ItemStatusPin', 'status', pins)
    this.statusPin.setAttribute('aria-label', this.labels.status)
    this.parentPin = this.menuPin('ItemParentPin', 'parent', pins)
    this.properties = element('dl', 'item-props', root)
    this.properties.setAttribute('aria-label', this.labels.properties)
    this.moreProperties = this.moreButton(root, () => {
      this.expanded.properties = !this.expanded.properties
      this.redraw()
    })
    this.propertyError = element('p', 'item-error', root)
    this.propertyError.setAttribute('role', 'alert')
    this.propertyError.textContent = this.labels.propertyRejected
    this.propertyError.hidden = true
    this.parentError = element('p', 'item-error', root)
    this.parentError.setAttribute('role', 'alert')
    this.parentError.textContent = this.labels.parentRejected
    this.parentError.hidden = true
    const redraw = () => this.redraw()
    const glyph = (name: string, parent: HTMLElement) => this.glyph(name, parent)
    this.contents = new LinkedSection(footer, 'item-contents', redraw, glyph)
    this.linked = new LinkedSection(footer, 'item-linked-from', redraw, glyph)

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
      this.footer.hidden = true
      document.body.dataset.header = 'general'
      document.body.dataset.text = 'shown'
      return
    }
    // Another item's title is never edited as this one's.
    if (previous?.item !== model.item && this.isEditingTitle) {
      this.editing = undefined
      this.title.blur()
    }
    this.root.hidden = model.hidden
    this.footer.hidden = model.hidden
    this.root.style.setProperty('--interface-text-size', `${model.interfaceTextSize}px`)
    this.footer.style.setProperty('--interface-text-size', `${model.interfaceTextSize}px`)
    document.body.dataset.text = model.showsText ? 'shown' : 'none'
    this.root.dataset.kind = model.kind
    document.body.dataset.header = model.hidden ? 'general' : model.kind
    this.subtitle.textContent = model.subtitle ?? ''
    this.subtitle.hidden = !model.subtitle
    const editable = model.editable ? 'plaintext-only' : 'false'
    if (this.title.getAttribute('contenteditable') !== editable) {
      this.title.setAttribute('contenteditable', editable)
      this.title.setAttribute('aria-readonly', String(!model.editable))
    }
    if (!this.isEditingTitle) this.showTitle()
    this.takeWantedTitle()
    this.titleError.hidden = !model.titleRejected
    this.titleRefusal.textContent = model.titleRefusal
    this.propertyError.hidden = !model.propertyRejected
    this.parentError.hidden = !model.parentRejected
    this.typePin.hidden = model.type == null
    this.typePin.querySelector('.item-pin-label')!.textContent = model.type ?? ''
    this.drawTypeIcon()
    this.showPin(this.statusPin, model.status)
    this.showPin(this.parentPin, model.parent)
    if (previous?.item !== model.item) {
      this.expanded = { item: model.item, properties: false }
      // A person's timeline and a collection's contents are the page's own content, so they open with the page.
      this.contents.reset(true)
      this.linked.reset(model.kind === 'person')
    }
    this.redraw()
    // The status pin is named for what it sets; what it is set to is read after.
    this.statusPin.setAttribute(
      'aria-description',
      model.status && !model.status.empty ? model.status.label : '',
    )
  }

  /** Gives the title of `item` the keyboard with its text selected, so typing replaces it. Held until the header
   *  shows that item and can be edited. */
  focusTitle(item: string) {
    this.wantedTitle = item
    this.takeWantedTitle()
  }

  /** The keyboard goes elsewhere, so a title still waiting for it does not take it later. */
  cancelTitleFocus() {
    this.wantedTitle = undefined
  }

  private takeWantedTitle() {
    const model = this.model
    if (!model || this.wantedTitle !== model.item || this.root.hidden) return
    if (this.title.getAttribute('contenteditable') !== 'plaintext-only') return
    this.wantedTitle = undefined
    this.title.focus()
    const selection = document.getSelection()
    if (!selection) return
    const range = document.createRange()
    range.selectNodeContents(this.title)
    selection.removeAllRanges()
    selection.addRange(range)
  }

  setIcons(icons: HeaderIcons) {
    const style = this.root.style
    const footerStyle = this.footer.style
    this.symbols = icons.symbols ?? {}
    this.drawTypeIcon()
    this.drawn = ''
    this.redraw()
    for (const [name, icon] of Object.entries(icons) as [keyof HeaderIcons, HeaderIcon][]) {
      if (name === 'symbols') continue
      style.setProperty(`--icon-${name}`, `url("${icon.url}")`)
      style.setProperty(`--icon-${name}-width`, `${icon.width}px`)
      style.setProperty(`--icon-${name}-height`, `${icon.height}px`)
      footerStyle.setProperty(`--icon-${name}`, `url("${icon.url}")`)
      footerStyle.setProperty(`--icon-${name}-width`, `${icon.width}px`)
      footerStyle.setProperty(`--icon-${name}-height`, `${icon.height}px`)
    }
  }

  /** The icon of the item's type before its name, in the secondary color; none for a type the app drew nothing for. */
  private drawTypeIcon() {
    const node = this.typePin.querySelector<HTMLElement>('.item-icon-type')!
    const icon = this.model?.icon ? this.symbols[this.model.icon] : undefined
    node.hidden = !icon
    if (!icon) return
    node.style.width = `${icon.width}px`
    node.style.height = `${icon.height}px`
    node.style.setProperty('-webkit-mask-image', `url("${icon.url}")`)
    node.style.maskImage = `url("${icon.url}")`
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

  private menuPin(id: string, menu: HeaderMenu, parent: HTMLElement): HTMLButtonElement {
    const pin = element('button', 'item-pin item-menu-pin', parent)
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

  private moreButton(parent: HTMLElement, action: () => void): HTMLButtonElement {
    return moreButton(parent, action)
  }

  /** A symbol the app drew, as a mask in the text's secondary color; nothing for one it did not draw. */
  private glyph(name: string, parent: HTMLElement): void {
    const icon = this.symbols[name]
    const node = element('span', 'item-glyph', parent)
    node.setAttribute('aria-hidden', 'true')
    if (!icon) return
    node.style.width = `${icon.width}px`
    node.style.height = `${icon.height}px`
    node.style.setProperty('-webkit-mask-image', `url("${icon.url}")`)
    node.style.maskImage = `url("${icon.url}")`
  }

  private link(parent: HTMLElement, text: string, open: () => void, href?: string): void {
    const link = element(href ? 'a' : 'button', 'item-link', parent)
    link.textContent = text
    if (link instanceof HTMLButtonElement) link.type = 'button'
    else {
      link.href = href!
      link.setAttribute('role', 'link')
    }
    link.addEventListener('click', (event) => {
      event.preventDefault()
      open()
    })
  }

  /** Draws the byline, the property block and the linked items from the model. */
  private redraw() {
    const model = this.model
    if (!model) return
    const source = model.byline.source
    const key = JSON.stringify([
      model.kind,
      model.event,
      model.person,
      model.byline,
      model.properties,
      model.contents,
      model.linked,
      model.showMore,
      model.showMoreContents,
      model.showMoreLinked,
      this.expanded,
      this.contents.state,
      this.linked.state,
      Object.keys(this.symbols).length,
    ])
    if (key === this.drawn) return
    this.drawn = key

    // The type, then who made the item and when, as one quiet line.
    for (const extra of [...this.byline.querySelectorAll('.item-byline-part, .item-byline-dot')])
      extra.remove()
    let first = this.typePin.hidden
    for (const part of [source, model.byline.date, model.byline.detail]) {
      if (!part) continue
      if (!first)
        element('span', 'item-byline-dot', this.byline).setAttribute('aria-hidden', 'true')
      first = false
      element('span', 'item-byline-part', this.byline).textContent = part
    }

    const shown = this.expanded.properties
      ? model.properties
      : model.properties.slice(0, model.foldAfter)
    this.properties.replaceChildren(...shown.map((row) => this.row(row, model)))
    this.properties.hidden = shown.length === 0
    this.drawLead(model)
    this.moreProperties.hidden = model.properties.length <= model.foldAfter
    this.moreProperties.textContent = this.expanded.properties
      ? this.labels.showLess
      : model.showMore

    const linkedName = model.kind === 'person' ? this.labels.timeline : this.labels.linkedFrom
    this.contents.draw(this.labels.contents, model.contents, model.linkedFoldAfter, {
      more: model.showMoreContents,
      less: this.labels.showLess,
    })
    this.linked.draw(linkedName, model.linked, model.linkedFoldAfter, {
      more: model.showMoreLinked,
      less: this.labels.showLess,
    })
  }

  /** What the kind adds above the properties: a person's avatar, an event's calendar block and when. */
  private drawLead(model: HeaderModel) {
    const person = model.kind === 'person' ? model.person : null
    this.avatar.hidden = !person
    this.avatar.replaceChildren()
    this.avatar.classList.toggle('photo', !!person?.photo)
    if (person?.photo) {
      const picture = element('img', 'item-avatar-photo', this.avatar)
      picture.alt = ''
      picture.src = person.photo
    } else if (person) {
      this.avatar.textContent = person.initials
    }

    const event = model.kind === 'event' ? model.event : null
    this.when.hidden = !event
    this.when.replaceChildren()
    if (!event) return
    const calendar = element('div', 'item-calendar', this.when)
    calendar.setAttribute('aria-hidden', 'true')
    element('span', 'item-calendar-month', calendar).textContent = event.month
    element('span', 'item-calendar-day', calendar).textContent = event.day
    const text = element('div', 'item-when-text', this.when)
    element('p', 'item-when-time', text).textContent = event.time
    const details = element('p', 'item-when-detail', text)
    const parts = [event.weekday, event.zone, event.relative].filter(Boolean) as string[]
    parts.forEach((part, index) => {
      if (index > 0) element('span', 'item-byline-dot', details).setAttribute('aria-hidden', 'true')
      element('span', '', details).textContent = part
    })
    // The status the event is in sits with its time rather than among the properties.
    if (model.status) element('div', 'item-when-status', text).append(this.statusPin)
  }

  private row(row: HeaderRow, model: HeaderModel): HTMLElement {
    const entry = element('div', 'item-prop')
    const term = element('dt', 'item-prop-label', entry)
    this.glyph(row.symbol, term)
    element('span', 'item-prop-name', term).textContent = row.label
    const value = element('dd', 'item-prop-value', entry)
    switch (row.kind) {
      case 'status':
        if (model.status) value.append(this.statusPin)
        break
      case 'parent':
        if (model.parent) value.append(this.parentPin)
        break
      case 'items':
        for (const target of row.items ?? [])
          this.link(value, target.title, () => postToHost({ type: 'openItem', item: target.item }))
        break
      case 'tags':
        for (const tag of row.texts ?? []) element('span', 'item-chip', value).textContent = tag
        break
      case 'url': {
        const href = row.text ?? ''
        if (/^https?:\/\//i.test(href))
          this.link(value, href, () => postToHost({ type: 'openLink', href }), href)
        else value.textContent = href
        break
      }
      case 'email': {
        const address = row.text ?? ''
        const href = `mailto:${address}`
        this.link(value, address, () => postToHost({ type: 'openLink', href }), href)
        break
      }
      case 'phone': {
        const number = row.text ?? ''
        // A number is dialed as its digits and a leading plus, whatever spacing it is written with.
        const dialed = number.replace(/(?!^\+)[^\d]/g, '')
        if (dialed.replace('+', '') === '') value.textContent = number
        else
          this.link(
            value,
            number,
            () => postToHost({ type: 'openLink', href: `tel:${dialed}` }),
            `tel:${dialed}`,
          )
        break
      }
      default:
        value.textContent = row.text ?? ''
    }
    return entry
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
