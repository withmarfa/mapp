import type { FileCardAction } from '@aicayzer/inkkit'

/** The `eye` of SF Symbols, drawn as a stroke. Inkkit draws an action's icon as a mask in the button's color, so only
 *  the shape's alpha counts. */
const eye =
  '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="#000" stroke-width="1.6" ' +
  'stroke-linecap="round" stroke-linejoin="round"><path d="M2.5 12C4.5 8 8 5.5 12 5.5S19.5 8 21.5 12C19.5 16 16 18.5 ' +
  '12 18.5S4.5 16 2.5 12Z"/><circle cx="12" cy="12" r="3.2"/></svg>'

export const quickLookIcon = 'data:image/svg+xml,' + encodeURIComponent(eye)

/** Quick Look on a file's card, an icon in the card's corner. `template` has `%@` where the file's name goes, so
 *  cards of several files read apart to VoiceOver and in the hover. `run` asks the app, which decides what the
 *  reference names and whether it can be shown. */
export function quickLookAction(
  name: string,
  template: string | undefined,
  run: FileCardAction['run'],
): FileCardAction {
  return {
    label: (template ?? 'Quick Look %@').replace('%@', () => name),
    icon: quickLookIcon,
    run,
  }
}
