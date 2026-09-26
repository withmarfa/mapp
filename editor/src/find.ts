import type { Node as ProseNode } from '@milkdown/kit/prose/model'
import { TextSelection } from '@milkdown/kit/prose/state'
import type { EditorView } from '@milkdown/kit/prose/view'

/** A run of the note's plain text that stands for a stretch of the document: `length` characters from text
 *  offset `offset`, which are the document's positions from `pos`. Offsets are UTF-16, as the app's are. */
interface Run {
  offset: number
  pos: number
  length: number
}

/** The note as plain text, as the system find bar searches it: each block's text, blocks separated by a line
 *  break, and a line break for a hard break or an image. */
export interface TextModel {
  text: string
  runs: Run[]
}

export function textModel(doc: ProseNode): TextModel {
  let text = ''
  const runs: Run[] = []
  let pendingBreak = false
  doc.descendants((node, pos) => {
    if (node.isBlock) {
      if (node.isTextblock && text.length > 0) pendingBreak = true
      return true
    }
    if (pendingBreak) {
      text += '\n'
      pendingBreak = false
    }
    const piece = node.isText ? node.text! : node.type.name === 'image' ? '￼' : '\n'
    runs.push({ offset: text.length, pos, length: piece.length })
    text += piece
    return false
  })
  return { text, runs }
}

/** The document position of a text offset; an offset between blocks is the end of the block before it. */
export function positionAt(model: TextModel, offset: number): number {
  let low = 0
  let high = model.runs.length - 1
  let found: Run | undefined
  while (low <= high) {
    const middle = (low + high) >> 1
    const run = model.runs[middle]!
    if (run.offset <= offset) {
      found = run
      low = middle + 1
    } else {
      high = middle - 1
    }
  }
  if (!found) return model.runs[0]?.pos ?? 0
  return found.pos + Math.min(offset - found.offset, found.length)
}

/** The text offset of a document position; a position outside any text is the offset of the text after it. */
export function offsetAt(model: TextModel, pos: number): number {
  for (const run of model.runs) {
    if (pos <= run.pos) return run.offset
    if (pos <= run.pos + run.length) return run.offset + (pos - run.pos)
  }
  return model.text.length
}

/** The text visible in the window, as offsets. */
export function visibleRange(view: EditorView, model: TextModel): [number, number] {
  const box = view.dom.getBoundingClientRect()
  const left = box.left + 1
  const top = view.posAtCoords({ left, top: Math.max(box.top, 0) + 1 })
  const bottom = view.posAtCoords({ left: box.right - 1, top: window.innerHeight - 1 })
  const from = top ? offsetAt(model, top.pos) : 0
  const to = bottom ? offsetAt(model, bottom.pos) : model.text.length
  // A line of margin each way, so a match half in view is still drawn.
  return [Math.max(0, from - 200), Math.min(model.text.length, to + 200)]
}

/** Each character's box in the range, as four numbers in page coordinates (the scroll added), so the app can
 *  draw any match within the range without asking again. A line break's box is empty. */
export function characterBoxes(view: EditorView, model: TextModel, from: number, to: number): number[] {
  const boxes: number[] = []
  const range = document.createRange()
  const scrollX = window.scrollX
  const scrollY = window.scrollY
  let offset = from
  for (const run of model.runs) {
    if (run.offset + run.length <= from) continue
    if (run.offset >= to) break
    for (; offset < run.offset; offset++) boxes.push(0, 0, 0, 0)
    const end = Math.min(run.offset + run.length, to)
    for (; offset < end; offset++) {
      const at = view.domAtPos(run.pos + (offset - run.offset))
      const next = view.domAtPos(run.pos + (offset - run.offset) + 1)
      if (at.node.nodeType !== Node.TEXT_NODE || next.node !== at.node) {
        const rect = view.coordsAtPos(run.pos + (offset - run.offset), 1)
        boxes.push(rect.left + scrollX, rect.top + scrollY, 0, rect.bottom - rect.top)
        continue
      }
      range.setStart(at.node, at.offset)
      range.setEnd(at.node, at.offset + 1)
      const rects = range.getClientRects()
      const rect = rects[rects.length - 1] ?? range.getBoundingClientRect()
      boxes.push(rect.left + scrollX, rect.top + scrollY, rect.width, rect.height)
    }
  }
  for (; offset < to; offset++) boxes.push(0, 0, 0, 0)
  return boxes
}

export function selectText(view: EditorView, model: TextModel, from: number, to: number): void {
  const selection = TextSelection.create(view.state.doc, positionAt(model, from), positionAt(model, to))
  view.dispatch(view.state.tr.setSelection(selection))
}

/** Scrolls the range into the middle of the window when it is out of view, as a text view does for a match. */
export function scrollToText(view: EditorView, model: TextModel, from: number): void {
  const rect = view.coordsAtPos(positionAt(model, from))
  if (rect.top >= 60 && rect.bottom <= window.innerHeight - 20) return
  window.scrollTo({ top: window.scrollY + rect.top - window.innerHeight / 2 })
}
