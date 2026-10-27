import {
  InkKitEditor,
  InkKitError,
  type CaretState as InkCaret,
  type EditorLabels,
  type FileReference,
  type FormatCommand as InkFormat,
  type ShortcutName,
  type WikiLinkReference,
  type TableCommand,
  type ReadableTextSnapshot,
} from '@aicayzer/inkkit'
import {
  askMissing,
  pickNote,
  postToHost,
  suggestNotes,
  type EmbeddedFile,
  type EmbedRequest,
  type UnavailableFile,
  type LinkRef,
} from './bridge'
import type { HeaderLabels } from './header'
import { NoteLinkStatus } from './links'
import { WebPictures, webAddress, type PictureWords } from './pictures'

/** A preview that could not be drawn is a diagnostic for the log, not an error in the person's edit. */
export function isPreviewDiagnostic(error: Error): boolean {
  return (
    error instanceof InkKitError &&
    (error.code === 'diagram-unavailable' || error.code === 'file-unavailable')
  )
}

/** The words the app hands the page. Inkkit rejects a label it does not know, so only Inkkit's own go to it;
 *  the header's and the Link to Note command's are MAPP's. */
export interface AppWords extends PictureWords {
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
  'parentRejected',
  'linkedFrom',
  'contents',
  'showLess',
  'timeline',
  'properties',
]
export function splitLabels(all: AppLabels): {
  editor: Partial<EditorLabels>
  header: Partial<HeaderLabels>
  words: AppWords
} {
  const {
    linkToNote,
    loadPicture,
    loadingPicture,
    picturesOff,
    loadOnePicture,
    loadPictures,
    ...rest
  } = all
  const header: Partial<HeaderLabels> = {}
  for (const key of headerLabelKeys) {
    if (key in rest) header[key] = rest[key]
    delete rest[key]
  }
  return {
    editor: rest,
    header,
    words: { linkToNote, loadPicture, loadingPicture, picturesOff, loadOnePicture, loadPictures },
  }
}

/**
 * Where a caret typed after `prefix`, in the Markdown source, falls in `readable`, the text the page reads out: the
 * offset just past the last of the prefix's characters found in order. Markup and spacing the readable text drops
 * are passed over, and so is a link's source the page does not show.
 */
export function caretOffset(prefix: string, readable: string): number {
  let at = 0
  for (const character of shownText(prefix)) {
    if (/\s/.test(character)) continue
    const found = readable.indexOf(character, at)
    // A character the page does not show, such as `#` or `*`, would otherwise send the caret on to a later match.
    if (found < 0 || (/[#*_`>~\-[\]()!|=]/.test(character) && found > at + 1)) continue
    at = found + character.length
  }
  return at
}

/**
 * The Markdown source with each link reduced to what Inkkit shows of it: an embed's name without its width, a wiki
 * link's alias where it has one, and a link's or image's text without its target or width. A link still being typed
 * when the caret was placed counts as ended there.
 */
function shownText(source: string): string {
  return source
    .replace(/!\[\[([^\]|]*)(?:\|[^\]]*)?(?:\]\]|$)/g, '$1')
    .replace(/\[\[(?:[^\]|]*\|)?([^\]]*)(?:\]\]|$)/g, '$1')
    .replace(/!?\[([^\]]*?)(?:\|\d+)?\](?:\([^)]*(?:\)|$)|\[[^\]]*(?:\]|$))/g, '$1')
}

