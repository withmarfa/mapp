import {
  Editor,
  defaultValueCtx,
  editorViewCtx,
  editorViewOptionsCtx,
  remarkStringifyOptionsCtx,
  rootCtx,
} from '@milkdown/kit/core'
import { clipboard } from '@milkdown/kit/plugin/clipboard'
import { history, redoCommand, undoCommand } from '@milkdown/kit/plugin/history'
import { redoDepth, undoDepth } from '@milkdown/kit/prose/history'
import { listener, listenerCtx } from '@milkdown/kit/plugin/listener'
import { cursor } from '@milkdown/kit/plugin/cursor'
import {
  blockquoteKeymap,
  blockquoteSchema,
  bulletListKeymap,
  codeBlockKeymap,
  createCodeBlockCommand,
  emphasisKeymap,
  headingKeymap,
  inlineCodeKeymap,
  inlineCodeSchema,
  linkSchema,
  listItemKeymap,
  orderedListKeymap,
  paragraphKeymap,
  strongKeymap,
  toggleEmphasisCommand,
  toggleInlineCodeCommand,
  toggleLinkCommand,
  toggleStrongCommand,
  turnIntoTextCommand,
  wrapInBulletListCommand,
  wrapInHeadingCommand,
  wrapInOrderedListCommand,
} from '@milkdown/kit/preset/commonmark'
import {
  addColAfterCommand,
  addColBeforeCommand,
  addRowAfterCommand,
  addRowBeforeCommand,
  deleteSelectedCellsCommand,
  insertTableCommand,
  selectColCommand,
  selectRowCommand,
  setAlignCommand,
  strikethroughKeymap,
  toggleStrikethroughCommand,
} from '@milkdown/kit/preset/gfm'
import { CellSelection, isInTable, selectedRect } from '@milkdown/kit/prose/tables'
import {
  NodeRange,
  type MarkType,
  type Node as ProseNode,
  type ResolvedPos,
} from '@milkdown/kit/prose/model'
import { keydownHandler, keymap } from '@milkdown/kit/prose/keymap'
import { liftListItem } from '@milkdown/kit/prose/schema-list'
import type { EditorView } from '@milkdown/kit/prose/view'
import { findWrapping, liftTarget } from '@milkdown/kit/prose/transform'
import {
  AllSelection,
  Plugin,
  PluginKey,
  Selection,
  TextSelection,
  type Command,
  type EditorState,
  type Transaction,
} from '@milkdown/kit/prose/state'
import { $prose, callCommand, replaceAll, type $UserKeymap } from '@milkdown/kit/utils'
import { codeCopyPlugin, headingMarkPlugin } from './decorations'
import { dialect, serialize, stringifyOptions } from './dialect'
import { highlightPlugin } from './highlight'
import { pastePlugin } from './paste'
import { selectionPlugin } from './selection'
import { search, SearchQuery, getSearchState, setSearchState } from 'prosemirror-search'
import { tableInterface } from './tables'
import { taskListPlugin, toggleTaskList } from './tasks'

export type Mark = 'bold' | 'italic' | 'strikethrough' | 'code' | 'link'

export type Block =
  | { type: 'paragraph' }
  | { type: 'heading'; level: number }
  | { type: 'codeBlock' }
  | { type: 'bulletList' }
  | { type: 'orderedList' }
  | { type: 'taskList' }

export interface CaretState {
  marks: Mark[]
  block: Block
  /** One quote holds the whole selection; the block is what sits inside it. */
  quoted: boolean
  /** The caret is in a table, so the table commands apply. */
  inTable: boolean
  canUndo: boolean
  canRedo: boolean
}

export type FormatCommand =
  | 'heading'
  | 'paragraph'
  | 'bold'
  | 'italic'
  | 'strikethrough'
  | 'code'
  | 'codeBlock'
  | 'quote'
  | 'bulletList'
  | 'orderedList'
  | 'taskList'
  | 'link'
  | 'table'
  | 'addRowAbove'
  | 'addRowBelow'
  | 'addColumnBefore'
  | 'addColumnAfter'
  | 'deleteRow'
  | 'deleteColumn'
  | 'alignColumn'

/** The keys the app binds, in ProseMirror's names, to the format command and argument each runs. The app
 *  owns them, since its Format menu shows the same shortcuts. */
export type Keymap = Record<string, [FormatCommand, string?]>

