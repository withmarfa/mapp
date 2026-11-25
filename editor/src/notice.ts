import type { HeaderIcon, HeaderIcons } from './header'
import { maskWith } from './symbol'

/** One line the page says when something is not ordinary, as the app words it (`PageNotice`): its kind, its symbol among
 *  the images the app sends, its words and at most one action. The page decides none of it. */
export interface NoticeModel {
  kind: string
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
  /** The person chose the notice's one action. */
  action(kind: string): void
  /** The person put the notice away. */
  close(): void
}

/**
 * The line above the head, and the reason under it where the text is withheld. The app's notice wins over the
 * pictures' own, which the page counts itself, so a page never says two things at once. A live region the screen
 * reader hears once: the line is built again only when what it says changes, so a redraw of the head repeats nothing.
 */
export class PageNoticeLine {
  private app: NoticeModel | null = null
  private pictures: NoticeModel | null = null
  private icons: HeaderIcons | undefined
  private shown = ''

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

  setApp(model: NoticeModel | null) {
    this.app = model
    this.render()
  }

  setPictures(model: NoticeModel | null) {
    this.pictures = model
    this.render()
  }

  setIcons(icons: HeaderIcons) {
    this.icons = icons
    this.shown = ''
    this.render()
  }

  private render() {
    const model = this.app ?? this.pictures
    const icon = model ? this.icons?.symbols?.[model.symbol] : undefined
    const close = model?.closable ? this.icons?.symbols?.xmark : undefined
    // The symbols arrive with the head, and a line is not drawn before its own has come.
    const key = model && icon ? JSON.stringify([model, !!close]) : ''
    const reason = this.app?.reason ?? ''
    this.renderReason(reason)
    if (key === this.shown) return
    this.shown = key
    this.root.replaceChildren()
    if (!model || !icon) return
    this.root.append(this.line(model, icon, close))
  }

  private renderReason(reason: string) {
    if (this.reasonRoot.textContent === reason) return
    this.reasonRoot.textContent = reason
  }

  private line(model: NoticeModel, icon: HeaderIcon, close: HeaderIcon | undefined): HTMLElement {
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
      action.addEventListener('click', () => this.events.action(model.kind))
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
    }
    return line
  }
}
