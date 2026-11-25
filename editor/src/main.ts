import { openLink, postToHost } from './bridge'
import {
  ItemEditor,
  guardedCommand,
  splitLabels,
  type AppLabels,
  type FormatCommand,
  type Keymap,
} from './editor'
import { ItemHeader, type HeaderIcons, type HeaderModel } from './header'
import { LinkStyle } from './link-style'
import { PageNoticeLine, type NoticeModel } from './notice'
import {
  InkKitError,
  normalizeLinkAddress,
  type DisplayPreferences,
  type TextInputPreferences,
} from '@aicayzer/inkkit'
import '@aicayzer/inkkit/style.css'
import './style.css'

declare global {
  interface Window {
    editor: {
      load(markdown: string, generation: number, editable: boolean): void
      reload(markdown: string, generation: number, editable: boolean): void
      markdown(): string | null
      flush(expected?: number): string | null | { commandError: string; message: string }
      format(command: FormatCommand, arg?: string | number, expected?: number): void
      unlinkSelected(text: string, expected?: number): boolean
      focus(): void
      focusTitle(item: string): void
      focusText(prefix: string | null): void
      blurText(expected: number): void
      setHostActive(active: boolean): void
      normalizeLinkAddress(input: string): string | null
      setEditingMode(mode: 'source' | 'formatted', expected?: number): void
      undo(expected?: number): void
      redo(expected?: number): void
      setItem(id: string): void
      linksChanged(): void
      embedsChanged(texts: string[]): void
      picturesChanged(): void
      savedPicturesChanged(addresses: string[]): void
      revealHeading(text: string, expected?: number): boolean
      revealHeadingAt(ordinal: number, expected?: number): boolean
      setFinding(finding: boolean): void
      findSelect(from: number, to: number, generation?: number, snapshotId?: string): void
      findScroll(from: number, generation?: number, snapshotId?: string): void
      findReplace(
        from: number,
        to: number,
        text: string,
        generation?: number,
        snapshotId?: string,
        batch?: string,
      ): void
      insertImages(
        images: { src: string; alt: string }[],
        x?: number,
        y?: number,
        height?: number,
      ): void
      appendImages(images: { src: string; alt: string }[], expected: number): unknown
      setKeymap(keymap: Keymap): void
      readableSnapshot(expected?: number): unknown
      snapshot(expected?: number): unknown
      printable(expected?: number): Promise<unknown>
      setFullWidth(full: boolean): void
      setTextSize(points: number): void
      setReadingWidth(ems: number): void
      setHeader(model: HeaderModel | null): void
      setHeaderIcons(icons: HeaderIcons): void
      setNotices(models: NoticeModel[]): void
      setLinkStyle(variables: Record<string, string>): void
      setOptions(options: { textInput: TextInputPreferences; display: DisplayPreferences }): void
      setLineSpacing(multiple: number): void
      setParagraphSpacing(multiple: number): void
    }
  }
}

const root = document.getElementById('editor')
const headerRoot = document.getElementById('item-header')
const footerRoot = document.getElementById('item-footer')
const noticeRoot = document.getElementById('page-notice')
const reasonRoot = document.getElementById('page-reason')
if (!root || !headerRoot || !footerRoot || !noticeRoot || !reasonRoot)
  throw new Error('editor root missing')
const labels = splitLabels((window as unknown as { marfaLabels?: AppLabels }).marfaLabels ?? {})

const editor = await ItemEditor.mount(
  root,
  {
    find(state) {
      postToHost({ type: 'find', ...state })
    },
    changed(markdown, generation) {
      postToHost({ type: 'changed', markdown, generation })
    },
    stateChanged(state) {
      postToHost({ type: 'state', ...state })
    },
    openLink,
    copy(text) {
      postToHost({ type: 'copy', text })
    },
    painted(generation) {
      postToHost({ type: 'painted', generation })
    },
    headings(headings, generation) {
      postToHost({ type: 'headings', headings, generation })
    },
    // The page counts the pictures that wait and says so in its notice, which the app's own notice replaces.
    picturesWaiting(count, sentence, button, shown) {
      notice.setPictures(
        shown && count > 0
          ? {
              kind: 'picturesWaiting',
              symbol: 'photo',
              words: sentence,
              action: button,
              closable: true,
            }
          : null,
      )
    },
  },
  labels.editor,
  labels.words,
)
const header = new ItemHeader(headerRoot, footerRoot, labels.header)
const notice = new PageNoticeLine(
  noticeRoot,
  reasonRoot,
  {
    // Loading pictures is the page's own: it asks the app for each, as its own Load buttons do.
    // Any other action is for the item the app made the notice for, so it needs no item on the page.
    action: (kind, item) => {
      if (kind === 'picturesWaiting') editor.loadPictures()
      else if (item) postToHost({ type: 'noticeAction', item, kind })
    },
    // Closing hides the notice for this page: it loads nothing and changes no setting.
    close: () => editor.dismissPictures(),
  },
  () => labels.words.closePictures ?? 'Close',
)

