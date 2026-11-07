import { openLink, postToHost } from './bridge'
import { dragRows } from './row-drag'

/** The symbol a row's key shows under the pointer, a key of `HeaderIcons.symbols`. */
const rowGrip = 'line.3.horizontal'

/** How a status pin draws its mark: the color the status carries (a tone's name, or `neutral` for the text's own
 *  color) and how the ring is filled. */
export type HeaderTone = 'neutral' | 'blue' | 'red' | 'green' | 'gray'
export type HeaderFill = 'none' | 'half' | 'full' | 'slash'

/** Every chip look as CSS custom properties, resolved by the app for light and for dark: the sizes and fills
 *  (`--chip-*`) and each tone's colors (`--tone-<name>`, `--tone-<name>-ink`, `--tone-<name>-mark`, `--tone-<name>-chip`). The page applies
 *  the set for the appearance it is in and never picks a color or a size of its own. */
export interface HeaderChipStyle {
  light: Record<string, string>
  dark: Record<string, string>
}

/** The status or the parent as a button that opens the menu the app builds, wherever the page draws it: in a pin or in
 *  a row of the property block. An empty status, in a row, has no value yet and shows a plus in place of its mark. */
export interface HeaderPin {
  label: string
  enabled: boolean
  empty: boolean
  /** Only the status pin has a mark. */
  mark?: { tone: HeaderTone; fill: HeaderFill }
  /** Only the parent pin has these: the parent's type icon, a key of `HeaderIcons.symbols`, and its tone's name. */
  icon?: string | null
  tone?: string | null
}

/** An item a row links to: drawn as its type's mark in the item's own tone and its title on a grey fill, or, for a person,
 *  as initials and the name. The app chooses the kind and the tone. */
export interface HeaderItem {
  title: string
  item: string
  symbol: string
  kind: 'link' | 'person'
  tone?: string | null
  /** A person's initials; absent where the name has none, so no empty circle is drawn. */
  initials?: string | null
}

/** A person a list names (an assignee, an attendee): initials and a name, with no item behind them to open. */
export interface HeaderListedPerson {
  title: string
  /** Absent where the name has no letters, so no empty circle is drawn. */
  initials?: string | null
}

/** One row of the property block, or one pin under the title (the app sends both in this shape). The status and parent
 *  rows hold the header's own buttons, which keep their menus; a link opens its item or its address. A row the app
 *  marks `editable` asks the app for its editor under the value; the page never decides which rows are. */
export interface HeaderRow {
  id: string
  label: string
  /** Whether the app opens an editor for the value, which the page asks for with `editValue`. */
  editable?: boolean
  /** The SF Symbol name of the row's icon, a key of `HeaderIcons.symbols`. */
  symbol: string
  kind:
    | 'status'
    | 'parent'
    | 'type'
    | 'items'
    | 'people'
    | 'options'
    | 'tags'
    | 'date'
    | 'url'
    | 'email'
    | 'phone'
    | 'text'
  text?: string
  /** What a pin's hover says in place of its value's words: an event's time, its zone and how far off it is. */
  help?: string
  /** A tag's words, each after a number sign. */
  texts?: string[]
  /** A choice or a list of words, each with the tone of its dot. */
  options?: { label: string; tone: string }[]
  items?: HeaderItem[]
  people?: HeaderListedPerson[]
  /** The type's chip: the key of its icon in `HeaderIcons.symbols` and the name of its tone. */
  icon?: string | null
  tone?: string | null
  /** How many values of a list a pin left out, shown as "+N" after the first two. */
  more?: number
}

/** An item that links to the one on the page. */
export interface HeaderLinked {
  item: string
  title: string
  symbol: string
  type: string
  date: string
}

