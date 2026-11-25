import type { HeaderIcon, HeaderIcons } from './header'
import { maskWith } from './symbol'

/** One line the page says when something is not ordinary, as the app words it (`PageNotice`): its kind, the item it is
 *  for, its symbol among the images the app sends, its words and at most one action. The page decides none of it. */
export interface NoticeModel {
  kind: string
  /** The item the app made the notice for, which its action is for. Empty on the page's own pictures notice. */
  item?: string
  symbol: string
  words: string
  /** The action's label, when the notice has one. */
  action?: string
  /** What the page's text says beside the line, for a notice that withholds the text. */
  reason?: string
  /** Whether the person may put the line away for the page. */
  closable?: boolean
}

export interface NoticeEvents {
  /** The person chose the notice's one action, on the notice for `item`. */
  action(kind: string, item: string): void
  /** The person put the notice away. */
  close(): void
}

/**
 * The lines above the head, and the reason under them where the text is withheld. The app's notices win over the
 * pictures' own, which the page counts itself, so a page never says two things at once unless the app does. A live
 * region the screen reader hears once: the lines are built again only when what they say changes, so a redraw of the
 * head, or a new set of symbols, repeats nothing.
 */
export class PageNoticeLine {
  private app: NoticeModel[] = []
  private pictures: NoticeModel | null = null
  private icons: HeaderIcons | undefined
  private shown = ''
  private marks: { glyph: HTMLElement; symbol: string; close?: HTMLElement }[] = []

  constructor(
    private readonly root: HTMLElement,
    private readonly reasonRoot: HTMLElement,
    private readonly events: NoticeEvents,
    private readonly closeLabel: () => string,
  ) {
    root.setAttribute('role', 'status')
    root.setAttribute('aria-live', 'polite')
    root.setAttribute('aria-atomic', 'true')
  }

  setApp(models: NoticeModel[]) {
    this.app = models
    this.render()
  }

  setPictures(model: NoticeModel | null) {
    this.pictures = model
    this.render()
  }

  setIcons(icons: HeaderIcons) {
    this.icons = icons
    this.render()
  }

  private render() {
    const models = this.app.length > 0 ? this.app : this.pictures ? [this.pictures] : []
    const symbols = this.icons?.symbols
    // The symbols arrive with the head, and a line is not drawn before its own has come.
    const ready = models.length > 0 && models.every((model) => symbols?.[model.symbol])
    const key = ready
      ? JSON.stringify(models.map((model) => [model, !!model.closable && !!symbols?.xmark]))
      : ''
    this.renderReason(this.app.find((model) => model.reason)?.reason ?? '')
    if (key === this.shown) return this.refreshMarks()
    this.shown = key
    this.root.replaceChildren()
    this.marks = []
    if (!ready || !symbols) return
    for (const model of models) {
      const icon = symbols[model.symbol]
      if (icon) this.root.append(this.line(model, icon, model.closable ? symbols.xmark : undefined))
    }
  }

  /** A new set of symbols draws the lines already shown again in place, so the live region is not rebuilt. */
  private refreshMarks() {
    const symbols = this.icons?.symbols
    for (const mark of this.marks) {
      const icon = symbols?.[mark.symbol]
      if (icon) maskWith(mark.glyph, icon)
      if (mark.close && symbols?.xmark) maskWith(mark.close, symbols.xmark)
    }
  }

  private renderReason(reason: string) {
    if (this.reasonRoot.textContent === reason) return
    this.reasonRoot.textContent = reason
  }

  private line(model: NoticeModel, icon: HeaderIcon, close: HeaderIcon | undefined): HTMLElement {
    let closeMark: HTMLElement | undefined
    const line = document.createElement('div')
    line.className = 'page-notice'
    line.dataset.kind = model.kind
    const glyph = document.createElement('span')
    glyph.className = 'page-notice-icon'
    glyph.setAttribute('aria-hidden', 'true')
    maskWith(glyph, icon)
    const words = document.createElement('span')
    words.className = 'page-notice-words'
    words.textContent = model.words
    line.append(glyph, words)
    if (model.action) {
      const action = document.createElement('button')
      action.type = 'button'
      action.className = 'page-notice-action'
      action.textContent = model.action
      action.addEventListener('click', () => this.events.action(model.kind, model.item ?? ''))
      line.append(action)
    }
    if (close) {
      const button = document.createElement('button')
      button.type = 'button'
      button.className = 'page-notice-close'
      const label = this.closeLabel()
      button.setAttribute('aria-label', label)
      button.title = label
      const mark = document.createElement('span')
      mark.className = 'page-notice-close-icon'
      mark.setAttribute('aria-hidden', 'true')
      maskWith(mark, close)
      button.append(mark)
      button.addEventListener('click', () => this.events.close())
      line.append(button)
      closeMark = mark
    }
    this.marks.push({ glyph, symbol: model.symbol, close: closeMark })
    return line
  }
}
