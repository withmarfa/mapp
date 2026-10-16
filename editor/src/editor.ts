import {
  InkKitEditor,
  InkKitError,
  type CaretState as InkCaret,
  type EditorLabels,
  type FileReference,
  type FormatCommand as InkFormat,
  type ShortcutName,
  type TableCommand,
  type ReadableTextSnapshot,
} from '@aicayzer/inkkit'
import { pickNote, postToHost, suggestNotes, type EmbeddedFile, type EmbedRequest } from './bridge'
import type { HeaderLabels } from './header'

/** A preview that could not be drawn is a diagnostic for the log, not an error in the person's edit. */
export function isPreviewDiagnostic(error: Error): boolean {
  return (
    error instanceof InkKitError &&
    (error.code === 'diagram-unavailable' || error.code === 'file-unavailable')
  )
}

/** The words the app hands the page. InkKit rejects a label it does not know, so only InkKit's own go to it;
 *  the header's, the note reference's and the Link to Note command's are MAPP's. */
export interface AppWords {
  noteReference?: string
  linkToNote?: string
}
export type AppLabels = Partial<EditorLabels & HeaderLabels> & AppWords
const headerLabelKeys: readonly (keyof HeaderLabels)[] = [
  'untitled',
  'title',
  'itemType',
  'status',
  'discardChanges',
  'propertyRejected',
]
export function splitLabels(all: AppLabels): {
  editor: Partial<EditorLabels>
  header: Partial<HeaderLabels>
  words: AppWords
} {
  const { noteReference, linkToNote, ...rest } = all
  const header: Partial<HeaderLabels> = {}
  for (const key of headerLabelKeys) {
    if (key in rest) header[key] = rest[key]
    delete rest[key]
  }
  return { editor: rest, header, words: { noteReference, linkToNote } }
}

export function guardedCommand<T>(action: () => T): T | { commandError: string; message: string } {
  try {
    return action()
  } catch (error) {
    if (error instanceof InkKitError) {
      // InkKit tells only the caller of a refused edit, so the app is told here, where it tells the person.
      if (error.code === 'preservation') postToHost({ type: 'error', message: error.message })
      return { commandError: error.code, message: error.message }
    }
    throw error
  }
}

export type CaretState = InkCaret & {
  sourceMode: boolean
  inTable: boolean
  canUndo: boolean
  canRedo: boolean
  generation: number
  formats: Record<string, boolean>
  tables: Record<string, boolean>
}
export type FormatCommand =
  | InkFormat
  | 'heading'
  | 'table'
  | 'addRowAbove'
  | 'addRowBelow'
  | 'addColumnBefore'
  | 'addColumnAfter'
  | 'deleteRow'
  | 'deleteColumn'
  | 'alignColumn'
export type Keymap = Record<string, [FormatCommand, string?]>
export interface FindState {
  snapshotId: string
  text: string
  selection: [number, number]
  visible: [number, number]
  boxes: number[]
  scrollY: number
  viewportHeight: number
  generation: number
}
export interface EditorEvents {
  changed(text: string, generation: number): void
  stateChanged(state: CaretState): void
  find(state: FindState): void
  openLink(href: string): void
  copy(text: string): void
}
const tables: Partial<Record<FormatCommand, TableCommand>> = {
  table: 'insert',
  addRowAbove: 'addRowBefore',
  addRowBelow: 'addRowAfter',
  addColumnBefore: 'addColumnBefore',
  addColumnAfter: 'addColumnAfter',
  deleteRow: 'deleteRow',
  deleteColumn: 'deleteColumn',
}
function request(reference: FileReference, item: string): EmbedRequest {
  return reference.kind === 'wiki'
    ? { item, name: reference.target }
    : { item, path: reference.reference }
}

function isNoteReference(reference: FileReference): boolean {
  const target = reference.target.split('?')[0]!
  const name = target.split('/').pop() ?? target
  return /\.(md|markdown|txt)$/i.test(name) || (reference.kind === 'wiki' && !name.includes('.'))
}