export interface EditorEvents {
  changed(markdown: string, generation: number): void
  stateChanged(state: CaretState): void
  openLink(href: string): void
  copy(text: string): void
  /** Escape, which nothing in the page uses, hands the keyboard back to the app. */
  escape(): void
}

const markNames: Record<string, Mark> = {
  strong: 'bold',
  emphasis: 'italic',
  strike_through: 'strikethrough',
  inlineCode: 'code',
  link: 'link',
}

// Select All resolves at the document level, where no block can be read.
function textBounds(state: EditorState): { $from: ResolvedPos; $to: ResolvedPos } {
  const { selection, doc } = state
  if (selection instanceof AllSelection)
    return TextSelection.between(doc.resolve(0), doc.resolve(doc.content.size))
  return selection
}

function caretState(state: EditorState): CaretState {
  const { empty } = state.selection
  const { $from, $to } = textBounds(state)
  const active = new Set<Mark>()
  const marks = empty ? (state.storedMarks ?? $from.marks()) : []
  for (const mark of marks) {
    const name = markNames[mark.type.name]
    if (name) active.add(name)
  }
  if (!empty) {
    for (const [name, mark] of Object.entries(markNames)) {
      const type = state.schema.marks[name]
      if (type && state.doc.rangeHasMark($from.pos, $to.pos, type)) active.add(mark)
    }
  }
  return {
    marks: [...active],
    block: blockAt($from),
    quoted: quoted($from, $to),
    inTable: isInTable(state),
    canUndo: undoDepth(state) > 0,
    canRedo: redoDepth(state) > 0,
  }
}

// True only when one quote holds the whole selection, so the state matches what the command can lift.
function quoted($from: ResolvedPos, $to: ResolvedPos): boolean {
  return $from.blockRange($to, (node) => node.type.name === 'blockquote') != null
}

function blockAt($from: EditorState['selection']['$from']): Block {
  for (let depth = $from.depth; depth > 0; depth--) {
    const node = $from.node(depth)
    switch (node.type.name) {
      case 'heading':
        return { type: 'heading', level: node.attrs.level }
      case 'code_block':
        return { type: 'codeBlock' }
      case 'list_item':
        return node.attrs.checked == null
          ? {
              type:
                $from.node(depth - 1).type.name === 'ordered_list' ? 'orderedList' : 'bulletList',
            }
          : { type: 'taskList' }
    }
  }
  return { type: 'paragraph' }
}

// Backspace at the start of a quote's first block is left alone by the preset;
// leaving the quote is what a Backspace there means.
const quoteBackspace = $prose(() =>
  keymap({
    Backspace: (state, dispatch) => {
      const { $from, empty } = state.selection
      if (!empty || $from.parentOffset > 0 || $from.depth < 2) return false
      if (
        $from.node($from.depth - 1).type.name !== 'blockquote' ||
        $from.index($from.depth - 1) > 0
      )
        return false
      const range = $from.blockRange($from, (node) => node.type.name === 'blockquote')
      const target = range && liftTarget(range)
      if (!range || target == null) return false
      dispatch?.(state.tr.lift(range, target).scrollIntoView())
      return true
    },
  }),
)

// The preset lifts only an item's first line, which cannot leave on its own while the item holds
// more, such as a nested list. The whole item is lifted instead, and a nested list it held joins the
// items that followed, since both then sit at one level.
const listItemBackspace = $prose(() =>
  keymap({
    Backspace: (state, dispatch) => {
      const { $from, empty } = state.selection
      if (!empty || $from.parentOffset > 0 || $from.depth < 3) return false
      const item = $from.node(-1)
      if (
        item.type.name !== 'list_item' ||
        item.childCount < 2 ||
        $from.index(-1) > 0 ||
        $from.index(-2) > 0
      )
        return false
      const { doc } = state
      const range = new NodeRange(
        doc.resolve($from.start(-1)),
        doc.resolve($from.end(-1)),
        $from.depth - 1,
      )
      const target = liftTarget(range)
      if (target == null) return false
      const tr = state.tr.lift(range, target)
      const $line = tr.doc.resolve(tr.mapping.map($from.pos))
      joinLists(tr, $line.start(-1), $line.index(-1) + item.childCount)
      dispatch?.(tr.scrollIntoView())
      return true
    },
  }),
)

