import { $nodeSchema } from '@milkdown/kit/utils'
import type { Literal } from 'mdast'
import type { Extension as FromMarkdownExtension } from 'mdast-util-from-markdown'
import { defaultHandlers, type Handle } from 'mdast-util-to-markdown'
import type { Code, Construct, Extension, State, TokenizeContext } from 'micromark-util-types'

/** `![[file]]`, `![[file|400]]` or `![[file#part]]`: an embed by name, as Obsidian writes one. The source
 *  text is kept whole, so it is written back as it was typed. */
export interface WikiEmbed extends Literal {
  type: 'wikiEmbed'
}

declare module 'mdast' {
  interface PhrasingContentMap {
    wikiEmbed: WikiEmbed
  }
  interface RootContentMap {
    wikiEmbed: WikiEmbed
  }
}

declare module 'micromark-util-types' {
  interface TokenTypeMap {
    wikiEmbed: 'wikiEmbed'
  }
}

declare module 'mdast-util-to-markdown' {
  interface ConstructNameMap {
    wikiEmbed: 'wikiEmbed'
  }
}

/** A document's extensions, as Marfa's core reads them: an embed of one shows a note, which stays text. */
const documentExtensions = new Set(['md', 'markdown', 'txt'])

/** The lowercased extension of a path's last component, or the empty string where it has none. */
export function extensionOf(path: string): string {
  const name = path.slice(path.lastIndexOf('/') + 1)
  const dot = name.lastIndexOf('.')
  return dot > 0 ? name.slice(dot + 1).toLowerCase() : ''
}

export function isDocument(path: string): boolean {
  return documentExtensions.has(extensionOf(path))
}

/** Whether a name reads as a file's, the only kind an embed shows. Marfa's core also counts a name with no
 *  extension it knows when such a file is in the folder, which the page cannot tell as it reads the note;
 *  `![[Dr. Smith]]` and `![[Minutes 2026.10.06]]` read as notes, as Obsidian reads them. */
export function namesFile(name: string): boolean {
  return (
    !isDocument(name) &&
    /^[a-z0-9]*[a-z][a-z0-9]*$/.test(extensionOf(name)) &&
    extensionOf(name).length <= 8
  )
}

/** What `![[…]]` holds, read as Obsidian and Marfa read it: the name before any `#` or `|`, the part of the
 *  file after a `#`, and a width as the last `|` gives it, `400` or `400x300`. */
export interface Named {
  name: string
  fragment: string
  width: number | null
}

const sizeSuffix = /(\\?)\|\s*(\d{1,5})(?:x\d{1,5})?\s*$/

export function readNamed(raw: string): Named {
  // In a table a cell's `|` is written `\|`, as Obsidian reads it.
  const inner = raw.slice(3, -2).replace(/\\\|/g, '|')
  const target = inner.split('|')[0] ?? ''
  const hash = target.indexOf('#')
  const size = sizeSuffix.exec(inner)
  return {
    name: (hash < 0 ? target : target.slice(0, hash)).trim(),
    fragment: hash < 0 ? '' : target.slice(hash).trim(),
    width: size ? Number(size[2]) : null,
  }
}

/** The embed with a new width, written as `|400` in place of any it had. */
export function withWidth(raw: string, width: number): string {
  const inner = raw.slice(3, -2)
  const sized = sizeSuffix.test(inner)
    ? inner.replace(sizeSuffix, (_, escape: string) => `${escape}|${width}`)
    : `${inner}|${width}`
  return `![[${sized}]]`
}

const exclamation = 33
const leftBracket = 91
const rightBracket = 93

