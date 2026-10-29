import { InkKitError, type FilePresentation } from '@aicayzer/inkkit'
import { askPicture, type PictureAnswer, type PictureAsk } from './bridge'

/** The words a picture's card and the callout above the text use. The app supplies them in the person's language. */
export interface PictureWords {
  /** Has `%@` where the picture's website goes. */
  pictureFrom?: string
  loadingPicture?: string
  picturesOff?: string
  /** The callout's button for one waiting picture, and for several. */
  loadOnePicture?: string
  loadPictures?: string
  /** The callout's sentence for one waiting picture. */
  pictureNotLoaded?: string
  /** The callout's sentence for several, with `%lld` where the number of pictures goes. */
  picturesNotLoaded?: string
}

/** A picture at a web address `http` or `https`, which is the only kind of embed whose target is one. */
export function webAddress(target: string): string | null {
  return /^https?:\/\//i.test(target) ? target : null
}

/** What the page knows of one picture. Nothing is fetched by the page: the app answers each question by the
 *  Remote Pictures setting, so a picture is `waiting` until the person chooses it, unless the app says otherwise. */
type PictureState =
  | { kind: 'loading' }
  | { kind: 'loaded'; url: string }
  | { kind: 'waiting' }
  | { kind: 'off' }
  | { kind: 'refused'; reason: string; retry: boolean }

/** Where the page asks the app about a picture. */
export type Ask = typeof askPicture

/** The pictures at web addresses in the note on the page, and what each card shows. */
export class WebPictures {
  private states = new Map<string, PictureState>()
  private asking = new Map<string, Promise<PictureState>>()
  /** How many cards are drawn for each address, from resolving one to Inkkit abandoning it. */
  private live = new Map<string, number>()
  private item = ''
  private announced = -1
  private scheduled = false
  /** While true the page only wants what the app already holds, as printing and exporting do. */
  cacheOnly = false

  constructor(
    private words: PictureWords,
    /** Draws these addresses' cards again. */
    private redraw: (addresses: string[]) => void,
    /** Hears how many pictures wait for the person to load them, whenever that changes. */
    private waitingChanged: (count: number, sentence: string, button: string) => void,
    private ask: Ask = askPicture,
  ) {}

  /** A different note forgets what it was told of the last one's pictures. */
  setItem(id: string) {
    if (id === this.item) return
    this.item = id
    this.states.clear()
    this.asking.clear()
    this.schedule()
  }

  /** The card for a picture, drawn from what the app has said of it, asking the app the first time. */
  async present(
    address: string,
    label: string | undefined,
    context: { documentId: string; signal: AbortSignal },
  ): Promise<FilePresentation> {
    this.track(address, context.signal)
    const shown = label ?? address
    const alt = label?.trim()
    let state = this.states.get(address)
    if (!state)
      state = await this.request(context.documentId, address, this.cacheOnly ? 'cached' : 'drawing')
    if (context.signal.aborted) return { kind: 'file', label: shown }
    return this.card(address, shown, alt, state)
  }

  private card(
    address: string,
    shown: string,
    alt: string | undefined,
    state: PictureState,
  ): FilePresentation {
    if (state.kind === 'loaded') return { kind: 'image', url: state.url, label: shown }
    // A printed note names the picture; it says nothing of what the person could choose.
    if (this.cacheOnly) return { kind: 'file', label: shown }
    const host = hostOf(address)
    switch (state.kind) {
      case 'loading':
        return {
          kind: 'file',
          label: `${host}: ${this.words.loadingPicture ?? 'Loading Picture…'}`,
        }
      case 'off':
        return {
          kind: 'file',
          label: `${host}: ${this.words.picturesOff ?? 'Remote Pictures Are Off'}`,
        }
      case 'refused':
        return { kind: 'file', label: `${host}: ${state.reason}` }
      default:
        // The callout above the text says the picture waits; the card only says what the picture is.
        return {
          kind: 'file',
          // A function, so a `$` in the host is not read as a replacement pattern.
          label: alt || (this.words.pictureFrom ?? 'Picture from %@').replace('%@', () => host),
        }
    }
  }

