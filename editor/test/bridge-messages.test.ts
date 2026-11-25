import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { expect, test } from 'vitest'
import type {
  EditorMessage,
  EmbedRequest,
  ItemRequest,
  PictureAsk,
  PictureRequest,
} from '../src/bridge'

/** `editor/bridge-messages.json` is the one list of what the page and the app say to each other. The Swift side reads
 *  it in `MarfaMacTests/EditorBridgeTests.swift`. Here the page's own types and its `window.editor` must match it, so a
 *  change on one side only fails a test on one side. */
const list = JSON.parse(
  readFileSync(resolve(import.meta.dirname, '../bridge-messages.json'), 'utf8'),
) as {
  host: Record<string, Record<string, unknown>>
  embeds: Record<string, Record<string, unknown>>
  items: Record<string, Record<string, unknown>>
  pictures: Record<string, Record<string, unknown>>
  pictureAsks: string[]
  pageFunctions: string[]
}

type Tagged<K extends string, M> = M extends { type: infer T } ? (K extends T ? M : never) : never
// The keys a message must carry: those not optional, apart from its `type`.
type Required<M> = Exclude<{ [P in keyof M]-?: {} extends Pick<M, P> ? never : P }[keyof M], 'type'>
/** Exactly these keys, each `true`. With no key, only an empty object: `Record<never, true>` is `{}`, which accepts
 *  any object, so a field dropped from a message that then has none would still pass. */
type Exact<Keys extends string> = [Keys] extends [never]
  ? Record<string, never>
  : Record<Keys, true>
/** One entry for each message type, naming exactly its required fields: TypeScript refuses a type or a field the
 *  page's types have and this lacks, and one they lack. */
type Fields<M extends { type: string }> = {
  [K in M['type']]: Exact<Required<Tagged<K, M>> & string>
}

const host: Fields<EditorMessage> = {
  ready: {},
  error: { message: true },
  diagnostic: { message: true },
  hiddenText: {},
  changed: { markdown: true, generation: true },
  state: {
    marks: true,
    block: true,
    quoted: true,
    sourceMode: true,
    inTable: true,
    canUndo: true,
    canRedo: true,
    generation: true,
    formats: true,
    tables: true,
  },
  painted: { generation: true },
  headings: { headings: true, generation: true },
  headerScrolledAway: { away: true, generation: true },
  contentUnderToolbar: { under: true, generation: true },
  titleFocus: { focused: true },
  titleInput: { item: true, text: true },
  titleCommit: { item: true, text: true, startWriting: true },
  titleDiscard: { item: true },
  headerMenu: { item: true, menu: true, rect: true, viewportHeight: true },
  editValue: { item: true, row: true, rect: true, viewportHeight: true },
  fieldMenu: { item: true, row: true, editsValue: true, rect: true, viewportHeight: true },
  valueMoved: { item: true, row: true, rect: true, viewportHeight: true },
  changeType: { item: true, rect: true, viewportHeight: true },
  noticeAction: { item: true, kind: true },
  openLink: { href: true },
  openItem: { item: true },
  cardHover: { item: true, card: true, rect: true, viewportHeight: true },
  cardEnd: {},
  cardMenu: { item: true, card: true, rect: true, viewportHeight: true },
  footMore: { item: true, key: true },
  copy: { text: true },
  escape: {},
  pasteImages: {},
  openEmbed: { embed: true },
  quickLookEmbed: { embed: true },
  embedMenu: { embed: true, opens: true },
  rowMenu: { row: true },
  moveRow: { item: true, row: true, order: true },
  openItemLink: { item: true, raw: true, target: true },
  linkMenu: { item: true, generation: true, link: true, point: true, viewportHeight: true },
  find: {
    snapshotId: true,
    text: true,
    selection: true,
    visible: true,
    boxes: true,
    scrollY: true,
    viewportHeight: true,
    generation: true,
  },
}
const embeds: { request: Exact<Required<EmbedRequest> & string> } = {
  request: { item: true, text: true },
}
const items: Fields<ItemRequest> = {
  suggest: { query: true, item: true },
  pick: { item: true },
  resolve: { item: true, links: true },
}
const pictures: Fields<PictureRequest> = { load: { item: true, address: true, ask: true } }
const asks: Record<PictureAsk, true> = { drawing: true, chosen: true, cached: true }

const source = (file: string) => readFileSync(resolve(import.meta.dirname, '../src', file), 'utf8')
const sorted = (names: Iterable<string>) => [...names].sort()

function shapes(listed: Record<string, Record<string, unknown>>, typed: Record<string, object>) {
  expect(sorted(Object.keys(listed))).toEqual(sorted(Object.keys(typed)))
  for (const [type, body] of Object.entries(listed)) {
    expect(sorted(Object.keys(body)), type).toEqual(sorted(Object.keys(typed[type] ?? {})))
  }
}

test('the page sends the messages the list names, each with the fields it names', () => {
  shapes(list.host, host)
  // The union as written in `bridge.ts`, so a message added there without the list fails here too.
  const union = source('bridge.ts').split('export type EditorMessage =')[1]?.split('\n\n')[0] ?? ''
  const written = [...union.matchAll(/type: ((?:'\w+'(?: \| )?)+)/g)].flatMap((m) =>
    [...(m[1] ?? '').matchAll(/'(\w+)'/g)].map((name) => name[1] ?? ''),
  )
  expect(sorted(written)).toEqual(sorted(Object.keys(list.host)))
})

test('the page asks the app the requests the list names', () => {
  shapes(list.embeds, embeds)
  shapes(list.items, items)
  shapes(list.pictures, pictures)
  expect(sorted(list.pictureAsks)).toEqual(sorted(Object.keys(asks)))
})

test('window.editor offers the functions the list names', () => {
  const block = source('main.ts').split('window.editor = {')[1]?.split('\n}\n')[0] ?? ''
  const offered = [...block.matchAll(/^ {2}(\w+)[:(]/gm)].map((m) => m[1] ?? '')
  expect(offered.length).toBeGreaterThan(0)
  expect(sorted(offered)).toEqual(sorted(list.pageFunctions))
})
