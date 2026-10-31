import type { CaretState, FindState } from './editor'
import type { HeaderMenu } from './header'

/** An embed as the note's text holds it, such as `![[photo.png|400]]` or `![](a.png)`, which the app
 *  matches against the embeds Marfa bound for the note. The text is exactly as written (`FileReference.raw`: alias,
 *  size suffix, escapes, a table cell's `\|`), and the page applies no rule of its own for what an embed names. */
export type EmbedRequest = { item: string; text: string; export?: boolean }

/** A file an embed names, as the app serves it: `url` and `icon` load through the app's own scheme, and
 *  `detail` is its size in the person's words. */
export interface EmbeddedFile {
  url: string
  kind: 'image' | 'audio' | 'video' | 'pdf' | 'file'
  name: string
  detail: string
  icon: string
  /** Whether Open hands it to an app; a file that might run is only shown in the Finder. */
  opens: boolean
}

/** Why an embed's file can't be shown now, such as a file not yet downloaded while the server can't be reached or
 *  more than one file having the name. The page shows an error card with the reason; a file that does not exist is
 *  Inkkit's File Not Found card instead. Neither is ever a broken image. */
export interface UnavailableFile {
  unavailable: string
}

export type EditorMessage =
  | { type: 'ready' }
  | { type: 'error' | 'diagnostic'; message: string }
  | { type: 'changed'; markdown: string; generation: number }
  | ({ type: 'state' } & CaretState)
  /** Said once for each `load`, after the browser has drawn the document. The app ends its `item.open` signpost
   *  there, and drops it with no sample when the page takes another generation first. */
  | { type: 'painted'; generation: number }
  | { type: 'headerScrolledAway'; away: boolean; generation: number }
  | { type: 'contentUnderToolbar'; under: boolean; generation: number }
  | { type: 'titleFocus'; focused: boolean }
  | { type: 'titleInput'; item: string; text: string }
  | { type: 'titleCommit'; item: string; text: string; startWriting: boolean }
  | { type: 'titleDiscard'; item: string }
  | {
      type: 'headerMenu'
      item: string
      menu: HeaderMenu
      rect: [number, number, number, number]
      viewportHeight: number
    }
  | { type: 'openLink'; href: string }
  | { type: 'openItem'; item: string }
  | { type: 'copy'; text: string }
  | { type: 'escape' }
  | { type: 'pasteImages' }
  | { type: 'openEmbed'; embed: EmbedRequest }
  | { type: 'embedMenu'; embed: EmbedRequest | null; opens: boolean }
  | { type: 'rowMenu'; row: { item: string; row: string } | null }
  | ({ type: 'openNote'; item: string } & LinkRef)
  | ({ type: 'find' } & FindState)

/** The authored spelling identifies the binding; decoded parts serve navigation and display. Forward `raw` unchanged
 *  through opening, resolution and cache identity: Marfa binds each spelling separately, including an alias that
 *  repeats the name and escaped separators. The page never guesses which note a name means. */
export interface LinkRef {
  raw: string
  target: string
  heading?: string
  alias?: string
}

/** What the page asks of the app's notes: names to offer after `[[`, which note the person links to, and which
 *  names the links of a note use that no note answers to. */
export type NoteRequest =
  | { type: 'suggest'; query: string; item: string }
  | { type: 'pick'; item: string }
  | { type: 'resolve'; item: string; links: LinkRef[] }

/** Why the page asks for a picture at a web address: it is drawing the card, the person chose to load it, or the
 *  page is printing and wants only what the app already holds. */
export type PictureAsk = 'drawing' | 'chosen' | 'cached'

/** A question about the picture at a web address. With `export`, the app answers with its bytes (a picture it holds)
 *  for a portable export, rather than a URL to show it from. */
export type PictureRequest = {
  type: 'load'
  item: string
  address: string
  ask: PictureAsk
  export?: boolean
}

/** What the app says of a picture at a web address. `loaded` gives the `url` the page shows it from; `waiting` means
 *  nothing was fetched and the person may choose to; `off` that Settings says never; `refused` why the app would not
 *  fetch it or could not, and whether trying again may differ (`retry`). */
export type PictureAnswer =
  | { state: 'loaded'; url: string }
  | { state: 'loaded'; data: string; mimeType: string }
  | { state: 'waiting' }
  | { state: 'off' }
  | { state: 'refused'; reason: string; retry?: string }

declare global {
  interface Window {
    webkit?: {
      messageHandlers?: {
        host?: { postMessage(message: EditorMessage): void }
        /** Answers with what the app knows of a file a note embeds, why the file can't be shown now, or null
         *  when it has none. */
        embeds?: {
          postMessage(request: EmbedRequest): Promise<EmbeddedFile | UnavailableFile | null>
        }
        /** Answers a `suggest` with note names, a `pick` with the link the person chose, or null, and a
         *  `resolve` with whether each name is missing. */
        notes?: { postMessage(request: NoteRequest): Promise<unknown> }
        /** Answers a question about a picture at a web address, or null when the app has no answer. The page
         *  fetches nothing itself: this is the only way such a picture reaches it. */
        pictures?: { postMessage(request: PictureRequest): Promise<PictureAnswer | null> }
      }
    }
  }
}

export function postToHost(message: EditorMessage): void {
  const host = window.webkit?.messageHandlers?.host
  if (host) host.postMessage(message)
  else console.debug('host', message)
}

/** Note names that answer what was typed after `[[`, in the order to show them. */
export async function suggestNotes(query: string, item: string): Promise<string[]> {
  const names = await window.webkit?.messageHandlers?.notes?.postMessage({
    type: 'suggest',
    query,
    item,
  })
  return Array.isArray(names) ? names.filter((name) => typeof name === 'string') : []
}

/** The Markdown link to the note the person chooses for the item, or undefined if they decline. The app
 *  answers when they have chosen, however long that takes. */
export async function pickNote(item: string): Promise<string | undefined> {
  const link = await window.webkit?.messageHandlers?.notes?.postMessage({ type: 'pick', item })
  return typeof link === 'string' ? link : undefined
}

/** Whether each link of the item names no note, in the order asked; null when the app does not answer, so the
 *  page assumes nothing. */
export async function askMissing(item: string, links: LinkRef[]): Promise<boolean[] | null> {
  const answer = await window.webkit?.messageHandlers?.notes?.postMessage({
    type: 'resolve',
    item,
    links,
  })
  return Array.isArray(answer) &&
    answer.length === links.length &&
    answer.every((missing) => typeof missing === 'boolean')
    ? answer
    : null
}

/** What the app says of the picture at a web address, or null when it does not answer. */
export async function askPicture(
  request: Omit<PictureRequest, 'type'>,
): Promise<PictureAnswer | null> {
  try {
    const answer = await window.webkit?.messageHandlers?.pictures?.postMessage({
      type: 'load',
      ...request,
    })
    return answer && typeof answer === 'object' && 'state' in answer ? answer : null
  } catch {
    return null
  }
}
