import type { CaretState, FindState } from './editor'
import type { HeaderMenu } from './header'

/** An embed as the note's text holds it, such as `![[photo.png|400]]` or `![](a.png)`, which the app
 *  matches against the embeds Marfa bound for the note. */
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

/** Why an embed's file can't be shown now, such as a file not yet downloaded while the server can't be reached. */
export interface UnavailableFile {
  unavailable: string
}

export type EditorMessage =
  | { type: 'ready' }
  | { type: 'error' | 'diagnostic'; message: string }
  | { type: 'changed'; markdown: string; generation: number }
  | ({ type: 'state' } & CaretState)
  | { type: 'headerScrolledAway'; away: boolean; generation: number }
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
  | { type: 'copy'; text: string }
  | { type: 'escape' }
  | { type: 'pasteImages' }
  | { type: 'openEmbed'; embed: EmbedRequest }
  | { type: 'embedMenu'; embed: EmbedRequest | null; opens: boolean }
  | ({ type: 'openNote'; item: string } & LinkRef)
  | ({ type: 'find' } & FindState)

/** A `[[link]]` as the page reads it: the name, any heading after `#`, and the alias after `|` when it has one.
 *  The app tells links apart by all three, since the library binds each spelling on its own. */
export interface LinkRef {
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
