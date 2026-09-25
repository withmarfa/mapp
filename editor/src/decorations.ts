import { Plugin, PluginKey, type EditorState } from '@milkdown/kit/prose/state'
import { Decoration, DecorationSet } from '@milkdown/kit/prose/view'
import { $prose } from '@milkdown/kit/utils'
import { labels } from './labels'

const copyIcon =
  '<svg width="14" height="14" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><rect x="5.5" y="5.5" width="8" height="8" rx="1.5"/><path d="M10.5 5.5v-2a1 1 0 0 0-1-1h-6a1 1 0 0 0-1 1v6a1 1 0 0 0 1 1h2"/></svg>'
const doneIcon =
  '<svg width="14" height="14" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M3.5 8.5l3 3 6-6.5"/></svg>'

// The button reads the block's text when clicked, so the same widget can stay
// mounted while the block is edited.
function copyButton(onCopy: (text: string) => void): HTMLElement {
  const button = document.createElement('button')
  button.type = 'button'
  button.className = 'copy'
  button.setAttribute('aria-label', labels.copy)
  button.innerHTML = copyIcon
  button.addEventListener('mousedown', (event) => event.preventDefault())
  button.addEventListener('click', () => {
    const code = button.closest('pre')?.querySelector('code')
    onCopy(code?.textContent ?? '')
    button.dataset.copied = ''
    button.innerHTML = doneIcon
    window.setTimeout(() => {
      delete button.dataset.copied
      button.innerHTML = copyIcon
    }, 1200)
  })
  return button
}

export function codeCopyPlugin(onCopy: (text: string) => void) {
  return $prose(
    () =>
      new Plugin({
        key: new PluginKey('codeCopy'),
        props: {
          decorations(state: EditorState) {
            const widgets: Decoration[] = []
            state.doc.descendants((node, pos) => {
              if (node.type.name !== 'code_block') return true
              widgets.push(
                Decoration.widget(pos + 1, () => copyButton(onCopy), {
                  side: -1,
                  key: 'copy',
                  ignoreSelection: true,
                }),
              )
              return false
            })
            return DecorationSet.create(state.doc, widgets)
          },
        },
      }),
  )
}

// The heading holding the caret shows its marks, so the level can be read while editing; a decoration,
// so the document never holds them.
export const headingMarkPlugin = $prose(
  () =>
    new Plugin({
      key: new PluginKey('headingMark'),
      props: {
        decorations(state: EditorState) {
          const { $from, $to } = state.selection
          if (!$from.sameParent($to) || $from.parent.type.name !== 'heading') return null
          const pos = $from.before()
          return DecorationSet.create(state.doc, [
            Decoration.node(pos, pos + $from.parent.nodeSize, { class: 'editing' }),
          ])
        },
      },
    }),
)
