/** Asks the app which of these names, spelled as the links of the item spell them, no note answers to. */
export type AskMissing = (item: string, names: string[]) => Promise<boolean[] | null>

/**
 * What the page knows of whether the notes its links name exist, so InkKit can draw a link to a missing note
 * differently. InkKit asks about each link as it draws it and wants the answer at once (`WikiLinkAdapter.resolve`),
 * but only the app can tell, and not at once. So an unknown link is drawn as a live one; the names asked about
 * in one pass over the note go to the app together; and a link is drawn again only when an answer changes how
 * it looks. The answers belong to the note on the page and are asked again when the app says its library changed,
 * keeping the old ones until the new arrive so a link does not flicker.
 */
export class NoteLinkStatus {
  private item = ''
  /** Whether each name used in the note on the page names no note, as last answered. */
  private readonly missing = new Map<string, boolean>()
  private readonly asking = new Set<string>()
  private queue = new Set<string>()
  private scheduled = false
  /** Changes with the note on the page and when the page ends, so a late answer for either is dropped. */
  private epoch = 0

  constructor(
    private readonly ask: AskMissing,
    /** Draws the links again, after answers that change how one looks. */
    private readonly redraw: () => void,
  ) {}

  /** What InkKit draws for the link: `missing` once the app has said so, otherwise nothing. */
  status(name: string, item: string): { missing?: boolean } | undefined {
    this.adopt(item)
    if (!name) return undefined
    const known = this.missing.get(name)
    if (known === undefined) {
      if (!this.asking.has(name)) this.want(name)
      return undefined
    }
    return known ? { missing: true } : undefined
  }

  /** The app's library changed, so every answer is asked for again. */
  refresh(): void {
    for (const name of [...this.missing.keys(), ...this.asking]) this.want(name)
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
    this.missing.clear()
    this.asking.clear()
    this.queue = new Set()
  }

  private want(name: string): void {
    this.queue.add(name)
    if (this.scheduled) return
    this.scheduled = true
    // Every link of a note is drawn in one pass, so the names wanted by then go in one request.
    queueMicrotask(() => this.send())
  }

  private send(): void {
    this.scheduled = false
    const names = [...this.queue]
    this.queue = new Set()
    if (names.length === 0) return
    const { item, epoch } = this
    for (const name of names) this.asking.add(name)
    void this.ask(item, names).then(
      (answers) => this.take(names, answers, epoch),
      () => this.take(names, null, epoch),
    )
  }

  private take(names: string[], answers: boolean[] | null, epoch: number): void {
    if (epoch !== this.epoch) return
    let changed = false
    for (const [index, name] of names.entries()) {
      this.asking.delete(name)
      const missing = answers?.[index]
      if (missing === undefined) continue
      // A name never answered was drawn as a live link.
      if ((this.missing.get(name) ?? false) !== missing) changed = true
      this.missing.set(name, missing)
    }
    if (changed) this.redraw()
  }
}
