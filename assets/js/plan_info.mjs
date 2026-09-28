// The Plan view's description region, on hover: pointing at anything the
// map draws shows that element's description in the region at the top of
// the panel, and pointing away puts back what the region said before - the
// selected block's description, or the document's when nothing is
// selected.
//
// Every description was computed by the server
// (`StatifierExamplesWeb.PlanDescription`) and rendered into the page's
// hidden store, `#plan-descriptions`, one entry per map id under
// `data-describes`, in the same markup the region draws. This file only
// copies an entry into the region and back: it pushes nothing to the
// server, adds no command, and never changes what is selected.
//
// It is the host's own hook, beside `PlanMap`, and it sits on an element of
// its own (`#plan-info`), because an element carries one hook and the map's
// element already carries the map's. It listens on the document, so the
// map may be redrawn under it at any time.
//
// The region stays the list's: the map is `aria-hidden`, and a keyboard or
// a screen reader reaches every description by selecting a row, which the
// server renders into the region itself.
//
// `.mjs` so that Node reads it as a module without a package.json: the
// hover test drives this file, outside the browser.

// The map id of the drawn element `target` belongs to, or null when it
// belongs to none. A connector or an interrupt edge carries its id in
// `data-map-edge`; a block, a slot's box or an empty slot's marker in
// `data-map-node`, on the group its rect, text and timer mark sit inside.
// A gap's "+" describes nothing of its own.
export function describedId(target) {
  if (!target || typeof target.closest !== "function") return null
  if (target.closest("[data-map-gap]")) return null

  const edge = target.closest("[data-map-edge]")
  if (edge) return edge.dataset.mapEdge

  const node = target.closest("[data-map-node]")
  if (node) return node.dataset.mapNode

  return null
}

// The store's entry for `id`, or null. Compared by value rather than by an
// attribute selector, because a map id carries `>` and `/`.
export function entryFor(store, id) {
  for (const entry of store.children) {
    if (entry.dataset.describes === id) return entry
  }
  return null
}

// The swap and the restore, over a region and a store. `region()` and
// `store()` are asked afresh on every call, since a patch may replace
// either.
//
// `show(id)` puts the entry for `id` into the region and marks the region
// with `data-plan-hover`; the first swap keeps what the region said, so
// `restore()` can put it back. An id with no entry restores instead.
//
// A patch that reaches the region while it shows a hovered entry redraws
// the server's own content there and drops the mark; the kept content is
// then stale, so it is discarded rather than put back.
export function hover(region, store) {
  let resting = null

  function restore() {
    const el = region()
    if (el && resting !== null && el.dataset.planHover !== undefined) {
      el.innerHTML = resting
      delete el.dataset.planHover
    }
    resting = null
  }

  function show(id) {
    const el = region()
    const entry = id === null ? null : entryFor(store(), id)
    if (!el || !entry) return restore()

    if (el.dataset.planHover === undefined) resting = el.innerHTML
    if (el.dataset.planHover === id) return

    el.innerHTML = entry.innerHTML
    el.dataset.planHover = id
  }

  return {show, restore}
}

// The LiveView hook. A pointer arriving over any element names what it
// points at; one arriving over nothing the map draws, or leaving the
// window, puts the region back.
export const PlanInfo = {
  mounted() {
    const doc = this.el.ownerDocument
    this.hover = hover(
      () => doc.getElementById(this.el.dataset.region),
      () => doc.getElementById(this.el.dataset.store),
    )
    this.onOver = (event) => this.hover.show(describedId(event.target))
    this.onOut = (event) => {
      if (!event.relatedTarget) this.hover.restore()
    }
    doc.addEventListener("mouseover", this.onOver)
    doc.addEventListener("mouseout", this.onOut)
  },

  destroyed() {
    const doc = this.el.ownerDocument
    doc.removeEventListener("mouseover", this.onOver)
    doc.removeEventListener("mouseout", this.onOut)
  },
}

export default {PlanInfo}