/**
 * Which header the page draws, chosen by the app from the core type the item's type builds on
 * (`PageHeaderKind`). The page draws the shared parts and never decides a kind or names a type.
 *
 * - `general`: the title, the pins, the properties and Linked From.
 * - `event`: the general page. The app sends the event's time as its first pin, with the zone and a relative phrase in
 *   the pin's help.
 * - `person`: adds an avatar, a subtitle and rows whose email and phone values open `mailto:` and `tel:` links, and
 *   calls Linked From "Timeline", open by default.
 * - `reading` (`core.bookmark`, `core.media`): puts the source, published date and reading time above the title
 *   (`byline`, which no other kind has), the description under it as a dek, and the text in a larger serif face set
 *   through `body[data-header]`, at the page width the person chose like any other page. The pins follow the title.
 *
 * A fifth kind, `webpage` (`core.file.webpage`), never reaches this page: a file has no text to edit, so SwiftUI
 * draws a Web Page's title and pins natively (`WebPageItemPage`) above the sealed HTML view.
 *
 * A kind never loads anything, because the page fetches nothing from the network: a bookmark's `image_url` is not
 * drawn as a hero and leaves the property block (the inspector still shows it), and an event has no map. The fields
 * a kind draws leave the property block (`PageHeaderLead.consumed`).
 */
export type HeaderKind = 'general' | 'event' | 'person' | 'reading'

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
  /** False where the item is titled by the first line of its text (`Item.titleRule` is `.firstLine`), which the page
   *  already shows as its text, so the page draws no title and the byline leads. The toolbar and the list still show
   *  the derived title, and `bottom` and the scrolled-away report do not change. Decided from the title rule, never
   *  from a type. */
  showsTitle?: boolean
  kind: HeaderKind
  person?: HeaderPerson | null
  /** The line under the title: a person's work, or a reading item's description. */
  subtitle?: string | null
  status: HeaderPin | null
  parent: HeaderPin | null
  /** The properties the person pinned under the title, in their order, at most four. The app has left out a pin with
   *  nothing to show and any that the kind's own line already says. */
  pins: HeaderRow[]
  /** A reading item's line above the title; no other page has one. */
  byline: { source?: string | null; date: string; detail?: string | null } | null
  properties: HeaderRow[]
  /** How many rows show before the rest wait behind a button. */
  foldAfter: number
  /** The items a collection (a type playing the `container` role) holds, listed in a Contents section of its own,
   *  open, under its text. Empty for any other item, and Linked From then holds only the other links. */
  contents: HeaderLinked[]
  linked: HeaderLinked[]
  linkedFoldAfter: number
  /** How many items link to this one, for the row above the title, wherever Linked From is shown. */
  linkedCount?: number
  /** Customize Layout in the row above the title: absent where the item cannot be laid out, else whether the mode is
   *  on. The app decides both; the page only draws them and says when they are pressed. */
  layoutOn?: boolean | null
  /** False where the page has no text to write, so the page draws no empty editor (`body[data-text='none']`): a
   *  collection with no text sends it. An empty editor only invites typing that a connector holding the item puts
   *  back, and MAPP cannot tell a connector's item from the person's until Marfa marks them read only (marfa issue
   *  2415). */
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
  /** How many lines the title shows before an ellipsis cuts it, while it is not being edited. */
  titleLines: number
  chips?: HeaderChipStyle
}

/** A symbol the app drew, as an image the page uses as a mask so it takes the text's color. */
export interface HeaderIcon {
  url: string
  width: number
  height: number
}

export interface HeaderIcons {
  plus: HeaderIcon
  indicator: HeaderIcon
  /** The symbols of the property rows and of the types, by SF Symbol name. */
  symbols: Record<string, HeaderIcon>
}

