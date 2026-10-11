import {
  InkKitEditor,
  InkKitError,
  type CaretState as InkCaret,
  type EditorLabels,
  type FileReference,
  type FormatCommand as InkFormat,
  type TableCommand,
  type ReadableTextSnapshot,
} from '@aicayzer/inkkit'
import { postToHost, type EmbeddedFile, type EmbedRequest } from './bridge'

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
    ? {
        item,
        name: reference.fragment
          ? reference.reference.slice(0, -reference.fragment.length - 1)
          : reference.reference,
      }
    : { item, path: reference.reference }
}

function isNoteReference(reference: FileReference): boolean {
  const target = reference.reference.split('#')[0]!.split('?')[0]!
  const name = target.split('/').pop() ?? target
  return /\.(md|markdown|txt)$/i.test(name) || (reference.kind === 'wiki' && !name.includes('.'))
}

/** The app bridge uses only InkKit's public facade; native libraries retain file and save policy. */
export class NoteEditor {
  private engine!: InkKitEditor
  private finding = false
  private findPending = 0
  private generation = 0
  private item = ''
  private reported = ''
  private original = ''
  private constructor(private events: EditorEvents) {}
  static async mount(
    root: HTMLElement,
    events: EditorEvents,
    labels: Partial<EditorLabels> & { noteReference?: string } = {},
  ): Promise<NoteEditor> {
    const host = new NoteEditor(events)
    const described = new Map<string, EmbeddedFile>()
    host.engine = await InkKitEditor.mount(
      root,
      {
        changed(text, generation) {
          host.reported = text
          events.changed(text, generation)
          host.findChanged()
        },
        stateChanged() {},
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
          host.findChanged()
        },
        openLink: events.openLink,
        copy: events.copy,
        error(error) {
          postToHost({ type: 'error', message: error.message })
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
                  labels.noteReference?.replace('%@', reference.label ?? reference.reference) ??
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
              url:
                file.url +
                ((reference.fragment ?? reference.reference.split('#')[1])
                  ? '#' + (reference.fragment ?? reference.reference.split('#')[1])
                  : ''),
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
        images: {
          presentation() {
            return undefined
          },
          async importImage() {
            throw new InkKitError(
              'image-unavailable',
              'Use the native attachment command to add an image.',
            )
          },
          async exportImage() {
            throw new InkKitError('image-unavailable', 'The embedded image could not be read.')
          },
        },
      },
    )
    host.engine.setViewport({ scrollContainer: document.documentElement })
    window.addEventListener('scroll', () => host.findChanged(), { passive: true })
    return host
  }
  setItem(id: string) {
    this.item = id
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
        this.findChanged()
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
  snapshot(expected = this.generation) {
    return this.engine.snapshot(expected)
  }
  markdown(): string | null {
    const snapshot = this.snapshot()
    return snapshot.text === this.original ? null : snapshot.text
  }
  flush(expected = this.generation): string | null {
    const text = this.snapshot(expected).text
    if (text === this.reported) return null
    this.reported = text
    return text
  }
  focus() {
    this.engine.focus()
  }
  setEditingMode(mode: 'source' | 'formatted', expected = this.generation) {
    this.engine.setEditingMode(mode, expected)
    this.findChanged()
  }
  undo(expected = this.generation) {
    this.engine.undo(expected)
  }
  redo(expected = this.generation) {
    this.engine.redo(expected)
  }
  format(command: FormatCommand, arg?: string | number, expected = this.generation) {
    this.engine.commandState(expected)
    const table =
      command === 'alignColumn'
        ? ({ left: 'alignLeft', center: 'alignCenter', right: 'alignRight' } as const)[
            arg as 'left' | 'center' | 'right'
          ]
        : tables[command]
    if (table) return this.engine.table(table)
    return this.engine.format(command as InkFormat, arg)
  }
  setKeymap(bindings: Keymap) {
    const keys: Record<string, string[]> = {}
    for (const [key, [command, arg]] of Object.entries(bindings)) {
      const name = tables[command]
        ? 'table' + tables[command]![0]!.toUpperCase() + tables[command]!.slice(1)
        : command === 'heading'
          ? 'heading' + arg
          : command
      ;(keys[name] ??= []).push(key)
    }
    this.engine.setKeymap(keys)
  }
  setSpellcheck(spellcheck: boolean) {
    this.engine.setTextInputPreferences({ spellcheck })
  }
  setFinding(finding: boolean) {
    this.finding = finding
    if (finding) this.sendFind()
  }
  private findChanged() {
    if (!this.finding) return
    cancelAnimationFrame(this.findPending)
    this.findPending = requestAnimationFrame(() => this.sendFind())
  }
  private range(from: number, to: number, snapshot: ReadableTextSnapshot) {
    return { snapshotId: snapshot.snapshotId, from, to }
  }
  private sendFind() {
    try {
      const snapshot = this.engine.textSnapshot(this.generation)
      const visible = this.engine.visibleTextRanges(snapshot.snapshotId)
      const from = visible[0]?.from ?? 0,
        to = visible.at(-1)?.to ?? 0
      const boxes: number[] = []
      for (let at = from; at < to; at++) {
        let rect
        try {
          rect = this.engine.textRangeRects(this.range(at, at + 1, snapshot))[0]
        } catch {}
        boxes.push(
          rect?.left ?? 0,
          (rect?.top ?? 0) + window.scrollY,
          rect?.width ?? 0,
          rect?.height ?? 0,
        )
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
  private replacementBatch?: { id: string; snapshotId: string }
  findReplace(
    from: number,
    to: number,
    text: string,
    generation = this.generation,
    snapshotId?: string,
    batch?: string,
  ) {
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
  }
  insertImages(images: { src: string; alt: string }[], x?: number, y?: number) {
    return this.engine.insertImages(
      images.map((image) => ({ path: image.src, alt: image.alt })),
      x,
      y,
    )
  }
  async printable(expected = this.generation) {
    const result = await this.engine.printableSnapshot(expected)
    return { ...result, assets: undefined, assetCount: result.assets.length }
  }
  destroy() {
    this.replacement++
    cancelAnimationFrame(this.findPending)
    return this.engine.destroy()
  }
}
