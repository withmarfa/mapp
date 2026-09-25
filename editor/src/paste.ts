import { linkSchema } from '@milkdown/kit/preset/commonmark'
import { Plugin, PluginKey } from '@milkdown/kit/prose/state'
import { $prose } from '@milkdown/kit/utils'

const url = /^https?:\/\/\S+$/

/** A URL pasted over a selection links what is selected rather than replacing it. */
export const pastePlugin = $prose(
  (ctx) =>
    new Plugin({
      key: new PluginKey('paste'),
      props: {
        handlePaste: (view, event) => {
          const data = event.clipboardData
          if (!data) return false
          const text = data.getData('text/plain').trim()
          const { selection } = view.state
          if (selection.empty || !url.test(text)) return false
          const mark = linkSchema.type(ctx).create({ href: text, title: '' })
          view.dispatch(
            view.state.tr.addMark(selection.from, selection.to, mark).removeStoredMark(mark),
          )
          return true
        },
      },
    }),
)
