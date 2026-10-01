import { editorViewCtx, serializerCtx } from '@milkdown/kit/core'
import type { Ctx, MilkdownPlugin } from '@milkdown/kit/ctx'
import type { Node as ProseNode } from '@milkdown/kit/prose/model'
import { commonmark, remarkPreserveEmptyLinePlugin } from '@milkdown/kit/preset/commonmark'
import {
  addColAfterCommand,
  addColBeforeCommand,
  addRowAfterCommand,
  addRowBeforeCommand,
  deleteSelectedCellsCommand,
  exitTable,
  extendListItemSchemaForTask,
  goToNextTableCellCommand,
  goToPrevTableCellCommand,
  insertTableCommand,
  selectColCommand,
  selectRowCommand,
  setAlignCommand,
  strikethroughAttr,
  strikethroughInputRule,
  strikethroughKeymap,
  strikethroughSchema,
  tableCellSchema,
  tableEditingPlugin,
  tableHeaderRowSchema,
  tableHeaderSchema,
  tableKeymap,
  tableRowSchema,
  tableSchema,
  toggleStrikethroughCommand,
  wrapInTaskListInputRule,
} from '@milkdown/kit/preset/gfm'
import { $remark } from '@milkdown/kit/utils'
import { autolinkInputRule } from './autolink'
import { imageView } from './images'
import type { Heading, Link, Paragraph, Parents, PhrasingContent } from 'mdast'
import { defaultHandlers, type Options as StringifyOptions } from 'mdast-util-to-markdown'
import {
  gfmAutolinkLiteralFromMarkdown,
  gfmAutolinkLiteralToMarkdown,
} from 'mdast-util-gfm-autolink-literal'
import {
  gfmStrikethroughFromMarkdown,
  gfmStrikethroughToMarkdown,
} from 'mdast-util-gfm-strikethrough'
import { gfmTableFromMarkdown, gfmTableToMarkdown } from 'mdast-util-gfm-table'
import {
  gfmTaskListItemFromMarkdown,
  gfmTaskListItemToMarkdown,
} from 'mdast-util-gfm-task-list-item'
import { gfmAutolinkLiteral } from 'micromark-extension-gfm-autolink-literal'
import { gfmStrikethrough } from 'micromark-extension-gfm-strikethrough'
import { gfmTable } from 'micromark-extension-gfm-table'
import { gfmTaskListItem } from 'micromark-extension-gfm-task-list-item'
import type { Processor } from 'unified'

const bareURL = /^https?:\/\/[^\s<>]+$/
// The literal form stops at these, so a URL ending in one would come back shorter than it went out.
const endsInPunctuation = /[.,;:!?]$/
// What may sit against a bare URL without the reader running the two together.
const beforeURL = /(^|[\s([*_~])$/
const afterURL = /^([\s.,;:!?)\]}<]|$)/

function balanced(url: string): boolean {
  let open = 0
  for (const character of url) {
    if (character === '(') open += 1
    else if (character === ')') open -= 1
    if (open < 0) return false
  }
  return open === 0
}

function textAt(
  parent: Parents | undefined,
  node: Link,
  offset: number,
): PhrasingContent | undefined {
  const children = parent?.children as PhrasingContent[] | undefined
  const index = children?.indexOf(node as PhrasingContent) ?? -1
  return index < 0 ? undefined : children?.[index + offset]
}

/** A link whose text is its own URL is written as the bare URL, the way it was typed. Only where reading
 *  it back gives the same link again: nothing may run into it at either end. */
function writesBare(node: Link, parent: Parents | undefined): boolean {
  const [child, ...rest] = node.children
  if (node.title || rest.length > 0 || child?.type !== 'text' || child.value !== node.url)
    return false
  if (!bareURL.test(node.url) || endsInPunctuation.test(node.url) || !balanced(node.url))
    return false
  const before = textAt(parent, node, -1)
  if (before && (before.type !== 'text' || !beforeURL.test(before.value))) return false
  const after = textAt(parent, node, 1)
  if (after && (after.type !== 'text' || !afterURL.test(after.value))) return false
  return true
}

const link: (typeof defaultHandlers)['link'] = (node, parent, state, info) =>
  writesBare(node, parent) ? node.url : defaultHandlers.link(node, parent, state, info)
link.peek = (node, parent, state) =>
  writesBare(node, parent) ? node.url[0]! : defaultHandlers.link.peek(node, parent, state)

// Spaces and tabs at the edges of a paragraph or heading are dropped when markdown is read, so writing them would
// only escape them, as `&#x20;`, into the file and into the note's name; they are left out.
function trimmed<T extends Paragraph | Heading>(node: T): T {
  // An empty block reaches the writer with no children at all.
  if (!Array.isArray(node.children)) return node
  const children = [...node.children]
  const first = children[0]
  if (first?.type === 'text') children[0] = { ...first, value: first.value.replace(/^[ \t]+/, '') }
  const last = children.at(-1)
  if (last?.type === 'text')
    children[children.length - 1] = { ...last, value: last.value.replace(/[ \t]+$/, '') }
  return { ...node, children }
}

