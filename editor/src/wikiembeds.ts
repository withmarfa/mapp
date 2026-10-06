import { InputRule } from '@milkdown/kit/prose/inputrules'
import { $inputRule, $markSchema, $nodeSchema } from '@milkdown/kit/utils'
import type { Literal, Parent, Parents, PhrasingContent } from 'mdast'
import type { Extension as FromMarkdownExtension } from 'mdast-util-from-markdown'
import type { Handle } from 'mdast-util-to-markdown'
import type { Code, Construct, Extension, State, TokenizeContext } from 'micromark-util-types'

/** `![[file]]`, `![[file|400]]` or `![[file#part]]`: an embed by name, as Obsidian writes one. The source
 *  text is kept whole, so it is written back as it was typed. */
export interface WikiEmbed extends Literal {
  type: 'wikiEmbed'
}

/** `[[a link]]`, or `![[A note]]` embedding a note, as typed. */
export interface WikiLink extends Literal {
  type: 'wikiLink'
}

/** A link as the editor writes it back: the text its mark holds, with any emphasis given to part of it. */
interface WikiMarked extends Parent {
  type: 'wikiLink'
  children: PhrasingContent[]
}

declare module 'mdast' {
  interface PhrasingContentMap {
    wikiEmbed: WikiEmbed
    wikiLink: WikiLink
  }
  interface RootContentMap {
    wikiEmbed: WikiEmbed
    wikiLink: WikiLink
  }
}

declare module 'micromark-util-types' {
  interface TokenTypeMap {
    wiki: 'wiki'
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

/** Reads `[[` or `![[` up to the first `]]` on the same line, as Obsidian and Marfa's core read a link or an
 *  embed, before markdown can read the brackets as anything else. */
function tokenizeWiki(embed: boolean) {
  return function (
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
      // Line endings are negative codes, and a link never spans one.
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
      if (!inner.trim()) return nok(code)
      effects.consume(code)
      effects.exit('wiki')
      return ok
    }
    return (code) => {
      effects.enter('wiki')
      if (!embed) return open(open(inside))(code)
      if (code !== exclamation) return nok(code)
      effects.consume(code)
      return open(open(inside))
    }
  }
}

export const wikiSyntax: Extension = {
  text: {
    [exclamation]: { name: 'wikiEmbed', tokenize: tokenizeWiki(true) },
    [leftBracket]: { name: 'wikiLink', tokenize: tokenizeWiki(false) },
  },
}

/** An embed of a file becomes a `wikiEmbed`, shown as the file; a link, or an embed of a note, a `wikiLink`,
 *  which stays text. */
export const wikiFromMarkdown: FromMarkdownExtension = {
  enter: {
    wiki(token) {
      this.enter({ type: 'wikiLink', value: '' }, token)
    },
  },
  exit: {
    wiki(token) {
      const node = this.stack[this.stack.length - 1] as WikiEmbed | WikiLink
      node.value = this.sliceSerialize(token)
      if (node.value.startsWith('!') && namesFile(readNamed(node.value).name))
        node.type = 'wikiEmbed'
      this.exit(token)
    },
  },
}

/** One `[[link]]` or `![[embed]]` after another, with nothing between them. */
const wikiRuns = /^(?:!?\[\[(?:(?!\]\])[^\n])*?\S(?:(?!\]\])[^\n])*\]\])+$/

/** A `|` the run holds would end a table's cell. */
function inCell(value: string, state: Parameters<Handle>[2]): string {
  return state.stack.includes('tableCell') ? value.replace(/(?<!\\)\|/g, '\\|') : value
}

const wikiEmbedHandler = Object.assign(
  (node: WikiEmbed, _: unknown, state: Parameters<Handle>[2]) => inCell(node.value, state),
  { peek: () => '!' },
)

/** A link's text is written as it was typed. Once an edit has made it something other than links, as by
 *  emphasis given to part of it, it is written as any text is, escaped and with its emphasis, so it never
 *  reads back as more than it shows and loses none of what it shows. */
function writeWikiLink(
  node: WikiMarked,
  _: unknown,
  state: Parameters<Handle>[2],
  info: Parameters<Handle>[3],
): string {
  if (node.children.every((child) => child.type === 'text')) {
    const value = node.children.map((child) => child.value).join('')
    if (wikiRuns.test(value)) return inCell(value, state)
  }
  // The mark holds phrasing as a paragraph does; mdast's own types know only the `wikiLink` it reads.
  return state.containerPhrasing(node as unknown as Parents, info)
}

const wikiLinkHandler = Object.assign(writeWikiLink, {
  peek: (...args: Parameters<typeof writeWikiLink>) => writeWikiLink(...args).charAt(0),
})

export const wikiToMarkdown = {
  handlers: { wikiEmbed: wikiEmbedHandler, wikiLink: wikiLinkHandler },
}

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

/** A link stays text the person edits and finds, marked so it is written back as typed rather than escaped.
 *  Emphasis or a link around it is kept around it; code, which shows the brackets as text, is refused over it. */
export const wikiLinkSchema = $markSchema('wikiLink', () => ({
  inclusive: false,
  excludes: 'inlineCode',
  parseDOM: [{ tag: 'span.wikilink' }],
  toDOM: () => ['span', { class: 'wikilink' }, 0],
  parseMarkdown: {
    match: ({ type }) => type === 'wikiLink',
    runner: (state, node, markType) => {
      state.openMark(markType)
      state.addText(String(node.value))
      state.closeMark(markType)
    },
  },
  toMarkdown: {
    match: (mark) => mark.type.name === 'wikiLink',
    runner: (state, mark) => {
      state.withMark(mark, 'wikiLink')
    },
  },
}))

/** `[[a link]]` typed becomes a link as its last bracket is typed, and `![[a file]]` an embed, as they would
 *  read when the note is opened again. Not inside code, which shows them as text. */
export const wikiInputRule = $inputRule(
  (ctx) =>
    new InputRule(/(!?\[\[(?:(?!\]\])[^\n])+\]\])$/, (state, match, start, end) => {
      const raw = match[1]!
      const $start = state.doc.resolve(start)
      if ($start.parent.type.spec.code || $start.marks().some((mark) => mark.type.spec.code))
        return null
      const schema = state.schema
      const file = raw.startsWith('!') && namesFile(readNamed(raw).name)
      const node = file
        ? wikiEmbedSchema.type(ctx).create({ raw })
        : schema.text(raw, [wikiLinkSchema.type(ctx).create()])
      return state.tr.replaceWith(start, end, node)
    }),
)
