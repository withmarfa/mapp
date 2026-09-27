import { commandsCtx, editorViewCtx } from '@milkdown/kit/core'
import type { Ctx } from '@milkdown/kit/ctx'
import { wrapInBulletListCommand } from '@milkdown/kit/preset/commonmark'
import type { Node as ProseNode } from '@milkdown/kit/prose/model'
import { Plugin, PluginKey } from '@milkdown/kit/prose/state'
import type { EditorView } from '@milkdown/kit/prose/view'
import { $prose } from '@milkdown/kit/utils'

// A click on the task marker lands on the <li> itself, since the marker is a
// pseudo-element; clicks inside the item's text land on its children.
export const taskListPlugin = $prose(
  () =>
    new Plugin({
      key: new PluginKey('taskToggle'),
      props: {
        handleClickOn(view, _pos, node, nodePos, event) {
          if (node.type.name !== 'list_item' || node.attrs.checked == null) return false
          const target = event.target as HTMLElement
          if (!target.matches('li[data-item-type="task"]')) return false
          view.dispatch(
            view.state.tr.setNodeMarkup(nodePos, undefined, {
              ...node.attrs,
              checked: !node.attrs.checked,
            }),
          )
          return true
        },
      },
    }),
)

/** The items whose own text the selection reaches: for each line selected, the nearest item holding it, so an
 *  item nested in another changes without the one around it. */
function listItemsInSelection(view: EditorView): Array<{ pos: number; node: ProseNode }> {
  const { doc, selection } = view.state
  const items = new Map<number, ProseNode>()
  doc.nodesBetween(selection.from, selection.to, (node, pos) => {
    if (!node.isTextblock) return true
    const inside = doc.resolve(pos + 1)
    for (let depth = inside.depth; depth > 0; depth--) {
      if (inside.node(depth).type.name === 'list_item') {
        items.set(inside.before(depth), inside.node(depth))
        break
      }
    }
    return false
  })
  return [...items].map(([pos, node]) => ({ pos, node }))
}

export function toggleTaskList(ctx: Ctx): void {
  const view = ctx.get(editorViewCtx)
  let items = listItemsInSelection(view)
  if (items.length === 0) {
    ctx.get(commandsCtx).call(wrapInBulletListCommand.key)
    items = listItemsInSelection(view)
  }
  const allTasks = items.every(({ node }) => node.attrs.checked != null)
  let tr = view.state.tr
  for (const { pos, node } of items) {
    tr = tr.setNodeMarkup(pos, undefined, {
      ...node.attrs,
      checked: allTasks ? null : (node.attrs.checked ?? false),
    })
  }
  view.dispatch(tr)
}