// Lifting an item out of a list that no item holds, the preset leaves a nested list the item held
// beside the items that followed. Out of a nested list it joins the two itself.
const liftItem: Command = (state, dispatch) => {
  const itemType = state.schema.nodes.list_item!
  const { $from, $to } = state.selection
  const range = $from.blockRange($to, (node) => node.firstChild?.type === itemType)
  const lift = liftListItem(itemType)
  if (!range || !dispatch || $from.node(range.depth - 1).type === itemType)
    return lift(state, dispatch)
  let lifted: Transaction | undefined
  if (!lift(state, (tr) => (lifted = tr)) || !lifted) return false
  let count = 0
  for (let index = range.startIndex; index < range.endIndex; index++)
    count += range.parent.child(index).childCount
  const start = range.$from.start(range.depth - 1)
  const first = range.$from.index(range.depth - 1) + (range.startIndex > 0 ? 1 : 0)
  joinLists(lifted, start, first + count)
  dispatch(lifted)
  return true
}

const listItemShiftTab = $prose(() => keymap({ 'Shift-Tab': liftItem }))

// A control chord that nothing handles reaches the page as its ASCII control character
// (Control-N as U+000E), which the web view would insert as text.
const controlCharacters = /^[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]+$/
const dropControlCharacters = $prose(
  () =>
    new Plugin({
      key: new PluginKey('dropControlCharacters'),
      props: {
        handleTextInput: (_view, _from, _to, text) => controlCharacters.test(text),
      },
    }),
)

// The listener plugin reports selection changes from inside state.apply, before
// the view holds the new state, so the caret state is read from the view instead.
function caretStatePlugin(events: EditorEvents) {
  return $prose(
    () =>
      new Plugin({
        key: new PluginKey('caretState'),
        view: () => ({
          update(view, previous) {
            const { state } = view
            if (
              state.selection.eq(previous.selection) &&
              state.doc.eq(previous.doc) &&
              state.storedMarks === previous.storedMarks
            )
              return
            events.stateChanged(caretState(state))
          },
        }),
      }),
  )
}

function outermostListDepth($pos: ResolvedPos): number | null {
  for (let depth = 1; depth <= $pos.depth; depth++) {
    if (isList($pos.node(depth))) return depth
  }
  return null
}

function innermostListDepth($pos: ResolvedPos): number | null {
  for (let depth = $pos.depth; depth >= 1; depth--) {
    if (isList($pos.node(depth))) return depth
  }
  return null
}

function isList(node: ProseNode): boolean {
  return node.type.name === 'bullet_list' || node.type.name === 'ordered_list'
}

// Two lists of one kind side by side are written with a changed marker to keep them apart, and the
// memo shows a gap between them, so an edit that leaves them so joins them.
function joinLists(tr: Transaction, start: number, index: number): void {
  const $start = tr.doc.resolve(start)
  const before = $start.parent.maybeChild(index - 1)
  const after = $start.parent.maybeChild(index)
  if (before && after && isList(before) && after.type === before.type)
    tr.join($start.posAtIndex(index))
}

export class NoteEditor {
  private editor!: Editor
  private lastMarkdown = ''
  private baseline = ''
  private generation = 0
  private keys: (view: EditorView, event: KeyboardEvent) => boolean = () => false
  private editable = true
  /** The range the last search selected, so clearing the search lets go of that and not of the reader's own. */
  private found: { from: number; to: number } | null = null

  private constructor(private readonly events: EditorEvents) {}

  // The app's bindings, replaced whole whenever they change; the plugin stays.
  private keymapPlugin = $prose(
    () =>
      new Plugin({
        key: new PluginKey('appKeymap'),
        props: { handleKeyDown: (view, event) => this.keys(view, event) },
      }),
  )

