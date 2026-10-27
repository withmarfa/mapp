import { InkKitError, type FilePresentation } from '@aicayzer/inkkit'
import { askPicture, type PictureAnswer, type PictureAsk } from './bridge'

/** The words a picture's card and the bar above the text use. The app supplies them in the person's language. */
export interface PictureWords {
  loadPicture?: string
  loadingPicture?: string
  picturesOff?: string
  loadOnePicture?: string
  /** Has `%lld` where the number of pictures goes. */
  loadPictures?: string
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
    private waitingChanged: (count: number, label: string) => void,
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
    let state = this.states.get(address)
    if (!state)
      state = await this.request(context.documentId, address, this.cacheOnly ? 'cached' : 'drawing')
    if (context.signal.aborted) return { kind: 'file', label: shown }
    return this.card(address, shown, state)
  }

  private card(address: string, shown: string, state: PictureState): FilePresentation {
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
        return { kind: 'file', label: `${host}: ${this.words.loadPicture ?? 'Load Picture'}` }
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
        if (remembered) this.states.set(address, state)
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

  /** The app's setting changed, or the app wants these asked again: the pictures that were waiting or turned off
   *  are asked about anew. A picture already loaded, or refused for a reason that stays, is left as it is. */
  changed(addresses?: string[]) {
    const wanted = addresses ? new Set(addresses) : null
    const again: string[] = []
    for (const address of this.live.keys()) {
      if (wanted && !wanted.has(address)) continue
      const kind = this.states.get(address)?.kind
      if (kind === 'waiting' || kind === 'off' || kind === undefined) {
        this.states.delete(address)
        again.push(address)
      }
    }
    for (const key of [...this.asking.keys()]) this.asking.delete(key)
    if (again.length) this.redraw(again)
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
    const label =
      count === 1
        ? (this.words.loadOnePicture ?? 'Load 1 Picture')
        : (this.words.loadPictures ?? 'Load %lld Pictures').replace('%lld', String(count))
    this.waitingChanged(count, label)
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

function hostOf(address: string): string {
  try {
    return new URL(address).host
  } catch {
    return address
  }
}
