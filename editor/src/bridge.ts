import type { CaretState, FindState } from './editor'

/** An embed as the note names it: by a path from the note, as `![](path)` does, or by name, as `![[name]]`
 *  does, for the app to resolve as Marfa's core does. */
export type EmbedRequest = { item: string } & ({ path: string } | { name: string })

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

export type EditorMessage =
  | { type: 'ready' }
  | { type: 'changed'; markdown: string; generation: number }
  | ({ type: 'state' } & CaretState)
  | { type: 'scrolled'; offset: number; generation: number }
  | { type: 'openLink'; href: string }
  | { type: 'copy'; text: string }
  | { type: 'escape' }
  | { type: 'pasteImages' }
  | { type: 'openEmbed'; embed: EmbedRequest }
  | { type: 'embedMenu'; embed: EmbedRequest | null; opens: boolean }
  | ({ type: 'find' } & FindState)

declare global {
  interface Window {
    webkit?: {
      messageHandlers?: {
        host?: { postMessage(message: EditorMessage): void }
        /** Answers with what the app knows of a file a note embeds, or null when it has none. */
        embeds?: { postMessage(request: EmbedRequest): Promise<EmbeddedFile | null> }
      }
    }
  }
}

export function postToHost(message: EditorMessage): void {
  const host = window.webkit?.messageHandlers?.host
  if (host) host.postMessage(message)
  else console.debug('host', message)
}