  private track(address: string, signal: AbortSignal) {
    if (signal.aborted) return
    this.live.set(address, (this.live.get(address) ?? 0) + 1)
    signal.addEventListener(
      'abort',
      () => {
        const left = (this.live.get(address) ?? 1) - 1
        if (left > 0) this.live.set(address, left)
        else this.live.delete(address)
        this.schedule()
      },
      { once: true },
    )
    this.schedule()
  }

  /** Asks the app once for a picture however many cards ask at the same time, and keeps its answer, unless the
   *  note on the page has changed meanwhile or the question was only for what is held. */
  private request(item: string, address: string, ask: PictureAsk): Promise<PictureState> {
    const key = `${ask}\n${address}`
    const held = this.asking.get(key)
    if (held) return held
    const forItem = this.item
    const pending = this.ask({ item, address, ask }).then((answer) => {
      const state = stateOf(answer)
      const remembered = ask !== 'cached' || state.kind === 'loaded'
      if (this.item === forItem && this.asking.get(key) === pending) {
        this.asking.delete(key)
        // A picture the person has chosen since is loading, whatever an earlier question now answers.
        if (remembered && (ask === 'chosen' || this.states.get(address)?.kind !== 'loading'))
          this.states.set(address, state)
        this.schedule()
      }
      return state
    })
    this.asking.set(key, pending)
    return pending
  }

  /** The person chose this picture: the app fetches it unless Settings says never, and the card is drawn again. */
  async choose(address: string): Promise<boolean> {
    const state = this.states.get(address)
    if (state?.kind !== 'waiting' && !(state?.kind === 'refused' && state.retry)) return false
    this.states.set(address, { kind: 'loading' })
    this.redraw([address])
    this.schedule()
    await this.request(this.item, address, 'chosen')
    if (this.states.get(address)?.kind === 'loading') this.states.set(address, { kind: 'waiting' })
    this.redraw([address])
    this.schedule()
    return true
  }

  /** Every picture of the note that waits for the person, chosen together. */
  chooseAll() {
    for (const address of this.waiting()) void this.choose(address)
  }

  /** Whether a card's Open should open the address in the browser, which it does for a picture that is not waiting
   *  to be loaded and has nothing to try again. */
  opensInBrowser(address: string): boolean {
    const state = this.states.get(address)
    return !(
      state?.kind === 'waiting' ||
      state?.kind === 'loading' ||
      (state?.kind === 'refused' && state.retry)
    )
  }

  /** The app's setting changed: the pictures that were waiting or turned off are asked about anew. A picture
   *  already loaded, or refused, is left as it is. */
  changed() {
    this.askAgain((address) => {
      const kind = this.states.get(address)?.kind
      return kind === 'waiting' || kind === 'off' || kind === undefined
    })
  }

  /** Files saved from these web addresses came to the item, changed or went, so what the app answers for the pictures
   *  at them may differ, as `loaded` from the file or back to the website's answer. Each is asked about anew, whatever
   *  it showed, except one the person is choosing now, whose answer is still on its way. A picture at any other
   *  address is left alone, so a refusal that stays is not asked again. */
  savedChanged(sources: string[]) {
    const named = new Set(sources.map(sameAddress))
    this.askAgain(
      (address) => named.has(sameAddress(address)) && this.states.get(address)?.kind !== 'loading',
    )
  }

