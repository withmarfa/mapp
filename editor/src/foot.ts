import { postToHost } from './bridge'
import { element, maskSymbol, useTone, type HeaderIcon } from './dom'

/** One item listed at the page's foot: its mark (a task's status, any other item's type) and its title, when, and its
 *  own sub-items. The app decides every word, and how many rows there are. */
export interface FootRow {
  item: string
  title: string
  /** The icon of the item's type, a key of `HeaderIcons.symbols`. */
  symbol: string
  /** Only an item with a status has a mark, which is drawn in place of its type's icon. */
  mark?: { symbol: string; tint: 'blue' | 'secondary' | 'tertiary' }
  /** The name of the tone the item's type draws in. */
  tone?: string
  date: string
  children?: FootRow[]
  /** What the Show More that follows this row's children says, and the key it asks for more by. Absent where all show. */
  more?: string
  key?: string
}

/** What belongs to the item, under a heading with its count: the sub-items, nested, or the items that link to it. */
export interface FootSection {
  kind: 'subItems' | 'timeline' | 'linkedFrom'
  title: string
  total: number
  rows: FootRow[]
  key: string
  more?: string
}

/** The foot of the page, under the text: what the app sends as `FootSection`s. A row opens its item, a row with
 *  sub-items folds them with its arrow (`toggled` holds the rows whose arrow the person turned from its first
 *  state: a first-level row's sub-items start open and a deeper row's folded), and Show More asks the app for the next
 *  rows of its list, since the app decides how many there are (`footMore`). */
export class Foot {
  private readonly toggled = new Set<string>()

  constructor(
    private readonly root: HTMLElement,
    private readonly changed: () => void,
    private readonly glyph: (name: string, parent: HTMLElement) => void,
  ) {}

  /** What the person opened or folded, so a change to it is drawn. */
  get state(): string {
    return [...this.toggled].join(',')
  }

  /** Another item starts with every arrow as it first shows. */
  reset() {
    this.toggled.clear()
  }

  draw(item: string, sections: FootSection[], symbols: Record<string, HeaderIcon>) {
    this.root.replaceChildren(...sections.map((section) => this.section(item, section, symbols)))
  }

  private section(
    item: string,
    section: FootSection,
    symbols: Record<string, HeaderIcon>,
  ): HTMLElement {
    const root = element('section', `item-foot item-foot-${section.kind}`)
    root.setAttribute('aria-label', section.title)
    // What mentions the item is the page's Linked From, which a person may hide from the page.
    if (section.kind !== 'subItems') root.dataset.row = '#linked'
    const heading = element('div', 'item-foot-heading', root)
    heading.setAttribute('role', 'heading')
    heading.setAttribute('aria-level', '3')
    element('span', 'item-foot-title', heading).textContent = section.title
    element('span', 'item-foot-count', heading).textContent = String(section.total)
    const list = this.list(item, section.rows, 0, section.kind === 'subItems', symbols)
    root.append(list)
    if (section.more) this.moreButton(list, item, section.key, section.more, 0)
    return root
  }

  private list(
    item: string,
    rows: FootRow[],
    depth: number,
    nests: boolean,
    symbols: Record<string, HeaderIcon>,
  ): HTMLUListElement {
    const list = element('ul', 'item-foot-list')
    list.style.setProperty('--depth', String(depth))
    if (depth > 0) list.setAttribute('role', 'group')
    for (const row of rows) list.append(this.row(item, row, depth, nests, symbols))
    return list
  }

  private row(
    item: string,
    row: FootRow,
    depth: number,
    nests: boolean,
    symbols: Record<string, HeaderIcon>,
  ): HTMLElement {
    const entry = element('li', 'item-foot-row')
    const line = element('div', 'item-foot-line', entry)
    const children = row.children ?? []
    const folds = children.length > 0 || !!row.more
    // A first-level row starts open and a deeper one folded.
    const open = folds && (depth === 0) !== this.toggled.has(row.item)
    if (nests) {
      if (folds) {
        const arrow = element('button', 'item-foot-arrow', line)
        arrow.type = 'button'
        arrow.setAttribute('aria-expanded', String(open))
        arrow.setAttribute('aria-label', row.title)
        element('span', 'item-chevron item-foot-chevron', arrow).setAttribute('aria-hidden', 'true')
        arrow.addEventListener('click', () => {
          if (!this.toggled.delete(row.item)) this.toggled.add(row.item)
          this.changed()
        })
      } else {
        element('span', 'item-foot-arrow', line).setAttribute('aria-hidden', 'true')
      }
    }
    const button = element('button', 'item-foot-open', line)
    button.type = 'button'
    button.dataset.cardItem = row.item
    useTone(button, row.tone)
    button.addEventListener('click', () => postToHost({ type: 'openItem', item: row.item }))
    // The status mark and a type's icon share one slot, so the names line up whichever a row has.
    const slot = element('span', 'item-foot-slot', button)
    if (row.mark) {
      const mark = element('span', 'item-foot-mark item-status-mark', slot)
      mark.setAttribute('aria-hidden', 'true')
      const icon = symbols[row.mark.symbol]
      maskSymbol(mark, icon)
      mark.dataset.tint = row.mark.tint
      if (icon) {
        mark.style.width = `${icon.width}px`
        mark.style.height = `${icon.height}px`
      }
    } else {
      this.glyph(row.symbol, slot)
    }
    element('span', 'item-foot-name', button).textContent = row.title
    element('span', 'item-foot-date', button).textContent = row.date
    if (open) {
      const nested = this.list(item, children, depth + 1, nests, symbols)
      entry.append(nested)
      if (row.more && row.key) this.moreButton(nested, item, row.key, row.more, depth + 1)
    }
    return entry
  }

  /** The line under a list that asks the app for its next rows. */
  private moreButton(list: HTMLElement, item: string, key: string, words: string, depth: number) {
    const entry = element('li', 'item-foot-more-row', list)
    entry.style.setProperty('--depth', String(depth))
    const more = element('button', 'item-more item-foot-more', entry)
    more.type = 'button'
    more.textContent = words
    more.addEventListener('click', () => postToHost({ type: 'footMore', item, key }))
  }
}