  static async mount(root: HTMLElement, events: EditorEvents): Promise<NoteEditor> {
    const instance = new NoteEditor(events)
    instance.editor = await Editor.make()
      .config((ctx) => {
        ctx.set(rootCtx, root)
        ctx.set(defaultValueCtx, '')
        ctx.set(remarkStringifyOptionsCtx, stringifyOptions)
        // The preset also binds Mod-[ and Mod-] here; the app uses those for back and forward.
        // Shift-Tab is bound to liftItem instead.
        ctx.update(listItemKeymap.key, (keys) => ({
          ...keys,
          SinkListItem: { shortcuts: 'Tab' },
          LiftListItem: { shortcuts: [] },
        }))
        // Formatting keys are the app's to set, through setKeymap; the presets' own go.
        const unbind = <K extends string>(keymap: $UserKeymap<string, K>, keep: K[] = []) =>
          ctx.update(keymap.key, (keys) => {
            const cleared = { ...keys }
            for (const name of Object.keys(cleared) as K[]) {
              if (!keep.includes(name)) cleared[name] = { shortcuts: [] }
            }
            return cleared
          })
        unbind(strongKeymap)
        unbind(emphasisKeymap)
        unbind(inlineCodeKeymap)
        unbind(strikethroughKeymap)
        unbind(headingKeymap, ['DowngradeHeading'])
        unbind(paragraphKeymap)
        unbind(blockquoteKeymap)
        unbind(codeBlockKeymap)
        unbind(bulletListKeymap)
        unbind(orderedListKeymap)
        ctx.update(editorViewOptionsCtx, (options) => ({
          ...options,
          editable: () => instance.editable,
          handleKeyDown: (_view, event) => {
            if (event.key !== 'Escape' || event.metaKey || event.ctrlKey || event.altKey) return false
            events.escape()
            return true
          },
          scrollThreshold: 24,
          scrollMargin: 24,
        }))
        ctx.get(listenerCtx).updated((ctx, doc) => {
          const markdown = serialize(ctx, doc)
          if (markdown === instance.lastMarkdown) return
          instance.lastMarkdown = markdown
          events.changed(markdown, instance.generation)
        })
      })
      .use(caretStatePlugin(events))
      .use(pastePlugin)
      .use(instance.keymapPlugin)
      .use(dialect)
      .use(listener)
      .use(history)
      .use(clipboard)
      .use(cursor)
      .use(taskListPlugin)
      .use(tableInterface)
      .use(quoteBackspace)
      .use(listItemBackspace)
      .use(listItemShiftTab)
      .use(dropControlCharacters)
      .use(codeCopyPlugin((text) => events.copy(text)))
      .use(headingMarkPlugin)
      .use(highlightPlugin)
      .use(selectionPlugin)
      .use($prose(() => search()))
      .create()
    root.addEventListener('click', (event) => {
      const anchor = (event.target as HTMLElement).closest('a[href]')
      if (anchor && event.metaKey) {
        event.preventDefault()
        events.openLink(anchor.getAttribute('href') ?? '')
      }
    })
    return instance
  }

  load(markdown: string, generation: number): void {
    // A loaded document only counts as changed once it is edited, so its
    // canonical form is the baseline, not the text as stored.
    this.generation = generation
    this.editor.action(replaceAll(markdown, true))
    this.baseline = serialize(this.editor.ctx)
    this.lastMarkdown = this.baseline
    const view = this.editor.ctx.get(editorViewCtx)
    // A caret at the end, where writing carries on; at the start it would sit in a first-line heading and
    // show its marks. The last place text can go, so a document ending in a rule takes a caret above it
    // rather than selecting the rule itself.
    const { doc } = view.state
    const end = Selection.findFrom(doc.resolve(doc.content.size), -1, true) ?? Selection.atEnd(doc)
    this.found = null
    view.dispatch(
      setSearchState(
        view.state.tr.setSelection(end).scrollIntoView(),
        new SearchQuery({ search: '' }),
      ),
    )
    this.events.stateChanged(caretState(view.state))
  }

  /** The same memo, written from outside while it was open: the text is replaced under the caret. */
  reload(markdown: string, generation: number): void {
    const view = this.editor.ctx.get(editorViewCtx)
    const at = view.state.selection.from
    const scroller = view.dom.parentElement
    const scrollTop = scroller?.scrollTop ?? 0
    this.generation = generation
    this.editor.action(replaceAll(markdown, true))
    this.baseline = serialize(this.editor.ctx)
    this.lastMarkdown = this.baseline
    const { doc } = view.state
    const $at = doc.resolve(Math.min(at, doc.content.size))
    const selection = Selection.findFrom($at, -1, true) ?? Selection.atEnd(doc)
    view.dispatch(view.state.tr.setSelection(selection))
    if (scroller) scroller.scrollTop = scrollTop
    this.events.stateChanged(caretState(view.state))
  }

  canonicalMarkdown(): string {
    return serialize(this.editor.ctx)
  }

  /** The document as markdown, or null while it is still what was loaded. */
  markdown(): string | null {
    const markdown = serialize(this.editor.ctx)
    return markdown === this.baseline ? null : markdown
  }