export function guardedCommand<T>(action: () => T): T | { commandError: string; message: string } {
  try {
    return action()
  } catch (error) {
    if (error instanceof InkKitError) {
      // Inkkit tells only the caller of a refused edit, so the app is told here, where it tells the person.
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
  /** How many pictures at web addresses wait for the person to load them, and the words for the button that loads
   *  them together. */
  picturesWaiting?(count: number, label: string): void
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
/** An embed as the note's text holds it, which is how Marfa lists the embeds it bound. */
function request(reference: FileReference, item: string): EmbedRequest {
  return { item, text: reference.raw }
}

/** The names of notes to offer after `[[`, unless the person has typed past the request. */
export function wikiSuggest(
  query: string,
  context: { documentId: string; signal: AbortSignal },
): Promise<string[]> {
  return context.signal.aborted ? Promise.resolve([]) : suggestNotes(query, context.documentId)
}

/** A link as the app tells links apart: the alias is what the link shows beyond its name and heading. */
function linkRef(reference: WikiLinkReference): LinkRef {
  const shown = reference.fragment ? `${reference.target}#${reference.fragment}` : reference.target
  return {
    target: reference.target,
    ...(reference.fragment ? { heading: reference.fragment } : {}),
    ...(reference.label !== shown ? { alias: reference.label } : {}),
  }
}

/** The heading text as a link names it: compared ignoring case and the spacing around and inside it. */
function headingKey(text: string): string {
  return text.trim().replace(/\s+/g, ' ').toLowerCase()
}

/** The app bridge uses only Inkkit's public facade; native libraries retain file and save policy. */
export class NoteEditor {
  private engine!: InkKitEditor
  private finding = false
  private findPending = 0
  private layoutObserver?: ResizeObserver
  private generation = 0
  private item = ''
  private links!: NoteLinkStatus
  private pictures!: WebPictures
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
    host.links = new NoteLinkStatus(askMissing, (targets) => host.drawLinksAgain(targets))
    host.pictures = new WebPictures(
      words,
      (addresses) => host.drawLinksAgain(addresses),
      (count, label) => events.picturesWaiting?.(count, label),
    )
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
            const picture = webAddress(reference.target)
            if (picture) return host.pictures.present(picture, reference.label, context)
            const embed = request(reference, context.documentId)
            host.noteTarget(embed.text, reference.target)
            const file = await host.answer(embed)
            if (!file || context.signal.aborted)
              return { kind: 'missing', label: reference.label ?? reference.reference }
            if ('unavailable' in file)
              return {
                kind: 'error',
                label: reference.label ?? reference.reference,
                message: file.unavailable,
              }
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
            const picture = webAddress(reference.target)
            if (picture) return host.pictures.bytes(context.documentId, picture)
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
            const address = webAddress(reference.target)
            if (address) {
              if (host.pictures.opensInBrowser(address)) return events.openLink(address)
              void host.pictures.choose(address)
              return
            }
            postToHost({ type: 'openEmbed', embed: request(reference, context.documentId) })
          },
          contextMenu(reference, _point, context) {
            if (webAddress(reference.target)) return
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
          suggest: wikiSuggest,
          // The app tells which names no note answers to, and Inkkit draws those links as missing.
          resolve: (reference, context) =>
            host.links.status(linkRef(reference), context.documentId),
          // A link to this note's own heading is the page's to follow. Any other names a note, which only the
          // app can find, so the app opens it and scrolls to the heading once it is shown.
          open(reference, context) {
            if (!reference.target) {
              if (reference.fragment) host.revealHeading(reference.fragment)
              return
            }
            postToHost({ type: 'openNote', item: context.documentId, ...linkRef(reference) })
          },
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
    if (id !== this.item) {
      this.answers.clear()
      this.targets.clear()
    }
    this.item = id
    this.pictures.setItem(id)
  }
  /** The app's Remote Pictures setting changed: pictures that waited, or were turned off, are asked about again. With
   *  `afresh`, a file saved from a web address came to the note's item or went from it: every picture is asked about again. */
  picturesChanged(addresses?: string[], afresh?: boolean) {
    this.pictures.changed(addresses, afresh)
  }
  /** The person chose to load every picture that waits. */
  loadPictures() {
    this.pictures.chooseAll()
  }
  /** What the app answered for each embed of the note, by its text, so two embeds of one file, and one drawn
   *  again, ask it once. Only a file is kept: an embed the app could not show is asked again. */
  private answers = new Map<
    string,
    { text: string; answer: Promise<EmbeddedFile | UnavailableFile | null> }
  >()
  /** The file each embed text names, as Inkkit finds it, to draw just the embeds the app says changed. */
  private targets = new Map<string, Set<string>>()
  noteTarget(text: string, target: string) {
    const held = this.targets.get(text)
    if (held) held.add(target)
    else this.targets.set(text, new Set([target]))
  }
  answer(embed: EmbedRequest): Promise<EmbeddedFile | UnavailableFile | null> {
    const key = JSON.stringify(embed)
    const held = this.answers.get(key)
    if (held) return held.answer
    const answer = Promise.resolve(
      window.webkit?.messageHandlers?.embeds?.postMessage(embed) ?? null,
    )
    this.answers.set(key, { text: embed.text, answer })
    const forget = () => {
      if (this.answers.get(key)?.answer === answer) this.answers.delete(key)
    }
    answer.then((file) => (file && !('unavailable' in file) ? undefined : forget()), forget)
    return answer
  }
  /** The app's library changed what these embeds show: they are asked and drawn again. */
  embedsChanged(texts: string[]) {
    const changed = new Set(texts)
    for (const [key, held] of this.answers) if (changed.has(held.text)) this.answers.delete(key)
    const targets = new Set<string>()
    for (const text of changed)
      for (const target of this.targets.get(text) ?? []) targets.add(target)
    if (!targets.size) return
    try {
      this.engine.refreshReferences([...targets])
    } catch (error) {
      if (!(error instanceof InkKitError)) throw error
    }
  }
  /** The app's library changed: which notes the links name is asked again. */
  linksChanged() {
    this.links.refresh()
  }
  /** Draws the links to these notes again, after the app's answer for them changed. A page with no document yet,
   *  or one that has ended, draws nothing, and each link it draws later is drawn from the answers held. */
  private drawLinksAgain(targets: string[]) {
    try {
      this.engine.refreshReferences(targets)
    } catch (error) {
      if (!(error instanceof InkKitError)) throw error
    }
  }
  /** Moves to the heading of the note on the page that has this text. Whether there was one. */
  revealHeading(text: string, expected = this.generation): boolean {
    const wanted = headingKey(text)
    const heading = this.engine
      .headings(expected)
      .find((entry) => headingKey(entry.text) === wanted)
    return heading ? this.engine.navigateHeading(heading) : false
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
    // A later load or reload reported this generation's text before it replaced it.
    if (expected < this.generation) return null
    const text = this.snapshot(expected).text
    if (this.pendingChanged?.generation === expected) this.pendingChanged = undefined
    if (text === this.reported) return null
    this.reported = text
    return text
  }
  focus() {
    this.engine.focus()
  }
  /** Gives the text the keyboard with the caret after `prefix`, the source typed before it in quick add, or at the
   *  end of the text when `prefix` is null. */
  focusText(prefix: string | null) {
    const snapshot = this.engine.textSnapshot(this.generation)
    const end = snapshot.text.replace(/\n+$/, '').length
    const at = prefix === null ? end : Math.min(caretOffset(prefix, snapshot.text), end)
    this.engine.selectTextRange(this.range(at, at, snapshot), { focus: true, reveal: true })
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
  /** Puts images after everything in the text, as files quick add attached to a new note, leaving the selection
   *  and the keyboard where they were so typing goes on where the person is. False in source editing, where the page
   *  leaves them for the app to send again. A note that ends in a code fence left open refuses them (`preservation`),
   *  and the app tells the person the files are attached but not in the text.
   *
   *  Inkkit replaces the whole document when it holds one block with nothing in it, which is how it reads a note
   *  that is only a rule, an empty code fence, an image or a link definition. So the text is checked after the edit:
   *  anything but trailing whitespace gone is taken back in the same step, before the change is reported, and
   *  refused as `preservation`. This guard stays whatever Inkkit does about it. */
  appendImages(images: { src: string; alt: string }[], expected = this.generation) {
    const before = this.snapshot(expected).text
    const reportedBefore = this.pendingChanged
    const appended = this.engine.appendImages(
      images.map((image) => ({ reference: image.src, alt: image.alt })),
      expected,
    )
    if (!appended) return false
    if (this.snapshot(expected).text.startsWith(before.trimEnd())) return true
    this.engine.undo(expected)
    if (this.snapshot(expected).text !== before)
      throw new InkKitError(
        'preservation',
        'The note could not be restored after adding the files.',
      )
    // Inkkit reported the lossy text and then the restored one, in this same turn. The app is told neither.
    this.pendingChanged = reportedBefore
    throw new InkKitError(
      'preservation',
      'The files could not be added to the text without changing it.',
    )
  }
  async printable(expected = this.generation) {
    // A printed note shows the pictures at web addresses already on this Mac, and fetches none.
    this.pictures.cacheOnly = true
    try {
      const result = await this.engine.printableSnapshot(expected)
      return { ...result, assets: undefined, assetCount: result.assets.length }
    } finally {
      this.pictures.cacheOnly = false
      this.pictures.afterCacheOnly()
    }
  }
  destroy() {
    this.links.end()
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