export interface HeaderLabels {
  untitled: string
  title: string
  status: string
  discardChanges: string
  propertyRejected: string
  parentRejected: string
  linkedFrom: string
  customizeLayout: string
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
  status: 'Status',
  discardChanges: 'Discard Changes',
  propertyRejected: 'The value could not be saved. Please try again.',
  parentRejected: 'The connection could not be removed.',
  linkedFrom: 'Linked From',
  customizeLayout: 'Customize Layout',
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

/** Gives a chip the tone the app named, from the custom properties the app sent (`--tone-<name>`); the page chooses no
 *  color. A name that is not a word leaves the chip with no tone. */
function useTone(node: HTMLElement, name: string | null | undefined) {
  const tones = ['--tone', '--tone-ink', '--tone-mark', '--tone-chip']
  if (!name || !/^[a-z]+$/.test(name)) {
    for (const property of tones) node.style.removeProperty(property)
    return
  }
  node.style.setProperty('--tone', `var(--tone-${name})`)
  node.style.setProperty('--tone-ink', `var(--tone-${name}-ink)`)
  node.style.setProperty('--tone-mark', `var(--tone-${name}-mark)`)
  node.style.setProperty('--tone-chip', `var(--tone-${name}-chip)`)
}

/** A symbol the app drew, as a mask in the tone's color. */
function maskSymbol(node: HTMLElement, icon: HeaderIcon | undefined) {
  node.hidden = !icon
  if (!icon) return
  node.style.setProperty('-webkit-mask-image', `url("${icon.url}")`)
  node.style.maskImage = `url("${icon.url}")`
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
    row?: string,
  ) {
    this.root = element('section', `item-linked ${className}`, parent)
    this.toggle = element('button', 'item-linked-toggle', this.root)
    this.toggle.type = 'button'
    if (row) this.toggle.dataset.row = row
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
    this.root.setAttribute('aria-label', name)
    element('span', 'item-linked-title', this.toggle).textContent = name
    element('span', 'item-linked-count', this.toggle).textContent = String(items.length)
    element('span', 'item-chevron', this.toggle).setAttribute('aria-hidden', 'true')
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
 *  menu. The header belongs to MAPP's page, not to Inkkit; do not move it back into a native overlay that follows
 *  WebKit's scrolling.
 *
 *  Under the title the header draws the pins the app sends (`HeaderModel.pins`, at most four, each a key with its icon
 *  above its value, in a slot of a fixed width), then the property block: the rows Swift sends (`HeaderRow`, one model for every item), folded after
 *  `foldAfter` rows with "Show N More" expanding in place, and "Show Less" once expanded. The status, in a pin or a
 *  row, and the parent, in a row, are one button each, moved into place with its menu unchanged. A link value posts
 *  `openItem` or `openLink`; nothing else here is edited. A pin that is a list shows what the app sent, and its
 *  "+N". The layout of the pins follows the width of the page's column, by container query (`style.css`).
 *
 *  Linked From (a folded section of the items that link to this one) and a collection's Contents are drawn in the
 *  footer, under the text. */
export class ItemHeader {
  private model?: HeaderModel
  private readonly labels: HeaderLabels
  private readonly tools: HTMLDivElement
  private readonly linkedTool: HTMLButtonElement
  private readonly layoutTool: HTMLButtonElement
  private readonly lead: HTMLDivElement
  private readonly avatar: HTMLSpanElement
  private readonly title: HTMLDivElement
  private readonly subtitle: HTMLParagraphElement
  private readonly titleError: HTMLDivElement
  private readonly titleRefusal: HTMLParagraphElement
  private readonly byline: HTMLDivElement
  private readonly pins: HTMLDListElement
  private readonly pinsBox: HTMLDivElement
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
    // The row above the title takes no room of its own (`style.css`), so it appears under the pointer without moving the
    // page, and it is in the page for the keyboard and for VoiceOver always.
    this.tools = element('div', 'item-tools', root)
    this.linkedTool = this.toolButton('ItemLinkedFromTool', () =>
      postToHost({ type: 'showLinked' }),
    )
    this.layoutTool = this.toolButton('ItemCustomizeLayoutTool', () =>
      postToHost({ type: 'toggleLayout' }),
    )
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
    this.pinsBox = element('div', 'item-pins', root)
    this.pins = element('dl', 'item-pin-list', this.pinsBox)
    const buttons = document.createElement('div')
    this.statusPin = this.menuPin('ItemStatusPin', 'status', buttons)
    this.statusPin.setAttribute('aria-label', this.labels.status)
    this.parentPin = this.menuPin('ItemParentPin', 'parent', buttons)
    this.properties = element('dl', 'item-props', root)
    dragRows(this.properties, (row, before) => this.moveRow(row, before))
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
    this.linked = new LinkedSection(footer, 'item-linked-from', redraw, glyph, '#linked')

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
    // The app sends the header before the window has sized the page. WebKit keeps the row heights of that first
    // layout at no width, where a shrinking value breaks after every character, so the rows are drawn anew once the
    // page has a width.
    window
      .matchMedia?.('(prefers-color-scheme: dark)')
      .addEventListener?.('change', () => this.applyChips())
    let width = window.innerWidth
    window.addEventListener('resize', () => {
      const had = width
      width = window.innerWidth
      if (had > 0 || width === 0) return
      this.drawn = ''
      this.redraw()
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

  /** Whether the footer holds anything, so the text above it can end where the text does. While it does, Linked
   *  From follows the text directly (`main.ts` sets `--inkkit-min-height` to zero); the text fills the window only
   *  when it holds nothing. */
  get hasFooterItems(): boolean {
    return !!this.model && (this.model.contents.length > 0 || this.model.linked.length > 0)
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
    this.root.style.setProperty('--title-lines', String(model.titleLines))
    this.applyChips()
    document.body.dataset.text = model.showsText ? 'shown' : 'none'
    this.root.dataset.kind = model.kind
    document.body.dataset.header = model.hidden ? 'general' : model.kind
    this.subtitle.textContent = model.subtitle ?? ''
    this.subtitle.hidden = !model.subtitle
    this.title.hidden = model.showsTitle === false
    this.root.dataset.title = model.showsTitle === false ? 'derived' : 'own'
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

  /** Gives the title of `item` the keyboard with its text selected, so typing replaces it, for a new item. Held until
   *  the header shows that item and can be edited; `focus`, `focusText` and `load` cancel the wait. Used once. */
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

  /** Sets the chip looks the app sent for the appearance the page is in, on the header and the footer, with the scale
   *  that follows the interface's text size. A tone or size the app changes reaches an open page this way. */
  private applyChips() {
    const model = this.model
    if (!model) return
    const dark = window.matchMedia?.('(prefers-color-scheme: dark)').matches ?? false
    const looks = (dark ? model.chips?.dark : model.chips?.light) ?? {}
    for (const node of [this.root, this.footer]) {
      for (const [name, value] of Object.entries(looks)) node.style.setProperty(name, value)
    }
    this.root.style.setProperty('--chip-scale', String(model.interfaceTextSize / 13))
  }

  setIcons(icons: HeaderIcons) {
    const style = this.root.style
    const footerStyle = this.footer.style
    this.symbols = icons.symbols ?? {}
    this.drawParentIcon()
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

  /** The parent chip's symbol is the icon of the parent's own type. */
  private drawParentIcon() {
    const icon = this.model?.parent?.icon
    maskSymbol(
      this.parentPin.querySelector<HTMLElement>('.item-icon-parent')!,
      icon ? this.symbols[icon] : undefined,
    )
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
    pin.querySelector('.item-pin-label')!.textContent = model?.label ?? ''
    // The status ring is drawn here, from the tone and fill the app chose, since the catalogue holds no colors.
    const mark = pin.querySelector<HTMLElement>('.item-status-mark')
    if (mark) {
      const tone = model?.mark?.tone ?? 'neutral'
      mark.dataset.tone = tone
      mark.dataset.fill = model?.mark?.fill ?? 'none'
      if (tone !== 'neutral' && /^[a-z]+$/.test(tone))
        mark.style.setProperty('--mark', `var(--tone-${tone})`)
      else mark.style.removeProperty('--mark')
    }
    if (pin === this.parentPin) {
      useTone(pin, model?.tone)
      this.drawParentIcon()
    }
  }

  private menuPin(id: string, menu: HeaderMenu, parent: HTMLElement): HTMLButtonElement {
    const pin = element('button', 'item-pin item-chip item-menu-pin', parent)
    pin.type = 'button'
    pin.id = id
    pin.setAttribute('aria-haspopup', 'menu')
    // The status is a status chip; the parent is a linked item and looks like one.
    pin.dataset.kind = menu === 'status' ? 'status' : 'link'
    // An empty status shows a plus where a filled one shows its mark.
    const symbol =
      menu === 'status'
        ? element('span', 'item-pin-symbol item-status-mark', pin)
        : element('span', 'item-pin-symbol item-chip-mark item-icon-parent', pin)
    symbol.setAttribute('aria-hidden', 'true')
    element('span', 'item-pin-icon item-icon-plus', pin).setAttribute('aria-hidden', 'true')
    element('span', 'item-pin-label item-chip-text', pin)
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
  private glyph(name: string, parent: HTMLElement, scale = 1): HTMLElement {
    const icon = this.symbols[name]
    const node = element('span', 'item-glyph', parent)
    node.setAttribute('aria-hidden', 'true')
    if (!icon) return node
    node.style.width = `${icon.width * scale}px`
    node.style.height = `${icon.height * scale}px`
    node.style.setProperty('-webkit-mask-image', `url("${icon.url}")`)
    node.style.maskImage = `url("${icon.url}")`
    return node
  }

  private toolButton(id: string, action: () => void): HTMLButtonElement {
    const button = element('button', 'item-tool', this.tools)
    button.type = 'button'
    button.id = id
    button.addEventListener('click', action)
    return button
  }

  /** The row above the title: how many items link here, and Customize Layout, lit while the mode is on. */
  private drawTools(model: HeaderModel) {
    const count = model.linkedCount ?? 0
    this.linkedTool.hidden = count === 0
    this.linkedTool.replaceChildren()
    this.glyph('arrow.down.left', this.linkedTool)
    element('span', 'item-tool-text', this.linkedTool).textContent =
      `${count} ${this.labels.linkedFrom}`
    const on = model.layoutOn
    this.layoutTool.hidden = on === undefined || on === null
    this.layoutTool.replaceChildren()
    this.glyph('rectangle.split.2x1', this.layoutTool)
    element('span', 'item-tool-text', this.layoutTool).textContent = this.labels.customizeLayout
    this.layoutTool.setAttribute('aria-pressed', String(on === true))
    this.tools.hidden = this.linkedTool.hidden && this.layoutTool.hidden
    this.root.dataset.layout = on ? 'on' : 'off'
  }

  /** An address or number as plain text that opens it, in the link color. */
  private link(parent: HTMLElement, text: string, open: () => void, href: string): void {
    const link = element('a', 'item-link', parent)
    link.textContent = text
    link.href = href
    link.setAttribute('role', 'link')
    link.addEventListener('click', (event) => {
      event.preventDefault()
      open()
    })
  }

  /** A chip of one kind of value. The text is set as text, never as markup. */
  private chip(parent: HTMLElement, kind: string, text: string, tone?: string | null) {
    const chip = element('span', 'item-chip', parent)
    chip.dataset.kind = kind
    useTone(chip, tone)
    if (kind === 'option')
      element('span', 'item-chip-dot', chip).setAttribute('aria-hidden', 'true')
    if (kind === 'tag') {
      element('span', 'item-chip-hash', chip).textContent = '#'
      chip.lastElementChild!.setAttribute('aria-hidden', 'true')
    }
    element('span', 'item-chip-text', chip).textContent = text
    return chip
  }

  /** A person's initials and name. The name is set as text, never as markup. */
  private person<T extends 'button' | 'span'>(
    parent: HTMLElement,
    tag: T,
    target: { title: string; initials?: string | null },
  ) {
    const person = element(tag, 'item-person', parent)
    // A name with no letters has no circle, not an empty one.
    if (target.initials) {
      element('span', 'item-person-initials', person).textContent = target.initials
      person.firstElementChild!.setAttribute('aria-hidden', 'true')
    }
    element('span', 'item-chip-text', person).textContent = target.title
    return person
  }

  /** An item a row links to: its type's mark in its own tone and its title, or a person's initials and name. */
  private linkedItem(parent: HTMLElement, target: HeaderItem) {
    const open = () => postToHost({ type: 'openItem', item: target.item })
    if (target.kind === 'person') {
      const person = this.person(parent, 'button', target)
      person.type = 'button'
      person.addEventListener('click', open)
      return
    }
    const link = element('button', 'item-chip', parent)
    link.type = 'button'
    link.dataset.kind = 'link'
    useTone(link, target.tone)
    const symbol = this.symbols[target.symbol]
    if (symbol) {
      const mark = element('span', 'item-chip-mark', link)
      mark.setAttribute('aria-hidden', 'true')
      maskSymbol(mark, symbol)
    }
    element('span', 'item-chip-text', link).textContent = target.title
    link.addEventListener('click', open)
  }

  /** Draws the byline, the pins, the property block and the linked items from the model. */
  private redraw() {
    const model = this.model
    if (!model) return
    const key = JSON.stringify([
      model.kind,
      model.person,
      model.byline,
      model.pins,
      model.properties,
      model.contents,
      model.linked,
      model.linkedCount,
      model.layoutOn,
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

    this.drawTools(model)
    // Where a reading item came from, when it was published and how long it takes, as one quiet line.
    this.byline.replaceChildren()
    let first = true
    for (const part of [model.byline?.source, model.byline?.date, model.byline?.detail]) {
      if (!part) continue
      if (!first)
        element('span', 'item-byline-dot', this.byline).setAttribute('aria-hidden', 'true')
      first = false
      element('span', 'item-byline-part', this.byline).textContent = part
    }
    this.byline.hidden = first

    this.pins.replaceChildren(...model.pins.map((pin) => this.pin(pin, model)))
    this.pinsBox.hidden = model.pins.length === 0

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

  /** What the kind adds above the properties: a person's avatar. */
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
  }

  private row(row: HeaderRow, model: HeaderModel): HTMLElement {
    const entry = element('div', 'item-prop')
    entry.dataset.row = row.id
    const term = element('dt', 'item-prop-label', entry)
    const symbol = element('span', 'item-prop-symbol', term)
    this.glyph(row.symbol, symbol)
    this.glyph(rowGrip, symbol).classList.add('item-prop-grip')
    const name = element('span', 'item-prop-name', term)
    name.textContent = row.label
    name.title = row.label
    const value = element('dd', 'item-prop-value', entry)
    this.value(value, row, model)
    this.editor(entry, term, value, row, model)
    return entry
  }

  /** Makes an editable row ask for its editor. The label always does, so a value that is itself a link keeps its click;
   *  the value does too where it holds no link. The editor opens under the value either way. */
  private editor(
    entry: HTMLElement,
    term: HTMLElement,
    value: HTMLElement,
    row: HeaderRow,
    model: HeaderModel,
  ) {
    if (!row.editable) return
    entry.classList.add('editable')
    const open = () => this.openEditor(value, row.id)
    const reach = (node: HTMLElement) => {
      node.tabIndex = 0
      node.setAttribute('role', 'button')
      node.addEventListener('click', open)
      node.addEventListener('keydown', (event) => {
        if (event.key !== 'Enter' && event.key !== ' ') return
        event.preventDefault()
        open()
      })
    }
    reach(term)
    term.setAttribute('aria-label', row.label)
    if (!value.querySelector('a, button')) {
      reach(value)
      value.setAttribute('aria-label', `${row.label}: ${this.wholeValue(row, model)}`)
    }
  }

  /** A pin: its key with the row's icon at 11 points, above its value on one line, cut with an ellipsis where it is
   *  longer than the slot, with the whole of each in the help. The status pin is the same button as the status row's. */
  private pin(row: HeaderRow, model: HeaderModel): HTMLElement {
    const entry = element('div', 'item-pin-item')
    entry.dataset.pin = row.id
    entry.dataset.kind = row.kind
    const key = element('dt', 'item-pin-key', entry)
    key.title = row.label
    this.glyph(row.symbol, key, 11 / 13)
    element('span', 'item-pin-name', key).textContent = row.label
    const value = element('dd', 'item-pin-value', entry)
    value.title = this.wholeValue(row, model)
    this.value(value, row, model, true)
    this.editor(entry, key, value, row, model)
    if (row.more) {
      const more = element('span', 'item-pin-more', value)
      more.textContent = `+${row.more}`
      more.title = String(row.more)
    }
    return entry
  }

  /** The words of a pin's value, for its help. */
  private wholeValue(row: HeaderRow, model: HeaderModel): string {
    if (row.help) return row.help
    switch (row.kind) {
      case 'status':
        return model.status?.label ?? ''
      case 'parent':
        return model.parent?.label ?? ''
      case 'items':
        return (row.items ?? []).map((item) => item.title).join(', ')
      case 'people':
        return (row.people ?? []).map((person) => person.title).join(', ')
      case 'options':
        return (row.options ?? []).map((option) => option.label).join(', ')
      case 'tags':
        return (row.texts ?? []).join(', ')
      default:
        return row.text ?? ''
    }
  }

  private value(value: HTMLElement, row: HeaderRow, model: HeaderModel, pinned = false) {
    switch (row.kind) {
      case 'status':
        if (model.status) value.append(this.statusPin)
        break
      case 'parent':
        if (model.parent) value.append(this.parentPin)
        break
      case 'type': {
        const chip = this.chip(value, 'type', row.text ?? '', row.tone)
        if (pinned) chip.id = 'ItemTypePin'
        const symbol = row.icon ? this.symbols[row.icon] : undefined
        if (symbol) {
          const mark = element('span', 'item-chip-mark')
          mark.setAttribute('aria-hidden', 'true')
          maskSymbol(mark, symbol)
          chip.prepend(mark)
        }
        break
      }
      case 'items':
        for (const target of row.items ?? []) this.linkedItem(value, target)
        break
      case 'people':
        for (const person of row.people ?? []) this.person(value, 'span', person)
        break
      case 'options':
        for (const option of row.options ?? [])
          this.chip(value, 'option', option.label, option.tone)
        break
      case 'tags':
        for (const tag of row.texts ?? []) this.chip(value, 'tag', tag)
        break
      case 'url': {
        const href = row.text ?? ''
        if (/^https?:\/\//i.test(href)) this.link(value, href, () => openLink(href), href)
        else element('span', 'item-text', value).textContent = href
        break
      }
      case 'email': {
        const address = row.text ?? ''
        const href = `mailto:${address}`
        this.link(value, address, () => openLink(href), href)
        break
      }
      case 'phone': {
        const number = row.text ?? ''
        // A number is dialed as its digits and a leading plus, whatever spacing it is written with.
        const dialed = number.replace(/(?!^\+)[^\d]/g, '')
        if (dialed.replace('+', '') === '') element('span', 'item-text', value).textContent = number
        else this.link(value, number, () => openLink(`tel:${dialed}`), `tel:${dialed}`)
        break
      }
      default:
        element('span', 'item-text', value).textContent = row.text ?? ''
    }
  }

  /** The row of the property block, or Linked From, that an event's target is in, for the app to add Hide from
   *  Page to the menu WebKit is opening there; the inspector still lists it. The page leaves WebKit's own menu alone
   *  and posts `rowMenu` just before it, with the row's identifier (a field key, a relationship's field, `#tags` or
   *  `#linked`) and the item, or null over anything else. The app keeps each person's choice for a type
   *  (`PagePlacements`), and a hidden row is simply not sent. */
  rowAt(target: EventTarget | null): { item: string; row: string } | null {
    const row = (target as Element | null)?.closest?.<HTMLElement>('[data-row]')?.dataset.row
    return this.model && row ? { item: this.model.item, row } : null
  }

  /** Asks the app to list a row before another. A row dropped last among those shown goes before the first folded away,
   *  so the folded rows stay where they are. */
  private moveRow(row: string, before: string | null) {
    if (!this.model) return
    const folded = this.expanded.properties
      ? undefined
      : this.model.properties[this.model.foldAfter]
    postToHost({
      type: 'moveRow',
      item: this.model.item,
      row,
      before: before ?? folded?.id ?? null,
    })
  }

  /** Asks the app for the editor of a row's or a pin's value, with the value's frame as a menu's is. */
  private openEditor(value: HTMLElement, row: string) {
    if (!this.model) return
    const rect = value.getBoundingClientRect()
    postToHost({
      type: 'editValue',
      item: this.model.item,
      row,
      rect: [rect.left, rect.top, rect.width, rect.height],
      viewportHeight: window.innerHeight,
    })
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