const paragraph: (typeof defaultHandlers)['paragraph'] = (node, parent, state, info) =>
  defaultHandlers.paragraph(trimmed(node), parent, state, info)
const heading: (typeof defaultHandlers)['heading'] = (node, parent, state, info) =>
  defaultHandlers.heading(trimmed(node), parent, state, info)

// Compact rows, since padding columns out would rewrite a whole table whenever one cell grew; but delimiters of
// at least three dashes, the form GitHub and most writers use, where the compact form would write one.
const tableToMarkdown = gfmTableToMarkdown({ tablePipeAlign: false })
const compactTable = tableToMarkdown.handlers!.table!
tableToMarkdown.handlers!.table = (node, parent, state, info) => {
  const lines = compactTable(node, parent, state, info).split('\n')
  if (lines[1]) lines[1] = lines[1].replace(/(:?)-+(:?)/g, '$1---$2')
  return lines.join('\n')
}

// Footnotes are deliberately left out.
function remarkDialect(this: Processor) {
  const data = this.data() as Record<string, unknown[] | undefined>
  const add = (key: string, value: unknown) => {
    const list = (data[key] ??= [])
    list.push(value)
  }
  add('micromarkExtensions', gfmStrikethrough())
  add('micromarkExtensions', gfmTaskListItem())
  add('micromarkExtensions', gfmAutolinkLiteral())
  add('micromarkExtensions', gfmTable())
  add('fromMarkdownExtensions', gfmStrikethroughFromMarkdown())
  add('fromMarkdownExtensions', gfmTaskListItemFromMarkdown())
  add('fromMarkdownExtensions', gfmAutolinkLiteralFromMarkdown())
  add('fromMarkdownExtensions', gfmTableFromMarkdown())
  add('toMarkdownExtensions', gfmStrikethroughToMarkdown())
  add('toMarkdownExtensions', gfmTaskListItemToMarkdown())
  add('toMarkdownExtensions', gfmAutolinkLiteralToMarkdown())
  add('toMarkdownExtensions', tableToMarkdown)
  add('toMarkdownExtensions', { handlers: { link, paragraph, heading } })
}

export const remarkDialectPlugin = $remark('remarkDialect', () => remarkDialect)

// Without it an empty paragraph is written as `<br />`, which the dialect forbids.
const commonmarkWithoutEmptyLines = commonmark.filter(
  (plugin) => !(remarkPreserveEmptyLinePlugin as MilkdownPlugin[]).includes(plugin),
)

// The preset gives a new cell left alignment, so a table made in the editor would be written with `:---` in
// every column. A cell nobody aligned has no alignment, which is written as `---`.
function unaligned<T extends typeof tableCellSchema | typeof tableHeaderSchema>(schema: T): T {
  return schema.extendSchema((previous) => (ctx) => {
    const base = previous(ctx)
    return {
      ...base,
      attrs: { ...base.attrs, alignment: { default: null } },
    }
  }) as T
}

export const tables: MilkdownPlugin[] = [
  tableSchema,
  tableHeaderRowSchema,
  tableRowSchema,
  unaligned(tableHeaderSchema),
  unaligned(tableCellSchema),
  tableEditingPlugin,
  tableKeymap,
  goToNextTableCellCommand,
  goToPrevTableCellCommand,
  exitTable,
  insertTableCommand,
  addRowBeforeCommand,
  addRowAfterCommand,
  addColBeforeCommand,
  addColAfterCommand,
  selectRowCommand,
  selectColCommand,
  deleteSelectedCellsCommand,
  setAlignCommand,
].flat()

export const dialect: MilkdownPlugin[] = [
  commonmarkWithoutEmptyLines,
  autolinkInputRule,
  extendListItemSchemaForTask,
  strikethroughAttr,
  strikethroughSchema,
  strikethroughInputRule,
  strikethroughKeymap,
  toggleStrikethroughCommand,
  wrapInTaskListInputRule,
  tables,
  remarkDialectPlugin,
  imageView,
].flat()

// One output form, so a note written back unchanged is byte-stable.
export const stringifyOptions: StringifyOptions = {
  bullet: '-',
  emphasis: '*',
  strong: '*',
  fences: true,
  listItemIndent: 'one',
  rule: '-',
}

// Empty paragraphs are spacing, not content, so they are left out of the markdown.
function withoutEmptyParagraphs(doc: ProseNode): ProseNode {
  const blocks: ProseNode[] = []
  doc.forEach((block) => {
    if (block.type.name !== 'paragraph' || block.content.size > 0) blocks.push(block)
  })
  if (blocks.length === doc.childCount) return doc
  return doc.type.create(doc.attrs, blocks.length > 0 ? blocks : [doc.child(0)])
}

export function serialize(ctx: Ctx, doc: ProseNode = ctx.get(editorViewCtx).state.doc): string {
  return ctx.get(serializerCtx)(withoutEmptyParagraphs(doc))
}
