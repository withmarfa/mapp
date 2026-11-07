const threshold = 4
/** How long a dropped row waits for the app's new order before it goes back where it was. */
const settling = 300

/** Lets a row of `list` be dragged by its key. The other rows make way as it passes. Escape puts it back, and a press
 *  that does not move stays a click. `move` gets the row and the row it now comes before, or null for the end. */
export function dragRows(list: HTMLElement, move: (row: string, before: string | null) => void) {
  list.addEventListener('pointerdown', (down) => {
    const key = (down.target as Element | null)?.closest?.('.item-prop-label')
    const entry = key?.parentElement
    const rows = [...list.children] as HTMLElement[]
    if (down.button !== 0 || down.ctrlKey || !entry || rows.length < 2) return

    const from = rows.indexOf(entry)
    const origin = list.getBoundingClientRect().top
    const spans = rows.map((row) => {
      const { top, height } = row.getBoundingClientRect()
      return { row, top: top - origin, height }
    })
    const own = spans[from]
    if (!own) return
    const room = list.getBoundingClientRect().height
    const pressed = down.clientY - origin
    let dragging = false
    let target = from

    // Against the list's own top, so scrolling during the drag changes nothing.
    const place = (y: number) => {
      const wanted = y - list.getBoundingClientRect().top - pressed
      const offset = Math.min(Math.max(wanted, -own.top), room - own.top - own.height)
      const start = own.top + offset
      const end = start + own.height
      target = from
      spans.forEach(({ row, top, height }, index) => {
        if (index === from) {
          row.style.transform = `translateY(${offset}px)`
          return
        }
        const middle = top + height / 2
        const passedDown = index > from && end > middle
        const passedUp = index < from && start < middle
        if (passedDown) target += 1
        if (passedUp) target -= 1
        const shift = passedDown ? -own.height : passedUp ? own.height : 0
        row.style.transform = shift ? `translateY(${shift}px)` : ''
      })
    }

    const restore = () => rows.forEach((row) => row.style.removeProperty('transform'))

    const onMove = (event: PointerEvent) => {
      if (!entry.isConnected) return finish(false)
      if (!dragging) {
        if (Math.abs(event.clientY - down.clientY) < threshold) return
        dragging = true
        list.classList.add('dragging')
        entry.classList.add('dragged')
      }
      place(event.clientY)
    }

    const onKey = (event: KeyboardEvent) => {
      if (event.key !== 'Escape' || !dragging) return
      event.preventDefault()
      event.stopPropagation()
      finish(false)
    }

    const onUp = () => finish(true)
    const onCancel = () => finish(false)

    function finish(drop: boolean) {
      window.removeEventListener('pointermove', onMove)
      window.removeEventListener('pointerup', onUp)
      window.removeEventListener('pointercancel', onCancel)
      window.removeEventListener('keydown', onKey, true)
      if (!dragging) return
      list.classList.remove('dragging')
      entry?.classList.remove('dragged')

      // The release must not also open the row's editor.
      const swallow = (event: Event) => event.stopPropagation()
      window.addEventListener('click', swallow, { capture: true, once: true })
      setTimeout(() => window.removeEventListener('click', swallow, true))

      if (!drop || target === from) return restore()
      const order = rows.filter((row) => row !== entry)
      const next = order[target]?.dataset.row ?? null
      if (entry?.dataset.row) move(entry.dataset.row, next)
      // The app draws the new order over these rows. Where it refuses the move, they go back.
      setTimeout(restore, settling)
    }

    window.addEventListener('pointermove', onMove)
    window.addEventListener('pointerup', onUp)
    window.addEventListener('pointercancel', onCancel)
    window.addEventListener('keydown', onKey, true)
  })
}