  find(text: string): void {
    const view = this.editor.ctx.get(editorViewCtx)
    const { selection } = view.state
    const previous = getSearchState(view.state)?.query.search
    const query = new SearchQuery({ search: text, literal: true })
    const selectedBySearch = this.found?.from === selection.from && this.found?.to === selection.to
    let tr = setSearchState(view.state.tr, query)
    const match = text
      ? (query.findNext(view.state, previous === text ? selection.to : selection.from) ??
        query.findNext(view.state, 0))
      : null
    if (match) {
      tr = tr.setSelection(TextSelection.create(tr.doc, match.from, match.to)).scrollIntoView()
      this.found = { from: match.from, to: match.to }
    } else {
      if (selectedBySearch) tr = tr.setSelection(Selection.near(selection.$to))
      this.found = null
    }
    view.dispatch(tr)
  }

  focus(): void {
    this.editor.ctx.get(editorViewCtx).focus()
  }

  /** Binds keys, in ProseMirror's names, to the formatting each runs; replaces the previous bindings. */
  setKeymap(keymap: Keymap): void {
    const bindings: Record<string, Command> = {}
    for (const [key, [command, arg]] of Object.entries(keymap)) {
      bindings[key] = () => {
        this.format(command, arg)
        return true
      }
    }
    this.keys = keydownHandler(bindings)
  }

  /** A deleted note can be read and not changed. */
  setEditable(editable: boolean): void {
    this.editable = editable
    const view = this.editor.ctx.get(editorViewCtx)
    view.setProps({ editable: () => this.editable })
  }

  undo(): void {
    this.editor.action(callCommand(undoCommand.key))
  }

  redo(): void {
    this.editor.action(callCommand(redoCommand.key))
  }

  // Removing a mark at a caret only clears the stored mark, so the whole marked
  // run is selected for the command and the caret put back after it.
  private withMarkRunSelected(mark: MarkType, command: () => void): boolean {
    const view = this.editor.ctx.get(editorViewCtx)
    const { selection, doc } = view.state
    if (!selection.empty) return false
    const $pos = selection.$from
    const parent = $pos.parent
    const start = $pos.start()
    let from = $pos.pos
    let to = $pos.pos
    parent.forEach((child, offset) => {
      const childFrom = start + offset
      const childTo = childFrom + child.nodeSize
      if (!mark.isInSet(child.marks)) return
      if (childTo >= $pos.pos && childFrom <= to) {
        from = Math.min(from, childFrom)
        to = Math.max(to, childTo)
      }
    })
    if (from === to) return false
    view.dispatch(view.state.tr.setSelection(TextSelection.create(doc, from, to)))
    command()
    const caret = Math.min($pos.pos, view.state.doc.content.size)
    view.dispatch(view.state.tr.setSelection(TextSelection.create(view.state.doc, caret)))
    return true
  }

  // Milkdown's inline code command ignores a caret; a stored mark makes the
  // next typed text code, the way bold and italic behave.
  private toggleInlineCode(): void {
    const view = this.editor.ctx.get(editorViewCtx)
    const type = inlineCodeSchema.type(this.editor.ctx)
    const run = () => {
      this.editor.action(callCommand(toggleInlineCodeCommand.key))
    }
    const { selection, storedMarks } = view.state
    if (!selection.empty) return run()
    // A pending stored mark is only that; the span next to the caret is left alone.
    if (storedMarks) {
      const tr = type.isInSet(storedMarks)
        ? view.state.tr.removeStoredMark(type)
        : view.state.tr.addStoredMark(type.create())
      return view.dispatch(tr)
    }
    if (!type.isInSet(selection.$from.marks()))
      view.dispatch(view.state.tr.addStoredMark(type.create()))
    else this.withMarkRunSelected(type, run)
  }

  private list(kind: 'bulletList' | 'orderedList'): void {
    const view = this.editor.ctx.get(editorViewCtx)
    const { state } = view
    const { $from } = textBounds(state)
    const wanted = kind === 'bulletList' ? 'bullet_list' : 'ordered_list'
    const depth = innermostListDepth($from)
    if (depth == null) {
      const command = kind === 'bulletList' ? wrapInBulletListCommand : wrapInOrderedListCommand
      this.editor.action(callCommand(command.key))
      return
    }
    const list = $from.node(depth)
    if (list.type.name === wanted) {
      liftItem(state, view.dispatch)
      return
    }
    // The items carry the list kind too, and a bullet list whose items say
    // ordered is turned back into one by the preset.
    const pos = $from.before(depth)
    const ordered = wanted === 'ordered_list'
    const attrs = ordered ? { order: 1, spread: list.attrs.spread } : { spread: list.attrs.spread }
    let tr = state.tr.setNodeMarkup(pos, state.schema.nodes[wanted], attrs)
    list.forEach((item, offset) => {
      tr = tr.setNodeMarkup(pos + 1 + offset, undefined, {
        ...item.attrs,
        listType: ordered ? 'ordered' : 'bullet',
        label: ordered ? '1.' : '•',
      })
    })
    view.dispatch(tr)
  }

