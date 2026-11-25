import { canOpenLink } from '@aicayzer/inkkit'
import type { CaretState, FindState } from './editor'
import type { CardTarget } from './card'
import type { HeaderMenu } from './header'

/** An embed as the item's text holds it, such as `![[photo.png|400]]` or `![](a.png)`, which the app
 *  matches against the embeds Marfa bound for the item. The text is exactly as written (`FileReference.raw`: alias,
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
  /** An input the person made reached folded text, and Inkkit dropped it and opened the section. The app tells them. */
  | { type: 'hiddenText' }
  | { type: 'changed'; markdown: string; generation: number }
  | ({ type: 'state' } & CaretState)
  /** Said once for each `load`, after the browser has drawn the document. The app ends its `item.open` signpost
   *  there, and drops it with no sample when the page takes another generation first. */
  | { type: 'painted'; generation: number }
  /** The item's headings in Inkkit's own order, so a heading's ordinal is its index here. Said after each load and after
   *  an edit changes the list; the app reveals a heading by ordinal under this generation. */
  | { type: 'headings'; headings: { level: number; text: string }[]; generation: number }
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
  /** A property row's or a pin's value asks for its editor under it: the row's identifier (a field key or `#tags`),
   *  and the value's frame as a menu's is sent. */
  | {
      type: 'editValue'
      item: string
      row: string
      rect: [number, number, number, number]
      viewportHeight: number
    }
  /** A row's or a pin's label was pressed: the app opens the field's menu under it. `editsValue` is set where the value
   *  holds a link of its own, so the menu is the only way to its editor. */
  | {
      type: 'fieldMenu'
      item: string
      row: string
      editsValue: boolean
      rect: [number, number, number, number]
      viewportHeight: number
    }
  /** The value an editor was asked for has moved on the page, to this frame. */
  | {
      type: 'valueMoved'
      item: string
      row: string
      rect: [number, number, number, number]
      viewportHeight: number
    }
  /** The kicker's type name: the app opens Change Type under it. */
  | {
      type: 'changeType'
      item: string
      rect: [number, number, number, number]
      viewportHeight: number
    }
  /** The person chose the page's notice action, for the item the page shows. Loading pictures is the page's own and
   *  posts nothing. */
  | { type: 'noticeAction'; item: string; kind: string }
  | { type: 'openLink'; href: string }
  | { type: 'openItem'; item: string }
  /** The pointer rests on a linked item: a row, a foot row or a chip names it (`item`, by identity), a link in the text is
   *  named as authored (`wiki`), and the app says what it means. The app waits, then draws the card under `rect`. */
  | {
      type: 'cardHover'
      item: string
      card: CardTarget
      rect: [number, number, number, number]
      viewportHeight: number
    }
  /** The pointer left, or the page scrolled, took a key or a click: no card. */
  | { type: 'cardEnd' }
  /** The context menu is opening over a linked item, or over none when null, for the menu's Show Card under `rect`. */
  | {
      type: 'cardMenu'
      item: string
      card: CardTarget | null
      rect: [number, number, number, number]
      viewportHeight: number
    }
  /** Show More under a foot list: the app sends the next rows of the list with this key. */
  | { type: 'footMore'; item: string; key: string }
  | { type: 'copy'; text: string }
  | { type: 'escape' }
  | { type: 'pasteImages' }
  | { type: 'openEmbed'; embed: EmbedRequest }
  /** Quick Look on an embedded file's card. */
  | { type: 'quickLookEmbed'; embed: EmbedRequest }
  | { type: 'embedMenu'; embed: EmbedRequest | null; opens: boolean }
  | { type: 'rowMenu'; row: { item: string; row: string } | null }
  /** A row of the property block was dragged: the whole order the page shows after the move, folded rows included. */
  | { type: 'moveRow'; item: string; row: string; order: string[] }
  | ({ type: 'openItemLink'; item: string } & LinkRef)
  /** The person asked for the menu of a link in the text, which Inkkit has selected. `point` is where the pointer was in
   *  the page's window, whose height is `viewportHeight`. The app builds the menu and carries each choice out through the
   *  page's commands, under `generation`. */
  | {
      type: 'linkMenu'
      item: string
      generation: number
      link: MenuLink
      point: [number, number]
      viewportHeight: number
    }
  | ({ type: 'find' } & FindState)