// Escape hands the keyboard back to the list. Heard on the window, since a read-only page's editor hears
// no keys of its own.
window.addEventListener('keydown', (event) => {
  if (event.key !== 'Escape' || event.metaKey || event.ctrlKey || event.altKey || event.shiftKey)
    return
  event.preventDefault()
  postToHost({ type: 'escape' })
})

// An image pasted on its own, a screenshot or an image file copied in the Finder, becomes a file of the items
// folder, which the app takes from the pasteboard itself; a copied web page, images and all, is the page's.
window.addEventListener(
  'paste',
  (event) => {
    const data = event.clipboardData
    if (!data || data.types.includes('text/html') || headerRoot.contains(event.target as Node))
      return
    const files = [...data.items].filter((item) => item.kind === 'file')
    if (files.length === 0 || !files.every((item) => item.type.startsWith('image/'))) return
    // Text beside the image is kept for the page, unless it only names a file copied in the Finder.
    if (data.types.includes('text/plain') && !data.types.includes('text/uri-list')) return
    event.preventDefault()
    event.stopPropagation()
    postToHost({ type: 'pasteImages' })
  },
  { capture: true },
)

// A right-click on a row of the head opens the row's menu, as a click on its name does. Elsewhere WebKit opens its own
// menu, which the app adds to: it hears which embed and which row of the footer the pointer is over just before. Heard
// first on the window, so a menu over neither clears what the last one named.
window.addEventListener(
  'contextmenu',
  (event) => {
    postToHost({ type: 'embedMenu', embed: null, opens: false })
    if (header.openRowMenuAt(event.target)) {
      event.preventDefault()
      event.stopPropagation()
      postToHost({ type: 'rowMenu', row: null })
      return
    }
    postToHost({ type: 'rowMenu', row: header.rowAt(event.target) })
  },
  { capture: true },
)

let generation = 0
// The toolbar shows the title once the head has gone under it; the app hears only when that changes. A page in Focus
// has its title there from the start; one whose head is not yet sent, or not yet laid out, has not scrolled it away.
let headerScrolledAway = false
function checkHeaderScrolledAway(): void {
  const away = header.isAway(window.scrollY)
  if (away === headerScrolledAway) return
  headerScrolledAway = away
  postToHost({ type: 'headerScrolledAway', away, generation: editor.loadedGeneration })
}
// The toolbar draws a glass band over the page only while some of it is under the toolbar, which is whenever the
// page has scrolled at all: the page starts below the toolbar, so at the top nothing is behind it. A rounded-up
// offset keeps a trackpad's sub-pixel settling from flickering the band, and the app hears only when it changes.
let contentUnderToolbar = false
function checkContentUnderToolbar(): void {
  const under = window.scrollY > 1
  if (under === contentUnderToolbar) return
  contentUnderToolbar = under
  postToHost({ type: 'contentUnderToolbar', under, generation: editor.loadedGeneration })
}
window.addEventListener(
  'scroll',
  () => {
    checkHeaderScrolledAway()
    checkContentUnderToolbar()
  },
  { passive: true },
)
window.addEventListener('resize', () => {
  checkHeaderScrolledAway()
  checkContentUnderToolbar()
})
// The item's text fills the rest of the window between the header and the footer, so a click anywhere below it
// places the caret and a short item does not scroll. The text's height changes in the next frame: changed while
// the browser reports sizes, it would be reported late, which WebKit raises as an error.
// A header that only grew wider moves nothing below it.
let surround = -1
const surroundObserver = new ResizeObserver(() => {
  const height =
    headerRoot.offsetHeight +
    noticeRoot.offsetHeight +
    reasonRoot.offsetHeight +
    footerRoot.offsetHeight
  // With linked items the text ends where it ends and they follow it; with none, the text fills the window.
  const follows = header.hasFooterItems
  const key = follows ? -2 - height : height
  if (key === surround) return
  surround = key
  requestAnimationFrame(() => {
    root.style.setProperty('--inkkit-min-height', follows ? '0px' : `calc(100vh - ${height}px)`)
    // The footer's own top padding already separates it, so the text's reserve for a floating footer is not needed.
    root.style.setProperty('--inkkit-padding-bottom', follows ? '1rem' : '')
    editor.invalidateFindGeometry()
    checkHeaderScrolledAway()
  })
})
surroundObserver.observe(headerRoot)
surroundObserver.observe(noticeRoot)
surroundObserver.observe(reasonRoot)
surroundObserver.observe(footerRoot)

const linkStyle = new LinkStyle(document.documentElement.style)

function setPageProperty(name: string, value: string): void {
  const style = document.documentElement.style
  if (style.getPropertyValue(name) === value) return
  style.setProperty(name, value)
  editor.invalidateFindGeometry()
}

function setBodyProperty(name: string, value: string): void {
  const style = document.body.style
  if (style.getPropertyValue(name) === value) return
  style.setProperty(name, value)
  editor.invalidateFindGeometry()
}