  private askAgain(wants: (address: string) => boolean) {
    const again = [...this.live.keys()].filter(
      (address) => wants(address) && !this.choosing(address),
    )
    // An answer still on its way for any other address is kept: dropping a chosen picture's answer would leave its card
    // waiting although it was fetched.
    for (const key of [...this.asking.keys()])
      if (again.includes(key.slice(key.indexOf('\n') + 1))) this.asking.delete(key)
    const forItem = this.item
    const ask = this.cacheOnly ? 'cached' : 'drawing'
    for (const address of again) {
      // The card and the count keep what they show until the new answer is here, so neither flickers between.
      const before = this.states.get(address)
      void this.request(forItem, address, ask).then((state) => {
        if (this.item !== forItem || sameState(before, this.states.get(address) ?? state)) return
        this.redraw([address])
      })
    }
  }

  private choosing(address: string): boolean {
    return this.states.get(address)?.kind === 'loading'
  }

  /** Draws again the cards a print left without their state, as a card drawn while only the cache was wanted is. */
  afterCacheOnly() {
    const again = [...this.live.keys()].filter((address) => !this.states.has(address))
    if (again.length) this.redraw(again)
  }

  /** The bytes of a loaded picture for a portable export. */
  async bytes(item: string, address: string): Promise<{ bytes: Uint8Array; mimeType: string }> {
    const answer = await this.ask({ item, address, ask: 'cached', export: true })
    if (!answer || answer.state !== 'loaded' || !('data' in answer))
      throw new InkKitError('image-unavailable', 'The picture could not be read.')
    return {
      bytes: Uint8Array.from(atob(answer.data), (char) => char.charCodeAt(0)),
      mimeType: answer.mimeType,
    }
  }

  /** The addresses of cards on the page whose picture waits for the person to choose it. */
  waiting(): string[] {
    return [...this.live.keys()].filter((address) => this.states.get(address)?.kind === 'waiting')
  }

  /** A card is drawn again as one is abandoned, so the count is settled after the page has finished drawing. */
  private schedule() {
    if (this.scheduled) return
    this.scheduled = true
    queueMicrotask(() => setTimeout(() => this.announce(), 0))
  }

  private announce() {
    this.scheduled = false
    const count = this.waiting().length
    if (count === this.announced) return
    this.announced = count
    this.waitingChanged(
      count,
      count === 1
        ? (this.words.pictureNotLoaded ?? '1 picture from another website isn’t loaded.')
        : (
            this.words.picturesNotLoaded ?? '%lld pictures from other websites aren’t loaded.'
          ).replace('%lld', String(count)),
      count === 1
        ? (this.words.loadOnePicture ?? 'Load Picture')
        : (this.words.loadPictures ?? 'Load Pictures'),
    )
  }
}

function stateOf(answer: PictureAnswer | null): PictureState {
  switch (answer?.state) {
    case 'loaded':
      return 'url' in answer ? { kind: 'loaded', url: answer.url } : { kind: 'waiting' }
    case 'off':
      return { kind: 'off' }
    case 'refused':
      return { kind: 'refused', reason: answer.reason, retry: answer.retry === 'true' }
    default:
      return { kind: 'waiting' }
  }
}

/** An address as the app compares a saved file's with a picture's (`SavedPictures.same`): the scheme and host in any
 *  case, the default port as none and the fragment ignored, the path and query exactly. */
export function sameAddress(address: string): string {
  const parts = /^([a-z][a-z0-9+.-]*):\/\/([^/?#]*)([^?#]*)(\?[^#]*)?/i.exec(address)
  if (!parts) return address
  const [, name = '', host = '', path = '', query = ''] = parts
  const scheme = name.toLowerCase()
  const authority = host.toLowerCase().replace(/:(\d*)$/, (_, port: string) => {
    return Number(port) === (scheme === 'https' ? 443 : 80) && port !== '' ? '' : `:${port}`
  })
  return `${scheme}://${authority}${path || '/'}${query}`
}

function sameState(a: PictureState | undefined, b: PictureState | undefined): boolean {
  return JSON.stringify(a) === JSON.stringify(b)
}

function hostOf(address: string): string {
  try {
    return new URL(address).host
  } catch {
    return address
  }
}
