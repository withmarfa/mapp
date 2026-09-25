import { parserCtx, remarkCtx } from '@milkdown/kit/core'
import type { Ctx } from '@milkdown/kit/ctx'
import type { Node as ProseNode } from '@milkdown/kit/prose/model'
import { serialize } from './dialect'

/** A top-level block of the note as it was written: its text, and the form the editor would write it in. */
interface SourceBlock {
  text: string
  canonical: string
  start: number
  end: number
}

/** The note as loaded, split into its blocks, so an edit rewrites only the blocks it touched. */
export interface Source {
  markdown: string
  blocks: SourceBlock[]
}

// The editor writes a block with a trailing newline; blocks are compared and joined without it.
function trimmed(markdown: string): string {
  return markdown.replace(/\n+$/, '')
}

/** One block alone in its canonical form. A block that shows nothing, such as a link definition, is empty. */
function canonicalOf(ctx: Ctx, node: ProseNode): string {
  return trimmed(serialize(ctx, node.type.schema.topNodeType.create(null, [node])))
}

/** Splits the note into its top-level blocks by where the parser found them. What lies between two blocks,
 *  blank lines or a block the editor does not show, stays with the gap between them. */
export function readSource(ctx: Ctx, markdown: string): Source {
  const tree = ctx.get(remarkCtx).parse(markdown)
  const parse = ctx.get(parserCtx)
  const text = (node: (typeof tree.children)[number]) =>
    markdown.slice(node.position?.start.offset ?? 0, node.position?.end.offset ?? 0)
  // A block is read with the note's link definitions, so `[text][ref]` means what it means in the note.
  const definitions = tree.children
    .filter((node) => node.type === 'definition')
    .map(text)
    .join('\n')
  const blocks: SourceBlock[] = []
  for (const child of tree.children) {
    const start = child.position?.start.offset
    const end = child.position?.end.offset
    if (start == null || end == null) continue
    const canonical = trimmed(serialize(ctx, parse(`${text(child)}\n\n${definitions}`)))
    if (canonical) blocks.push({ text: text(child), canonical, start, end })
  }
  return { markdown, blocks }
}

/** The pairs of equal items, in order, that the longest common subsequence of two lists aligns. */
function align(a: string[], b: string[]): Map<number, number> {
  const lengths = Array.from({ length: a.length + 1 }, () =>
    new Array<number>(b.length + 1).fill(0),
  )
  for (let i = a.length - 1; i >= 0; i--) {
    for (let j = b.length - 1; j >= 0; j--) {
      lengths[i]![j] =
        a[i] === b[j]
          ? lengths[i + 1]![j + 1]! + 1
          : Math.max(lengths[i + 1]![j]!, lengths[i]![j + 1]!)
    }
  }
  const pairs = new Map<number, number>()
  let i = 0
  let j = 0
  while (i < a.length && j < b.length) {
    if (a[i] === b[j]) {
      pairs.set(j, i)
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

/** The document as markdown, keeping the source's own text for every block the edit left alone, and the gaps
 *  between blocks that are still neighbours. An edited or new block is written in the canonical form. If the
 *  result would read back differently from the document, as when two kept lists would run together, the
 *  whole document is written canonically instead. */
export function preserve(ctx: Ctx, source: Source, doc: ProseNode): string {
  const canonical = serialize(ctx, doc)
  const current: string[] = []
  doc.forEach((node) => {
    const text = canonicalOf(ctx, node)
    if (text) current.push(text)
  })
  const { blocks, markdown } = source
  if (blocks.length === 0 || current.length === 0) return canonical
  const pairs = align(
    blocks.map((block) => block.canonical),
    current,
  )

  // An edited block that stands where a source block stood, with nothing matching that source block, takes
  // its place: the blank lines around it stay as they were, though its own text is written anew.
  const used = new Set(pairs.values())
  let out = ''
  let previous: number | undefined
  current.forEach((text, index) => {
    const matched = pairs.get(index)
    const next = previous == null ? 0 : previous + 1
    const standsIn = matched == null && next < blocks.length && !used.has(next) ? next : undefined
    const position = matched ?? standsIn
    const block = position == null ? undefined : blocks[position]
    if (index === 0) {
      if (position === 0 && block) out += markdown.slice(0, block.start)
    } else if (position != null && previous != null && position === previous + 1 && block) {
      out += markdown.slice(blocks[previous]!.end, block.start)
    } else {
      out += '\n\n'
    }
    out += matched != null && block ? block.text : text
    previous = position
  })
  const last = blocks[blocks.length - 1]!
  out += previous === blocks.length - 1 ? markdown.slice(last.end) : '\n'

  const parse = ctx.get(parserCtx)
  return serialize(ctx, parse(out)) === canonical ? out : canonical
}
