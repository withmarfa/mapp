import { parserCtx, remarkCtx } from '@milkdown/kit/core'
import type { Ctx } from '@milkdown/kit/ctx'
import type { Node as ProseNode } from '@milkdown/kit/prose/model'
import type { Nodes, Root } from 'mdast'
import { serialize } from './dialect'

/** A top-level block of the note as it was written: its text, and the form the editor would write it in. */
interface SourceBlock {
  text: string
  canonical: string
  start: number
  end: number
}

/** A top-level link definition. The page shows nothing for it, so it is kept by its place in the text. */
interface Definition {
  text: string
  start: number
  end: number
}

/** The note's body as loaded, split into blocks when it is first edited. The app keeps what the page cannot
 *  show, front matter, a byte-order mark and Windows line endings, and hands the page the body alone. */
export interface Source {
  body: string
  blocks?: SourceBlock[]
  definitions?: Definition[]
}

export function readSource(body: string): Source {
  return { body }
}

// The editor writes a block with a trailing newline; blocks are compared and joined without it.
function trimmed(markdown: string): string {
  return markdown.replace(/\n+$/, '')
}

function definitionsIn(tree: Root): Nodes[] {
  const found: Nodes[] = []
  const visit = (node: Nodes) => {
    if (node.type === 'definition') found.push(node)
    if ('children' in node) for (const child of node.children) visit(child)
  }
  visit(tree)
  return found
}

/** Splits the body into its top-level blocks by where the parser found them, each from the start of its
 *  first line so an indented block keeps its indent. */
function split(ctx: Ctx, source: Source): void {
  const body = source.body
  const tree = ctx.get(remarkCtx).parse(body) as Root
  const parse = ctx.get(parserCtx)
  const slice = (node: Nodes) =>
    body.slice(node.position?.start.offset ?? 0, node.position?.end.offset ?? 0)
  // A block is read after the note's link definitions, so `[text][ref]` means what it means in the note.
  const definitions = definitionsIn(tree).map(slice).join('\n')
  source.blocks = []
  source.definitions = []
  for (const child of tree.children) {
    let start = child.position?.start.offset
    const end = child.position?.end.offset
    if (start == null || end == null) continue
    const lineStart = body.lastIndexOf('\n', start - 1) + 1
    if (/^[ \t]*$/.test(body.slice(lineStart, start))) start = lineStart
    const text = body.slice(start, end)
    if (child.type === 'definition') {
      source.definitions.push({ text, start, end })
      continue
    }
    const canonical = trimmed(
      serialize(ctx, parse(definitions ? `${definitions}\n\n${text}` : text)),
    )
    if (canonical) source.blocks.push({ text, canonical, start, end })
  }
}

// A block the document still holds unchanged is the same node, so its canonical form is worked out once.
const canonicalForms = new WeakMap<ProseNode, string>()

function canonicalOf(ctx: Ctx, node: ProseNode): string {
  let form = canonicalForms.get(node)
  if (form == null) {
    form = trimmed(serialize(ctx, node.type.schema.topNodeType.create(null, [node])))
    canonicalForms.set(node, form)
  }
  return form
}

/** The pairs of equal items that the longest common subsequence aligns, from positions in `b` to `a`. The
 *  common start and end are paired first, so an edit in a long note compares only the part around it. */
function align(a: string[], b: string[]): Map<number, number> {
  const pairs = new Map<number, number>()
  let head = 0
  while (head < a.length && head < b.length && a[head] === b[head]) {
    pairs.set(head, head)
    head++
  }
  let tail = 0
  while (
    tail < a.length - head &&
    tail < b.length - head &&
    a[a.length - 1 - tail] === b[b.length - 1 - tail]
  ) {
    pairs.set(b.length - 1 - tail, a.length - 1 - tail)
    tail++
  }
  const midA = a.slice(head, a.length - tail)
  const midB = b.slice(head, b.length - tail)
  const lengths = Array.from({ length: midA.length + 1 }, () =>
    new Array<number>(midB.length + 1).fill(0),
  )
  for (let i = midA.length - 1; i >= 0; i--) {
    for (let j = midB.length - 1; j >= 0; j--) {
      lengths[i]![j] =
        midA[i] === midB[j]
          ? lengths[i + 1]![j + 1]! + 1
          : Math.max(lengths[i + 1]![j]!, lengths[i]![j + 1]!)
    }
  }
  let i = 0
  let j = 0
  while (i < midA.length && j < midB.length) {
    if (midA[i] === midB[j]) {
      pairs.set(head + j, head + i)
      i++
      j++
    } else if (lengths[i + 1]![j]! >= lengths[i]![j + 1]!) {
      i++
    } else {
      j++
    }
  }
  return pairs
}

/** The body as markdown, keeping the source's own text for every block the edit left alone, and the gaps
 *  between blocks that are still neighbours. An edited or new block is written in the canonical form, and
 *  an edited block standing where a source block stood keeps that block's surrounding blank lines. Link
 *  definitions are never dropped. If the result would read back differently from the document, as when two
 *  kept lists would run together, the whole body is written canonically instead, its definitions after it. */
export function preserve(ctx: Ctx, source: Source, doc: ProseNode, canonical: string): string {
  if (!source.blocks || !source.definitions) split(ctx, source)
  const blocks = source.blocks!
  const definitions = source.definitions!
  const body = source.body
  const current: string[] = []
  doc.forEach((node) => {
    const text = canonicalOf(ctx, node)
    if (text) current.push(text)
  })
  if (blocks.length === 0 || current.length === 0) return canonical
  const pairs = align(
    blocks.map((block) => block.canonical),
    current,
  )
  const used = new Set(pairs.values())

  // The source text written out, by range, so a definition that went with none of it can be put back.
  const kept: [number, number][] = []
  let out = ''
  const keep = (start: number, end: number) => {
    out += body.slice(start, end)
    kept.push([start, end])
  }

  // Positions only move forward, so no stretch of the source is written twice.
  let cursor = -1
  let previous: number | undefined
  current.forEach((text, index) => {
    const matched = pairs.get(index)
    const next = cursor + 1
    const standsIn = matched == null && next < blocks.length && !used.has(next) ? next : undefined
    if (standsIn != null) used.add(standsIn)
    const position = matched ?? standsIn
    const block = position == null ? undefined : blocks[position]
    if (index === 0) {
      if (position === 0 && block) keep(0, block.start)
    } else if (position != null && previous != null && position === previous + 1 && block) {
      keep(blocks[previous]!.end, block.start)
    } else {
      out += '\n\n'
    }
    if (matched != null && block) keep(block.start, block.end)
    else out += text
    if (position != null) cursor = Math.max(cursor, position)
    previous = position
  })
  const last = blocks[blocks.length - 1]!
  if (previous === blocks.length - 1) keep(last.end, body.length)
  else out += '\n'

  const lost = definitions.filter(
    (definition) =>
      !kept.some(([start, end]) => start <= definition.start && definition.end <= end),
  )
  if (lost.length > 0)
    out = `${trimmed(out)}\n\n${lost.map((definition) => definition.text).join('\n')}\n`

  if (serialize(ctx, ctx.get(parserCtx)(out)) === canonical) return out
  // The page shows no definition, so the canonical form has none; they are kept after it, where they change
  // nothing it writes, since it writes every link inline and escapes any other brackets.
  if (definitions.length === 0) return canonical
  return `${trimmed(canonical)}\n\n${definitions.map((definition) => definition.text).join('\n')}\n`
}