/** The link a `linkMenu` is for. `openable` is Inkkit's answer and `canOpenLink`'s, so the app opens an address only
 *  where both allow it. A wiki link carries what `openItemLink` does. */
export type MenuLink =
  | { kind: 'web'; text: string; href: string; openable: boolean }
  | ({ kind: 'wiki'; text: string } & LinkRef)

/** The authored spelling identifies the binding; decoded parts serve navigation and display. Forward `raw` unchanged
 *  through opening, resolution and cache identity: Marfa binds each spelling separately, including an alias that
 *  repeats the name and one with a backslash. The page never guesses which item a name means. */
export interface LinkRef {
  raw: string
  target: string
  heading?: string
  alias?: string
}

/** What the page asks of the app's items: names to offer after `[[`, which item the person links to, and what each
 *  link of an item names. */
export type ItemRequest =
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
        /** Answers with what the app knows of a file an item embeds, why the file can't be shown now, or null
         *  when it has none. */
        embeds?: {
          postMessage(request: EmbedRequest): Promise<EmbeddedFile | UnavailableFile | null>
        }
        /** Answers a `suggest` with item names, a `pick` with the link the person chose, or null, and a
         *  `resolve` with what each name is (`LinkAnswers`). */
        items?: { postMessage(request: ItemRequest): Promise<unknown> }
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

/** Asks the app to open a web, mail or phone address in the system's own app. Inkkit's `canOpenLink` decides what
 *  may be opened, so any other address, such as a `file:` or `javascript:` one in an item, is dropped here. */
export function openLink(href: string): void {
  if (canOpenLink(href)) postToHost({ type: 'openLink', href })
}

/** Item names that answer what was typed after `[[`, in the order to show them. */
export async function suggestItems(query: string, item: string): Promise<string[]> {
  const names = await window.webkit?.messageHandlers?.items?.postMessage({
    type: 'suggest',
    query,
    item,
  })
  return Array.isArray(names) ? names.filter((name) => typeof name === 'string') : []
}

/** The Markdown link to the item the person chooses for the item on the page, or undefined if they decline. The app
 *  answers when they have chosen, however long that takes. */
export async function pickItem(item: string): Promise<string | undefined> {
  const link = await window.webkit?.messageHandlers?.items?.postMessage({ type: 'pick', item })
  return typeof link === 'string' ? link : undefined
}

/** What the app says of one link of the item: whether it names no item, and otherwise, when it names exactly
 *  one, the icon of that item's type (a key of `LinkAnswers.icons`, absent for a type with none) and the name of
 *  the type's tone. */
export interface LinkAnswer {
  missing: boolean
  icon?: string
  tone?: string
}

/** The answers to a `resolve`, one for each link asked in the order asked, and the image of each icon they name,
 *  sent once however many links name it: a data URL of an image the page draws as a mask. */
export interface LinkAnswers {
  links: LinkAnswer[]
  icons: Map<string, string>
}

const isWord = (value: unknown): value is string =>
  typeof value === 'string' && /^[a-z]+$/.test(value)

/** What the app says of each link of the item, in the order asked; null when the app does not answer or the
 *  answer is not one the page can draw from, so the page assumes nothing. */
export async function askLinks(item: string, links: LinkRef[]): Promise<LinkAnswers | null> {
  const answer: unknown = await window.webkit?.messageHandlers?.items?.postMessage({
    type: 'resolve',
    item,
    links,
  })
  if (!answer || typeof answer !== 'object') return null
  const { links: answers, icons } = answer as Partial<Record<keyof LinkAnswers, unknown>>
  if (!Array.isArray(answers) || answers.length !== links.length) return null
  if (!icons || typeof icons !== 'object') return null
  const drawn = new Map<string, string>()
  for (const [key, url] of Object.entries(icons)) {
    if (typeof url === 'string' && url.startsWith('data:image/')) drawn.set(key, url)
  }
  const read: LinkAnswer[] = []
  for (const entry of answers as unknown[]) {
    if (!entry || typeof entry !== 'object') return null
    const { missing, icon, tone } = entry as Record<string, unknown>
    if (typeof missing !== 'boolean') return null
    read.push({
      missing,
      // A name that is not a word, or an icon never sent, is left out rather than guessed at.
      ...(typeof icon === 'string' && drawn.has(icon) ? { icon } : {}),
      ...(isWord(tone) ? { tone } : {}),
    })
  }
  return { links: read, icons: drawn }
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
