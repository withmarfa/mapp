import { postToHost } from './bridge'

/** A chip whose menu the app shows. */
export interface HeaderChip {
  label: string
  enabled: boolean
}

/** What the app says the header shows for the item on the page. */
export interface HeaderModel {
  item: string
  hidden: boolean
  title: string
  /** The title the person typed and the app has not saved, kept by the app for each item. */
  draft: string | null
  titleRejected: boolean
  editable: boolean
  type: string | null
  status: HeaderChip | null
  parent: HeaderChip | null
  propertyRejected: boolean
  /** The interface's text size in points, which the chips and messages follow. */
  interfaceTextSize: number
}

/** A symbol the app drew, as an image the page uses as a mask so it takes the text's color. */
export interface HeaderIcon {
  url: string
  width: number
  height: number
}

export interface HeaderIcons {
  status: HeaderIcon
  parent: HeaderIcon
  indicator: HeaderIcon
}

export interface HeaderLabels {
  untitled: string
  title: string
  itemType: string
  status: string
  discardChanges: string
  titleRejected: string
  propertyRejected: string
}

export type HeaderMenu = 'status' | 'parent'

const englishLabels: HeaderLabels = {
  untitled: 'Untitled',
  title: 'Title',
  itemType: 'Item Type',
  status: 'Status',
  discardChanges: 'Discard Changes',
  titleRejected:
    'The title could not be saved. Use a unique file name without slashes or line breaks.',
  propertyRejected: 'The value could not be saved. Please try again.',
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

/** The item's title and chips, drawn in the page above the note so they scroll with it as one surface. What
 *  they do is the app's: the title is saved as the item's property, and each chip opens a native menu. */
export class ItemHeader {
  private model?: HeaderModel
  private readonly labels: HeaderLabels
  private readonly title: HTMLDivElement
  private readonly titleError: HTMLDivElement
  private readonly chips: HTMLDivElement
  private readonly typeChip: HTMLSpanElement
  private readonly statusChip: HTMLButtonElement
  private readonly parentChip: HTMLButtonElement
  private readonly propertyError: HTMLParagraphElement
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
    const message = element('p', 'item-error', this.titleError)
    message.setAttribute('role', 'alert')
    message.textContent = this.labels.titleRejected
    const discard = element('button', 'item-discard', this.titleError)
    discard.type = 'button'
    discard.textContent = this.labels.discardChanges
    discard.addEventListener('click', () => {
      if (this.model) postToHost({ type: 'titleDiscard', item: this.model.item })
    })
    this.chips = element('div', 'item-chips', root)
    this.typeChip = element('span', 'item-chip', this.chips)
    this.typeChip.id = 'ItemTypeChip'
    this.typeChip.title = this.labels.itemType
    element('span', 'item-chip-label', this.typeChip)
    this.statusChip = this.menuChip('ItemStatusChip', 'status')
    this.statusChip.setAttribute('aria-label', this.labels.status)
    this.parentChip = this.menuChip('ItemParentChip', 'parent')
    this.propertyError = element('p', 'item-error', root)
    this.propertyError.setAttribute('role', 'alert')
    this.propertyError.textContent = this.labels.propertyRejected
    this.propertyError.hidden = true

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
    this.title.addEventListener('keydown', (event) => {
      if (event.key !== 'Enter' || event.isComposing) return
      event.preventDefault()
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
      if (this.model) postToHost({ type: 'titleInput', item: this.model.item, text: this.text })
    })
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
    this.propertyError.hidden = !model.propertyRejected
    this.typeChip.hidden = model.type == null
    this.typeChip.firstElementChild!.textContent = model.type ?? ''
    this.showChip(this.statusChip, model.status)
    this.showChip(this.parentChip, model.parent)
    // The status chip is named for what it sets; what it is set to is read after.
    this.statusChip.setAttribute('aria-description', model.status?.label ?? '')
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

  private showChip(chip: HTMLButtonElement, model: HeaderChip | null) {
    chip.hidden = model == null
    chip.disabled = !(model?.enabled ?? false)
    chip.querySelector('.item-chip-label')!.textContent = model?.label ?? ''
  }

  private menuChip(id: string, menu: HeaderMenu): HTMLButtonElement {
    const chip = element('button', 'item-chip item-menu-chip', this.chips)
    chip.type = 'button'
    chip.id = id
    chip.setAttribute('aria-haspopup', 'menu')
    element('span', `item-chip-icon item-icon-${menu}`, chip).setAttribute('aria-hidden', 'true')
    element('span', 'item-chip-label', chip)
    element('span', 'item-chip-icon item-icon-indicator', chip).setAttribute('aria-hidden', 'true')
    // A native pop-up button opens as the mouse goes down, and from the keyboard on Space or Return.
    chip.addEventListener('pointerdown', (event) => {
      if (event.button !== 0 || chip.disabled) return
      event.preventDefault()
      this.openMenu(chip, menu)
    })
    // As with an AppKit button, a click leaves the keyboard where it was, in the title say.
    chip.addEventListener('mousedown', (event) => event.preventDefault())
    chip.addEventListener('click', (event) => {
      if (event.detail === 0) this.openMenu(chip, menu)
    })
    return chip
  }

  private openMenu(chip: HTMLElement, menu: HeaderMenu) {
    if (!this.model) return
    const rect = chip.getBoundingClientRect()
    postToHost({
      type: 'headerMenu',
      item: this.model.item,
      menu,
      rect: [rect.left, rect.top, rect.width, rect.height],
      viewportHeight: window.innerHeight,
    })
  }
}