  private quote(): void {
    const view = this.editor.ctx.get(editorViewCtx)
    const type = blockquoteSchema.type(this.editor.ctx)
    const { $from, $to } = textBounds(view.state)
    let range = $from.blockRange($to)
    let wrapping = range && findWrapping(range, type)
    if (!wrapping) {
      // A list item's first block stays a paragraph, so a quote there takes the whole list instead.
      const depth = outermostListDepth($from)
      if (depth == null) return
      const doc = view.state.doc
      range = new NodeRange(
        doc.resolve($from.before(depth)),
        doc.resolve($from.after(depth)),
        depth - 1,
      )
      wrapping = findWrapping(range, type)
    }
    if (!range || !wrapping) return
    view.dispatch(view.state.tr.wrap(range, wrapping))
  }

  private unquote(): void {
    const view = this.editor.ctx.get(editorViewCtx)
    const { $from, $to } = textBounds(view.state)
    const range = $from.blockRange($to, (node) => node.type.name === 'blockquote')
    if (!range) return
    const target = liftTarget(range)
    if (target == null) return
    view.dispatch(view.state.tr.lift(range, target))
  }

  /** The row or column the caret is in, whole: the table's own delete takes only the selected cells. */
  private deleteTableLine(line: 'row' | 'column'): void {
    const view = this.editor.ctx.get(editorViewCtx)
    if (!isInTable(view.state)) return
    if (!(view.state.selection instanceof CellSelection)) {
      const rect = selectedRect(view.state)
      const select = line === 'row' ? selectRowCommand : selectColCommand
      this.editor.action(
        callCommand(select.key, { index: line === 'row' ? rect.top : rect.left }),
      )
    }
    this.editor.action(callCommand(deleteSelectedCellsCommand.key))
  }

  format(command: FormatCommand, arg?: string | number): void {
    const run = (cmd: Parameters<typeof callCommand>[0], payload?: unknown) =>
      this.editor.action(callCommand(cmd, payload))
    const state = caretState(this.editor.ctx.get(editorViewCtx).state)
    switch (command) {
      case 'heading': {
        const level = Number(arg ?? 1)
        if (state.block.type === 'heading' && state.block.level === level)
          run(turnIntoTextCommand.key)
        else run(wrapInHeadingCommand.key, level)
        break
      }
      case 'paragraph':
        run(turnIntoTextCommand.key)
        break
      case 'bold':
        run(toggleStrongCommand.key)
        break
      case 'italic':
        run(toggleEmphasisCommand.key)
        break
      case 'strikethrough':
        run(toggleStrikethroughCommand.key)
        break
      case 'code':
        this.toggleInlineCode()
        break
      case 'codeBlock':
        if (state.block.type === 'codeBlock') run(turnIntoTextCommand.key)
        else run(createCodeBlockCommand.key, typeof arg === 'string' ? arg : '')
        break
      case 'quote':
        if (state.quoted) this.unquote()
        else this.quote()
        break
      case 'bulletList':
      case 'orderedList':
        this.list(command)
        break
      case 'taskList':
        toggleTaskList(this.editor.ctx)
        break
      case 'table':
        if (!isInTable(this.editor.ctx.get(editorViewCtx).state))
          run(insertTableCommand.key, { row: 3, col: 3 })
        break
      case 'addRowAbove':
        run(addRowBeforeCommand.key)
        break
      case 'addRowBelow':
        run(addRowAfterCommand.key)
        break
      case 'addColumnBefore':
        run(addColBeforeCommand.key)
        break
      case 'addColumnAfter':
        run(addColAfterCommand.key)
        break
      case 'deleteRow':
      case 'deleteColumn':
        this.deleteTableLine(command === 'deleteRow' ? 'row' : 'column')
        break
      case 'alignColumn': {
        const align = arg === 'center' || arg === 'right' ? arg : 'left'
        run(setAlignCommand.key, align)
        break
      }
      case 'link': {
        const payload = typeof arg === 'string' ? { href: arg } : {}
        const toggle = () => run(toggleLinkCommand.key, payload)
        if (
          !state.marks.includes('link') ||
          !this.withMarkRunSelected(linkSchema.type(this.editor.ctx), toggle)
        )
          toggle()
        break
      }
    }
    this.focus()
  }
}
