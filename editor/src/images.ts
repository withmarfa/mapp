import { imageSchema } from '@milkdown/kit/preset/commonmark'
import type { Node as ProseNode } from '@milkdown/kit/prose/model'
import type { NodeView } from '@milkdown/kit/prose/view'
import { $view } from '@milkdown/kit/utils'

/** The note has no attachments yet and the page fetches nothing, so an image shows what it was called, and the
 *  markdown keeps the image as written. */
class ImageView implements NodeView {
  dom: HTMLElement

  constructor(node: ProseNode) {
    this.dom = document.createElement('span')
    this.dom.className = 'image-absent'
    this.render(node)
  }

  update(node: ProseNode): boolean {
    if (node.type.name !== 'image') return false
    this.render(node)
    return true
  }

  ignoreMutation(): boolean {
    return true
  }

  private render(node: ProseNode): void {
    this.dom.textContent = String(node.attrs.alt || node.attrs.src || '')
  }
}

export const imageView = $view(imageSchema.node, () => (node) => new ImageView(node))
