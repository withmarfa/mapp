import { tableBlock, tableBlockConfig, type RenderType } from '@milkdown/kit/component/table-block'
import type { Ctx, MilkdownPlugin } from '@milkdown/kit/ctx'
import { labels, type Labels } from './labels'

// Each icon carries its name, which is what VoiceOver reads for the button around it.
const stroke = (label: keyof Labels, paths: string) => () =>
  `<svg role="img" aria-label="${labels[label]}" width="14" height="14" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">${paths}</svg>`

// Drawn in the manner of the matching SF Symbols (plus, trash, text.alignleft and so on), which a web page
// cannot use directly.
const icons: Record<RenderType, () => string> = {
  add_row: stroke('addRow', '<path d="M8 3.5v9M3.5 8h9"/>'),
  add_col: stroke('addColumn', '<path d="M8 3.5v9M3.5 8h9"/>'),
  delete_row: stroke(
    'deleteRow',
    '<path d="M3 4.5h10M6.5 4.5V3h3v1.5M4.5 4.5l.6 8.5h5.8l.6-8.5M7 7v4M9 7v4"/>',
  ),
  delete_col: stroke(
    'deleteColumn',
    '<path d="M3 4.5h10M6.5 4.5V3h3v1.5M4.5 4.5l.6 8.5h5.8l.6-8.5M7 7v4M9 7v4"/>',
  ),
  align_col_left: stroke('alignLeft', '<path d="M3 4h10M3 7h6M3 10h10M3 13h6"/>'),
  align_col_center: stroke('alignCenter', '<path d="M3 4h10M5 7h6M3 10h10M5 13h6"/>'),
  align_col_right: stroke('alignRight', '<path d="M3 4h10M7 7h6M3 10h10M7 13h6"/>'),
  col_drag_handle: stroke('column', '<path d="M4 8h.01M8 8h.01M12 8h.01"/>'),
  row_drag_handle: stroke('row', '<path d="M8 4h.01M8 8h.01M8 12h.01"/>'),
}

/** Handles on a table's rows and columns to add, delete, align and drag them, as Notes offers. */
export const tableInterface: MilkdownPlugin[] = [
  tableBlockConfig,
  (ctx: Ctx) => () => {
    ctx.update(tableBlockConfig.key, (config: { renderButton: (type: RenderType) => string }) => ({
      ...config,
      renderButton: (type: RenderType) => icons[type](),
    }))
  },
  tableBlock,
].flat()