/** Reads `![[` up to the first `]]` on the same line, and only where what it names is a file. */
function tokenizeWikiEmbed(
  this: TokenizeContext,
  effects: Parameters<Construct['tokenize']>[0],
  ok: State,
  nok: State,
): State {
  let inner = ''
  const open =
    (next: State): State =>
    (code: Code) => {
      if (code !== leftBracket) return nok(code)
      effects.consume(code)
      return next
    }
  const inside: State = (code) => {
    // Line endings are negative codes, and an embed never spans one.
    if (code === null || code < -2) return nok(code)
    effects.consume(code)
    if (code === rightBracket) return closing
    inner += code === -2 ? '\t' : code === -1 ? ' ' : String.fromCodePoint(code)
    return inside
  }
  const closing: State = (code) => {
    if (code !== rightBracket) {
      inner += ']'
      return inside(code)
    }
    const name = readNamed(`![[${inner}]]`).name
    if (!name || !namesFile(name)) return nok(code)
    effects.consume(code)
    effects.exit('wikiEmbed')
    return ok
  }
  return (code) => {
    if (code !== exclamation) return nok(code)
    effects.enter('wikiEmbed')
    effects.consume(code)
    return open(open(inside))
  }
}

const wikiEmbedConstruct: Construct = { name: 'wikiEmbed', tokenize: tokenizeWikiEmbed }

export const wikiEmbedSyntax: Extension = { text: { [exclamation]: wikiEmbedConstruct } }

export const wikiEmbedFromMarkdown: FromMarkdownExtension = {
  enter: {
    wikiEmbed(token) {
      this.enter({ type: 'wikiEmbed', value: '' }, token)
    },
  },
  exit: {
    wikiEmbed(token) {
      const node = this.stack[this.stack.length - 1] as WikiEmbed
      node.value = this.sliceSerialize(token)
      this.exit(token)
    },
  },
}

// A `|` the embed holds would end a table's cell.
const wikiEmbedHandler = Object.assign(
  (node: WikiEmbed, _: unknown, state: Parameters<Handle>[2]) =>
    state.stack.includes('tableCell') ? node.value.replace(/(?<!\\)\|/g, '\\|') : node.value,
  { peek: () => '!' },
)

/** `[[a link]]` and `![[A note]]` are text to the page, but the brackets are what make them a link or an
 *  embed to Obsidian and to Marfa's core, so they are written as typed rather than escaped. Only where the
 *  text inside could not read as anything else; otherwise the run is escaped as any text is. */
const wikiRun = /!?\[\[(?:(?!\]\])[^\n])+\]\]/g
const plainInside = /^[^`*_~<>&\\[\]@]*$/

function literal(run: string): boolean {
  const inner = run.slice(run.startsWith('!') ? 3 : 2, -2)
  return plainInside.test(inner) && !/:\/\/|www\./i.test(inner)
}

const text: Handle = (node, parent, state, info) => {
  const value = String(node.value)
  let out = ''
  let last = 0
  const safe = (piece: string, after: string) =>
    piece ? state.safe(piece, { ...info, before: out ? out.slice(-1) : info.before, after }) : ''
  for (const match of value.matchAll(wikiRun)) {
    if (!literal(match[0])) continue
    out += safe(value.slice(last, match.index), match[0][0]!)
    out += state.stack.includes('tableCell') ? match[0].replace(/\|/g, '\\|') : match[0]
    last = match.index + match[0].length
  }
  if (last === 0) return defaultHandlers.text(node, parent, state, info)
  return out + safe(value.slice(last), info.after)
}

export const wikiEmbedToMarkdown = { handlers: { wikiEmbed: wikiEmbedHandler, text } }

export const wikiEmbedSchema = $nodeSchema('embed', () => ({
  inline: true,
  group: 'inline',
  selectable: true,
  draggable: true,
  marks: '',
  atom: true,
  attrs: { raw: { default: '', validate: 'string' } },
  // Copied as plain text, an embed is the markdown that makes it.
  leafText: (node) => String(node.attrs.raw),
  parseDOM: [
    {
      tag: 'span[data-embed]',
      getAttrs: (dom) => ({ raw: (dom as HTMLElement).dataset.embed ?? '' }),
    },
  ],
  toDOM: (node) => ['span', { 'data-embed': node.attrs.raw }, String(node.attrs.raw)],
  parseMarkdown: {
    match: ({ type }) => type === 'wikiEmbed',
    runner: (state, node, type) => {
      state.addNode(type, { raw: String(node.value) })
    },
  },
  toMarkdown: {
    match: (node) => node.type.name === 'embed',
    runner: (state, node) => {
      state.addNode('wikiEmbed', undefined, String(node.attrs.raw))
    },
  },
}))