window.editor = {
  load: (markdown, nextGeneration, editable) => {
    generation = nextGeneration
    header.cancelTitleFocus()
    editor.load(markdown, nextGeneration, editable)
    headerScrolledAway = false
    checkHeaderScrolledAway()
    contentUnderToolbar = false
    checkContentUnderToolbar()
  },
  reload: (markdown, nextGeneration, editable) => {
    generation = nextGeneration
    editor.reload(markdown, nextGeneration, editable)
  },
  markdown: () => editor.markdown(),
  flush: (expected) => guardedCommand(() => editor.flush(expected)),
  format: (command, arg, expected) =>
    guardedCommand(() => editor.format(command, arg ?? undefined, expected), { retry: true }),
  unlinkSelected: (text, expected) =>
    guardedCommand(() => editor.unlinkSelected(text, expected), { retry: true }) === true,
  focus: () => {
    header.cancelTitleFocus()
    editor.focus()
  },
  focusTitle: (item) => header.focusTitle(item),
  setHostActive: (active) => editor.setHostActive(active),
  normalizeLinkAddress: (input) => normalizeLinkAddress(input) ?? null,
  focusText: (prefix) => {
    header.cancelTitleFocus()
    guardedCommand(() => editor.focusText(prefix))
  },
  blurText: (expected: number) => {
    if (expected !== generation) return
    guardedCommand(() => editor.blur(expected))
    const active = document.activeElement
    if (active instanceof HTMLElement && active.matches('.item-title')) active.blur()
  },
  setEditingMode: (mode, expected) => guardedCommand(() => editor.setEditingMode(mode, expected)),
  undo: (expected) => guardedCommand(() => editor.undo(expected)),
  redo: (expected) => guardedCommand(() => editor.redo(expected)),
  setItem: (id) => editor.setItem(id),
  linksChanged: () => editor.linksChanged(),
  embedsChanged: (texts) => editor.embedsChanged(texts),
  picturesChanged: () => editor.picturesChanged(),
  savedPicturesChanged: (addresses) => editor.savedPicturesChanged(addresses),
  revealHeading: (text, expected) => {
    const result = guardedCommand(() => editor.revealHeading(text, expected))
    return result === true
  },
  revealHeadingAt: (ordinal, expected) => {
    const result = guardedCommand(() => editor.revealHeadingAt(ordinal, expected))
    return result === true
  },
  setFinding: (finding) => editor.setFinding(finding),
  findSelect: (from, to, generation, snapshotId) =>
    guardedCommand(() => editor.findSelect(from, to, generation, snapshotId)),
  findScroll: (from, generation, snapshotId) =>
    guardedCommand(() => editor.findScroll(from, generation, snapshotId)),
  findReplace: (from, to, text, generation, snapshotId, batch) =>
    guardedCommand(() => editor.findReplace(from, to, text, generation, snapshotId, batch)),
  // The app gives a drop's place in the web view; the page's window starts below whatever covers its top.
  insertImages: (images, x, y, height) =>
    guardedCommand(() =>
      editor.insertImages(
        images,
        x,
        y == null ? y : y - Math.max(0, (height ?? window.innerHeight) - window.innerHeight),
      ),
    ),
  appendImages: (images, expected) => guardedCommand(() => editor.appendImages(images, expected)),
  setKeymap: (keymap) => editor.setKeymap(keymap),
  readableSnapshot: (expected) => editor.readableSnapshot(expected),
  snapshot: (expected) => editor.snapshot(expected),
  printable: async (expected) => {
    try {
      return await editor.printable(expected)
    } catch (error) {
      if (error instanceof InkKitError) return { snapshotError: error.code, message: error.message }
      throw error
    }
  },
  setFullWidth: (full) => {
    if (document.documentElement.classList.contains('full-width') === full) return
    document.documentElement.classList.toggle('full-width', full)
    editor.invalidateFindGeometry()
  },
  // Text measures use rem, so the reading width scales with its text.
  setTextSize: (points) => setPageProperty('font-size', `${points}px`),
  setOptions: (options) => editor.setOptions(options),
  // Both are set on the body, where the page's own stylesheet sets the same Inkkit properties.
  setLineSpacing: (multiple) => setBodyProperty('--inkkit-line-height', String(multiple)),
  setParagraphSpacing: (multiple) =>
    setBodyProperty('--inkkit-paragraph-spacing', `calc(var(--inkkit-font-size) * ${multiple})`),
  setReadingWidth: (ems) => setPageProperty('--reading-width', `${ems}rem`),
  // Padding and corners move the text, so the find marks are measured again.
  setLinkStyle: (variables) => {
    if (linkStyle.set(variables)) editor.invalidateFindGeometry()
  },
  setHeader: (model) => {
    header.set(model)
    editor.setTitle(model?.title ?? '')
    if (model)
      document.documentElement.style.setProperty(
        '--interface-text-size',
        `${model.interfaceTextSize}px`,
      )
    checkHeaderScrolledAway()
  },
  setHeaderIcons: (icons) => {
    header.setIcons(icons)
    notice.setIcons(icons)
  },
  setNotices: (models) => notice.setApp(models),
}

postToHost({ type: 'ready' })