/** The app bridge uses only InkKit's public facade; native libraries retain file and save policy. */
export class NoteEditor {
  private engine!: InkKitEditor
  private finding = false
  private findPending = 0
  private layoutObserver?: ResizeObserver
  private generation = 0
  private item = ''
  private reported = ''
  private original = ''
  private constructor(private events: EditorEvents) {}
  static async mount(
    root: HTMLElement,
    events: EditorEvents,
    labels: Partial<EditorLabels> = {},
    words: AppWords = {},
  ): Promise<NoteEditor> {
    const host = new NoteEditor(events)
    const described = new Map<string, EmbeddedFile>()
    host.engine = await InkKitEditor.mount(
      root,
      {
        changed({ text, generation }) {
          host.pendingChanged = { text, generation }
          queueMicrotask(() => host.flushChanges())
          host.invalidateFindGeometry()
        },
        commandStateChanged(state) {
          events.stateChanged({
            ...state.caret,
            sourceMode: state.mode === 'source',
            inTable: !!state.table,
            canUndo: state.commands.undo,
            canRedo: state.commands.redo,
            generation: state.generation,
            formats: state.commands.format,
            tables: state.commands.table,
          })
          host.invalidateFindGeometry()
        },
        openLink: events.openLink,
        copy: events.copy,
        error(error) {
          postToHost({
            type: isPreviewDiagnostic(error) ? 'diagnostic' : 'error',
            message: error.message,
          })
        },
      },
      {
        labels,
        files: {
          async resolve(reference, context) {
            if (isNoteReference(reference))
              return {
                kind: 'file',
                label:
                  words.noteReference?.replace('%@', reference.label ?? reference.reference) ??
                  `Note reference: ${reference.label ?? reference.reference}. Open to edit source.`,
              }
            const embed = request(reference, context.documentId)
            const file = await window.webkit?.messageHandlers?.embeds?.postMessage(embed)
            if (!file || context.signal.aborted)
              return { kind: 'missing', label: reference.label ?? reference.reference }
            described.set(JSON.stringify(embed), file)
            if (file.kind === 'file') return { kind: 'file', label: file.name }
            if (file.kind === 'pdf')
              return {
                kind: 'file',
                label: `${file.name}: ${labels.filePDFPreview ?? 'Open to view this PDF'}`,
              }
            return {
              kind: file.kind,
              url: file.url + (reference.fragment ? '#' + reference.fragment : ''),
              label: file.name,
            }
          },
          async exportImage(reference, context) {
            const embed = request(reference, context.documentId)
            const result = (await window.webkit?.messageHandlers?.embeds?.postMessage({
              ...embed,
              export: true,
            })) as unknown as { data?: string; mimeType?: string } | null
            if (!result?.data || !result.mimeType)
              throw new InkKitError('image-unavailable', 'The embedded image could not be read.')
            return {
              bytes: Uint8Array.from(atob(result.data), (char) => char.charCodeAt(0)),
              mimeType: result.mimeType,
            }
          },
          open(reference, context) {
            if (isNoteReference(reference)) {
              host.setEditingMode('source', context.generation)
              host.focus()
              return
            }
            postToHost({ type: 'openEmbed', embed: request(reference, context.documentId) })
          },
          contextMenu(reference, _point, context) {
            const embed = request(reference, context.documentId)
            postToHost({
              type: 'embedMenu',
              embed,
              opens: described.get(JSON.stringify(embed))?.opens ?? false,
            })
          },
        },
        wikiLinks: {
          // The app matches names against its library; a request the person has typed past is not sent.
          suggest: (query, context) =>
            context.signal.aborted ? Promise.resolve([]) : suggestNotes(query, context.documentId),
          // InkKit requires the adapter to open a link. Opening the note it names is not offered yet.
          open() {},
        },
        slashMenu: {
          enabled: true,
          customCommands: [
            {
              name: words.linkToNote ?? 'Link to Note',
              keywords: ['note', 'wiki', 'reference'],
              // The app asks the person which note, and answers with the link, or nothing if they decline.
              action: (context) => pickNote(context.documentId),
            },
          ],
        },
      },
    )
    host.engine.setViewport({ scrollContainer: document.documentElement })
    window.addEventListener('scroll', host.scrolled, { passive: true, capture: true })
    window.addEventListener('resize', host.scrolled)
    root.addEventListener('load', host.scrolled, true)
    root.addEventListener('loadedmetadata', host.scrolled, true)
    document.fonts?.addEventListener('loadingdone', host.scrolled)
    host.layoutRoot = root
    host.layoutObserver = new ResizeObserver(host.scrolled)
    host.layoutObserver.observe(root)
    return host
  }
  setItem(id: string) {
    this.item = id
  }
  private pendingChanged?: { text: string; generation: number }
  private flushChanges() {
    const pending = this.pendingChanged
    this.pendingChanged = undefined
    if (!pending) return
    if (pending.generation === this.generation) this.reported = pending.text
    this.events.changed(pending.text, pending.generation)
  }
  private replacement = 0
  get loadedGeneration() {
    return this.generation
  }
  private replace(text: string, generation: number, editable: boolean, reload: boolean) {
    const request = ++this.replacement
    const documentId = this.item
    const apply = () => {
      if (request !== this.replacement) return
      try {
        this.flushChanges()
        if (this.generation) {
          const previous = this.snapshot()
          if (previous.text !== this.reported)
            this.events.changed(previous.text, previous.generation)
        }
        const input = { documentId, generation, format: 'md' as const, text }
        if (reload) this.engine.reloadDocument(input)
        else this.engine.loadDocument(input)
        this.engine.setEditable(editable)
        this.generation = generation
        this.reported = text
        this.original = text
        if (!reload) window.scrollTo(0, 0)
        this.invalidateFindGeometry()
      } catch (error) {
        if (
          error instanceof InkKitError &&
          (error.code === 'composition' || error.code === 'operation-pending')
        ) {
          setTimeout(apply, 50)
          return
        }
        throw error
      }
    }
    apply()
  }
  load(text: string, generation: number, editable = true) {
    this.replace(text, generation, editable, false)
  }
  reload(text: string, generation: number, editable = true) {
    this.replace(text, generation, editable, true)
  }
  readableSnapshot(expected = this.generation) {
    return this.engine.textSnapshot(expected)
  }
  snapshot(expected = this.generation) {
    return this.engine.snapshot(expected)
  }
  markdown(): string | null {
    const snapshot = this.snapshot()
    return snapshot.text === this.original ? null : snapshot.text
  }
  flush(expected = this.generation): string | null {
    const text = this.snapshot(expected).text
    if (this.pendingChanged?.generation === expected) this.pendingChanged = undefined
    if (text === this.reported) return null
    this.reported = text
    return text
  }
  focus() {
    this.engine.focus()
  }
  blur(expected = this.generation) {
    this.engine.blur(expected)
  }
  setEditingMode(mode: 'source' | 'formatted', expected = this.generation) {
    this.engine.setEditingMode(mode, expected)
    this.invalidateFindGeometry()
  }
  undo(expected = this.generation) {
    this.engine.undo(expected)
  }
  redo(expected = this.generation) {
    this.engine.redo(expected)
  }
  format(command: FormatCommand, arg?: string | number, expected = this.generation) {
    const table =
      command === 'alignColumn'
        ? ({ left: 'alignLeft', center: 'alignCenter', right: 'alignRight' } as const)[
            arg as 'left' | 'center' | 'right'
          ]
        : tables[command]
    if (table) return this.engine.table(table, undefined, expected)
    return this.engine.format(
      (command === 'heading' ? 'heading' + arg : command) as InkFormat,
      undefined,
      expected,
    )
  }
  setKeymap(bindings: Keymap) {
    const keys: Partial<Record<ShortcutName, string[]>> = {}
    for (const [key, [command, arg]] of Object.entries(bindings)) {
      const name = (
        tables[command]
          ? 'table' + tables[command]![0]!.toUpperCase() + tables[command]!.slice(1)
          : command === 'heading'
            ? 'heading' + arg
            : command
      ) as ShortcutName
      ;(keys[name] ??= []).push(key)
    }
    this.engine.setKeymap(keys)
  }
  setSpellcheck(spellcheck: boolean) {
    this.engine.setTextInputPreferences({ spellcheck })
  }
  setFinding(finding: boolean) {
    this.finding = finding
    cancelAnimationFrame(this.findPending)
    this.findPending = 0
    if (finding) this.sendFind()
  }
  private layoutRoot?: HTMLElement
  private scrolled = () => this.invalidateFindGeometry()
  invalidateFindGeometry() {
    if (!this.finding || this.findPending) return
    this.findPending = requestAnimationFrame(() => {
      this.findPending = 0
      this.sendFind()
    })
  }
  private range(from: number, to: number, snapshot: ReadableTextSnapshot) {
    return { snapshotId: snapshot.snapshotId, from, to }
  }
  private sendFind() {
    if (!this.finding) return
    try {
      const snapshot = this.engine.textSnapshot(this.generation)
      const visible = this.engine.visibleTextRanges(snapshot.snapshotId)
      const from = visible[0]?.from ?? 0,
        to = visible.at(-1)?.to ?? 0
      const boxes: number[] = new Array((to - from) * 4).fill(0)
      const characters: ReturnType<NoteEditor['range']>[] = []
      for (const range of visible) {
        for (let at = range.from; at < range.to;) {
          const length = (snapshot.text.codePointAt(at) ?? 0) > 0xffff ? 2 : 1
          characters.push(this.range(at, Math.min(at + length, range.to), snapshot))
          at += length
        }
      }
      const geometry = this.engine.textRangesRects(characters)
      for (const [index, range] of characters.entries()) {
        const rect = geometry[index]?.[0]
        for (let at = range.from; at < range.to; at++) {
          const base = (at - from) * 4
          boxes[base] = rect?.left ?? 0
          boxes[base + 1] = (rect?.top ?? 0) + window.scrollY
          boxes[base + 2] = rect?.width ?? 0
          boxes[base + 3] = rect?.height ?? 0
        }
      }
      this.events.find({
        snapshotId: snapshot.snapshotId,
        text: snapshot.text,
        selection: [snapshot.selection.from, snapshot.selection.to],
        visible: [from, to],
        boxes,
        scrollY: window.scrollY,
        viewportHeight: window.innerHeight,
        generation: this.generation,
      })
    } catch (error) {
      if (!(error instanceof InkKitError)) throw error
    }
  }
  findSelect(from: number, to: number, generation = this.generation, snapshotId?: string) {
    const snapshot = this.engine.textSnapshot(generation)
    this.engine.selectTextRange({ snapshotId: snapshotId ?? snapshot.snapshotId, from, to })
  }
  findScroll(from: number, generation = this.generation, snapshotId?: string) {
    const snapshot = this.engine.textSnapshot(generation)
    this.engine.revealTextRange({ snapshotId: snapshotId ?? snapshot.snapshotId, from, to: from })
  }
  private failedReplacementBatch?: string
  private replacementBatch?: { id: string; snapshotId: string }
  findReplace(
    from: number,
    to: number,
    text: string,
    generation = this.generation,
    snapshotId?: string,
    batch?: string,
  ) {
    try {
      if (batch && this.failedReplacementBatch === batch)
        throw new InkKitError('stale-document', 'An earlier replacement in this batch failed.')
      const snapshot = this.engine.textSnapshot(generation)
      const continuing = batch && this.replacementBatch?.id === batch
      if (continuing && snapshot.snapshotId !== this.replacementBatch!.snapshotId)
        throw new InkKitError('stale-document', 'The text changed before replacement.')
      this.engine.replaceTextRange(
        {
          snapshotId: continuing ? snapshot.snapshotId : (snapshotId ?? snapshot.snapshotId),
          from,
          to,
        },
        text,
      )
      this.replacementBatch = batch
        ? { id: batch, snapshotId: this.engine.textSnapshot(generation).snapshotId }
        : undefined
      this.sendFind()
    } catch (error) {
      if (batch) this.failedReplacementBatch = batch
      this.sendFind()
      throw error
    }
  }
  insertImages(images: { src: string; alt: string }[], x?: number | null, y?: number | null) {
    return this.engine.insertImages(
      images.map((image) => ({ reference: image.src, alt: image.alt })),
      x == null || y == null ? undefined : { clientX: x, clientY: y },
    )
  }
  async printable(expected = this.generation) {
    const result = await this.engine.printableSnapshot(expected)
    return { ...result, assets: undefined, assetCount: result.assets.length }
  }
  destroy() {
    this.replacement++
    this.setFinding(false)
    window.removeEventListener('scroll', this.scrolled, true)
    window.removeEventListener('resize', this.scrolled)
    this.layoutRoot?.removeEventListener('load', this.scrolled, true)
    this.layoutRoot?.removeEventListener('loadedmetadata', this.scrolled, true)
    document.fonts?.removeEventListener('loadingdone', this.scrolled)
    this.layoutObserver?.disconnect()
    return this.engine.destroy()
  }
}
