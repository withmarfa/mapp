import type { LinkRef } from './bridge'

/** Asks the app which of these links of the item name no note. */
export type AskMissing = (item: string, links: LinkRef[]) => Promise<boolean[] | null>

/** Decoded names can coincide even when Marfa bound the authored spellings separately. */
function keyOf(link: LinkRef): string {
  return link.raw
}

/**
 * What the page knows of whether the notes its links name exist, so Inkkit can draw a link to a missing note
 * differently. Inkkit asks about each link as it draws it and wants the answer at once (`WikiLinkAdapter.resolve`),
 * but only the app can tell, and not at once. So an unknown link is drawn as a live one; the links of one pass
 * over the note go to the app together; and a link is drawn again only when an answer changes how it looks. The
 * answers belong to the note on the page and are asked again when the app says its library changed, keeping the
 * old ones until the new arrive so a link does not flicker.
 */
export class NoteLinkStatus {
  private item = ''
  private readonly links = new Map<string, LinkRef>()
  /** Whether each link of the note on the page names no note, as last answered. */
  private readonly missing = new Map<string, boolean>()
  private readonly asking = new Set<string>()
  private queue = new Set<string>()
  private scheduled = false
  /** Changes with the note on the page and when the page ends, so a late answer for either is dropped. */
  private epoch = 0

  constructor(
    private readonly ask: AskMissing,
    /** Draws the links to these notes again, after answers that change how one looks. */
    private readonly redraw: (targets: string[]) => void,
  ) {}

  /** What Inkkit draws for the link: `missing` once the app has said so, otherwise nothing. */
  status(link: LinkRef, item: string): { missing?: boolean } | undefined {
    this.adopt(item)
    if (!link.target) return undefined
    const key = keyOf(link)
    const known = this.missing.get(key)
    if (known === undefined) {
      if (!this.asking.has(key)) this.want(key, link)
      return undefined
    }
    return known ? { missing: true } : undefined
  }

  /** The app's library changed, so every answer is asked for again. */
  refresh(): void {
    for (const key of [...this.missing.keys(), ...this.asking]) this.want(key, this.links.get(key)!)
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
    this.missing.clear()
    this.asking.clear()
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
    for (const key of keys) this.asking.add(key)
    const links = keys.map((key) => this.links.get(key)!)
    void this.ask(item, links).then(
      (answers) => this.take(keys, answers, epoch),
      () => this.take(keys, null, epoch),
    )
  }

  private take(keys: string[], answers: boolean[] | null, epoch: number): void {
    if (epoch !== this.epoch) return
    const changed = new Set<string>()
    for (const [index, key] of keys.entries()) {
      this.asking.delete(key)
      const missing = answers?.[index]
      if (missing === undefined) continue
      // A link never answered was drawn as a live one.
      if ((this.missing.get(key) ?? false) !== missing) changed.add(this.links.get(key)!.target)
      this.missing.set(key, missing)
    }
    if (changed.size > 0) this.redraw([...changed])
  }
}
