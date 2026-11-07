/** Names the app may set to change how links look: Inkkit's wiki link tokens and the page's own `--link-icon-<tone>`
 *  and `--link-tint-<tone>`, which say what a type's tone is under the look in force (`NoteLinkStatus`). */
const allowed = /^--(inkkit-wiki-link|link)-[a-z-]+$/

/**
 * How links look, as the custom properties the app sends for the person's choice. They are set on the page's root, so
 * every link reads them, and a look that leaves one unset takes the one before it off. The page chooses no look and
 * no color: it holds these and Inkkit's own defaults do the rest.
 */
export class LinkStyle {
  private applied = new Map<string, string>()

  constructor(private readonly style: CSSStyleDeclaration) {}

  /** Makes these the variables in force. Whether any differs from what was set. */
  set(variables: Record<string, string>): boolean {
    const next = new Map(Object.entries(variables).filter(([name]) => allowed.test(name)))
    let changed = false
    for (const name of this.applied.keys()) {
      if (next.has(name)) continue
      this.style.removeProperty(name)
      changed = true
    }
    for (const [name, value] of next) {
      if (this.applied.get(name) === value) continue
      this.style.setProperty(name, value)
      changed = true
    }
    this.applied = next
    return changed
  }
}
