import type { WikiLinkPresentation } from '@aicayzer/inkkit'
import type { LinkAnswers, LinkRef } from './bridge'

/** Asks the app what these links of the item name. */
export type AskLinks = (item: string, links: LinkRef[]) => Promise<LinkAnswers | null>

/** What the app last said of a link: whether it names no note and, for a link that names one note, the image of the
 *  icon of that note's type and the name of the type's tone. */
interface Reading {
  missing: boolean
  icon?: string
  tone?: string
}

/** Decoded names can coincide even when Marfa bound the authored spellings separately. */
function keyOf(link: LinkRef): string {
  return link.raw
}

/**
 * What the page knows of the notes its links name: whether they exist, so Inkkit can draw a link to a missing note
 * differently, and the icon and tone of the type of one that does, so the person's chosen look for links can draw
 * them. Inkkit asks about each link as it draws it and wants the answer at once (`WikiLinkAdapter.resolve`),
 * but only the app can tell, and not at once. So an unknown link is drawn as a live one with no mark; the links of
 * one pass over the note go to the app together; and a link is drawn again only when an answer changes how it
 * looks. The answers belong to the note on the page and are asked again when the app says its library changed,
 * keeping the old ones until the new arrive so a link does not flicker.
 *
 * The page decides no color: a link names its tone and the app's style (`window.editor.setLinkStyle`) says what that
 * tone is under the look in force, by `--link-icon-<tone>` and `--link-tint-<tone>`.
 */
export class NoteLinkStatus {
  private item = ''
  private readonly links = new Map<string, LinkRef>()
  /** What each link of the note on the page was last answered. */
  private readonly readings = new Map<string, Reading>()
  private readonly asking = new Set<string>()
  /** The number of the latest request that named each link, so a slower earlier answer cannot replace a newer one. */
  private readonly requests = new Map<string, number>()
  private requested = 0
  private queue = new Set<string>()
  private scheduled = false
  /** Changes with the note on the page and when the page ends, so a late answer for either is dropped. */
  private epoch = 0

  constructor(
    private readonly ask: AskLinks,
    /** Draws the links to these notes again, after answers that change how one looks. */
    private readonly redraw: (targets: string[]) => void,
  ) {}

  /** What Inkkit draws for the link: `missing` once the app has said so, the icon and tint of the type of the note
   *  it names, or nothing. */
  status(link: LinkRef, item: string): ({ missing?: boolean } & WikiLinkPresentation) | undefined {
    this.adopt(item)
    if (!link.target) return undefined
    const key = keyOf(link)
    const known = this.readings.get(key)
    if (known === undefined) {
      if (!this.asking.has(key)) this.want(key, link)
      return undefined
    }
    if (known.missing) return { missing: true }
    const { icon, tone } = known
    if (icon === undefined && tone === undefined) return undefined
    return {
      ...(icon === undefined ? {} : { icon }),
      // The tone is a word the app named and the look gives it a color; without one the icon takes the text's.
      ...(tone === undefined ? {} : { iconColor: `var(--link-icon-${tone}, currentcolor)` }),
      ...(tone === undefined ? {} : { tint: `var(--link-tint-${tone}, transparent)` }),
    }
  }

  /** The app's library changed, so every answer is asked for again. */
  refresh(): void {
    for (const key of [...this.readings.keys(), ...this.asking])
      this.want(key, this.links.get(key)!)
  }

  /** The page is going; nothing more is sent or drawn. */
  end(): void {
    this.reset('')
  }

  private adopt(item: string): void {
    if (item !== this.item) this.reset(item)
  }

  private reset(item: string): void {
    this.item = item
    this.epoch++
    this.links.clear()
    this.readings.clear()
    this.asking.clear()
    this.requests.clear()
    this.queue = new Set()
  }

  private want(key: string, link: LinkRef): void {
    this.links.set(key, link)
    this.queue.add(key)
    if (this.scheduled) return
    this.scheduled = true
    // Every link of a note is drawn in one pass, so the links wanted by then go in one request.
    queueMicrotask(() => this.send())
  }

  private send(): void {
    this.scheduled = false
    const keys = [...this.queue]
    this.queue = new Set()
    if (keys.length === 0) return
    const { item, epoch } = this
    const request = ++this.requested
    for (const key of keys) {
      this.asking.add(key)
      this.requests.set(key, request)
    }
    const links = keys.map((key) => this.links.get(key)!)
    void this.ask(item, links).then(
      (answers) => this.take(keys, answers, epoch, request),
      () => this.take(keys, null, epoch, request),
    )
  }

  private take(keys: string[], answers: LinkAnswers | null, epoch: number, request: number): void {
    if (epoch !== this.epoch) return
    const changed = new Set<string>()
    for (const [index, key] of keys.entries()) {
      // A link asked again since is still being asked, and its newer answer is the one to take.
      if (this.requests.get(key) !== request) continue
      this.asking.delete(key)
      const answer = answers?.links[index]
      if (answer === undefined) continue
      const icon = answer.icon === undefined ? undefined : answers!.icons.get(answer.icon)
      const reading: Reading = answer.missing
        ? { missing: true }
        : {
            missing: false,
            ...(icon === undefined ? {} : { icon }),
            ...(answer.tone === undefined ? {} : { tone: answer.tone }),
          }
      // A link never answered was drawn as a live one with no mark.
      if (!same(this.readings.get(key) ?? { missing: false }, reading)) {
        changed.add(this.links.get(key)!.target)
      }
      this.readings.set(key, reading)
    }
    if (changed.size > 0) this.redraw([...changed])
  }
}

function same(a: Reading, b: Reading): boolean {
  return a.missing === b.missing && a.icon === b.icon && a.tone === b.tone
}
