// The Plan view's map: lays out the graph `StatifierExamplesWeb.PlanMap`
// builds with elkjs and draws it as plain SVG.
//
// The server decides everything that is a fact about the document - which
// boxes exist, what they say, how big they are, the order they are in and
// the ELK options that keep that order. This file asks ELK where the boxes
// go and draws them there. It stores nothing: a position lives only in the
// SVG it was drawn into, and the next change lays the graph out again.
//
// A layout that fails draws an error pane in place of the map, never a
// blank one: an empty panel reads as "this document has no steps", which is
// a worse answer than "the map could not be drawn".
//
// `.mjs` so that Node reads it as a module without a package.json: the
// layout tests run this file, through elkjs, outside the browser.
import ELK from "../vendor/elk.bundled.js"

const SVG_NS = "http://www.w3.org/2000/svg"
const LINE_HEIGHT = 16
const HEADER_BASE = 12

let sharedElk = null

// One ELK instance per page: the bundled build carries its own worker
// shim, and building it is the expensive part.
function elkInstance() {
  if (sharedElk === null) sharedElk = new ELK()
  return sharedElk
}

export function escapeText(value) {
  return String(value)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;")
}

// Lays `graph` out. Resolves to the laid-out graph, or rejects with the
// reason ELK gave - including a result with nothing in it, which is a
// failure rather than a picture.
export async function layout(graph, elk = elkInstance()) {
  const laid = await elk.layout(graph)

  if (!laid || !Array.isArray(laid.children) || laid.children.length === 0 ||
      !(laid.width > 0) || !(laid.height > 0)) {
    throw new Error("the layout came back empty")
  }

  return laid
}

// Every node in the laid-out graph, parents before children, with its box
// made absolute. ELK answers a child's position relative to its parent, so
// the offsets are added up here, once, rather than by every drawing step.
export function boxes(laid) {
  const out = []
  const walk = (node, dx, dy) => {
    for (const child of node.children || []) {
      const box = {...child, x: dx + child.x, y: dy + child.y}
      out.push(box)
      walk(child, box.x, box.y)
    }
  }
  walk(laid, 0, 0)
  return out
}

// Every edge with its points made absolute. An edge's points are relative
// to the node it is declared in, which is the container holding both of
// its ends.
export function edgesOf(laid) {
  const out = []
  const shift = (p, dx, dy) => ({x: dx + p.x, y: dy + p.y})
  const walk = (node, dx, dy) => {
    for (const edge of node.edges || []) {
      const sections = (edge.sections || []).map((section) => ({
        startPoint: shift(section.startPoint, dx, dy),
        endPoint: shift(section.endPoint, dx, dy),
        bendPoints: (section.bendPoints || []).map((p) => shift(p, dx, dy)),
      }))
      out.push({...edge, sections})
    }
    for (const child of node.children || []) walk(child, dx + child.x, dy + child.y)
  }
  walk(laid, 0, 0)
  return out
}

function textLines(node, x, y, className) {
  return (node.lines || [])
    .map((line, i) =>
      `<text class="${className}" x="${x}" y="${y + i * LINE_HEIGHT}">${escapeText(line)}</text>`)
    .join("")
}

// The "+" at a block's lower right corner: the gap right after the block,
// the same gap the list's "+" under its row arms. Drawn only on a page that
// can edit, and never for the root, which sits in no slot.
function drawGap(node) {
  if (node.kind !== "block" || node.gap !== true) return ""
  const cx = node.x + node.width - 10
  const cy = node.y + node.height
  return `<g class="plan-map__gap" data-map-gap="${escapeText(node.id)}">` +
    `<circle cx="${cx}" cy="${cy}" r="7" ` +
    `style="fill: var(--plan-map-block-fill, #ffffff); stroke: var(--plan-map-edge, #64748b)"/>` +
    `<path d="M${cx - 3.5} ${cy} H${cx + 3.5} M${cx} ${cy - 3.5} V${cy + 3.5}" ` +
    `style="stroke: var(--plan-map-edge, #64748b); stroke-width: 1.5"/>` +
    `</g>`
}

function drawNode(node) {
  const x = node.x
  const y = node.y
  const w = node.width
  const h = node.height
  const container = Array.isArray(node.children) && node.children.length > 0
  const id = escapeText(node.id)

  if (node.kind === "empty") {
    const target = node.parent === undefined ? "" :
      ` data-map-parent="${escapeText(node.parent)}" data-map-slot="${escapeText(node.slot)}"`
    return `<g class="plan-map__empty" data-map-node="${id}" data-map-kind="empty"${target}>` +
      `<rect x="${x}" y="${y}" width="${w}" height="${h}" rx="6" ` +
      `style="fill: var(--plan-map-empty-fill, transparent); stroke: var(--plan-map-empty-stroke, #94a3b8); stroke-dasharray: 4 3"/>` +
      `<text class="plan-map__empty-text" x="${x + 12}" y="${y + HEADER_BASE + LINE_HEIGHT - 4}">${escapeText(node.title)}</text>` +
      `</g>`
  }

  if (node.kind === "slot") {
    const style = escapeText(node.style || "arm")
    return `<g class="plan-map__slot plan-map__slot--${style}" data-map-node="${id}" data-map-kind="slot">` +
      `<rect x="${x}" y="${y}" width="${w}" height="${h}" rx="8" ` +
      `style="fill: var(--plan-map-slot-fill, #f8fafc); stroke: var(--plan-map-slot-stroke, #cbd5e1)"/>` +
      textLines(node, x + 12, y + HEADER_BASE + LINE_HEIGHT - 4, "plan-map__slot-label") +
      `</g>`
  }

  const caption = `<text class="plan-map__title" x="${x + 12}" y="${y + HEADER_BASE + LINE_HEIGHT - 4}">${escapeText(node.title)}</text>`
  const body = textLines(node, x + 12, y + HEADER_BASE + 2 * LINE_HEIGHT - 4, "plan-map__sentence")

  return `<g class="plan-map__block${container ? " plan-map__block--container" : ""}" data-map-node="${id}" data-map-kind="block">` +
    `<rect x="${x}" y="${y}" width="${w}" height="${h}" rx="8" ` +
    `style="fill: var(--plan-map-block-fill, #ffffff); stroke: var(--plan-map-block-stroke, #64748b)"/>` +
    caption + body +
    `</g>`
}

function drawEdge(edge) {
  return (edge.sections || []).map((section) => {
    const points = [section.startPoint, ...(section.bendPoints || []), section.endPoint]
    const d = points.map((p, i) => `${i === 0 ? "M" : "L"}${p.x} ${p.y}`).join(" ")
    return `<path class="plan-map__edge" data-map-edge="${escapeText(edge.id)}" d="${d}" ` +
      `marker-end="url(#plan-map-arrow)" style="fill: none; stroke: var(--plan-map-edge, #64748b)"/>`
  }).join("")
}

// The laid-out graph as one SVG string. The picture is decoration over the
// list, which is the accessible path through the same document, so the SVG
// is hidden from assistive technology and takes no focus.
//
// `editable` adds the gaps an insert can target; a read-only page draws
// none.
export function renderSvg(laid, {editable = false} = {}) {
  const all = boxes(laid)
  const nodes = all.map(drawNode).join("")
  const gaps = editable ? all.map(drawGap).join("") : ""
  const edges = edgesOf(laid).map(drawEdge).join("")
  const width = Math.ceil(laid.width)
  const height = Math.ceil(laid.height)

  return `<svg xmlns="${SVG_NS}" class="plan-map__svg" data-map-svg="true" ` +
    `width="${width}" height="${height}" viewBox="0 0 ${width} ${height}" ` +
    `aria-hidden="true" focusable="false">` +
    `<defs><marker id="plan-map-arrow" viewBox="0 0 10 10" refX="10" refY="5" ` +
    `markerWidth="7" markerHeight="7" orient="auto-start-reverse">` +
    `<path d="M0 0 L10 5 L0 10 z" style="fill: var(--plan-map-edge, #64748b)"/></marker></defs>` +
    nodes + edges + gaps +
    `</svg>`
}

// The pane drawn in place of a map that could not be laid out.
export function renderError(reason) {
  const message = reason && reason.message ? reason.message : String(reason)

  return `<div class="plan-map__error" data-map-error="true">` +
    `<p class="plan-map__error-title">The map could not be drawn.</p>` +
    `<p class="plan-map__error-reason">${escapeText(message)}</p>` +
    `<p class="plan-map__error-hint">The list has every step of this document.</p>` +
    `</div>`
}

// Lays `graph` out and draws the result, or the error pane, into `target`.
// Resolves to `{drawn: "map", laid}` with the laid-out graph it drew, or
// `{drawn: "error", laid: null}`, so a caller can tell which it drew and
// read the very positions it drew from. `editable` is `renderSvg`'s.
export async function drawMap(target, graph, {elk = elkInstance(), editable = false} = {}) {
  try {
    const laid = await layout(graph, elk)
    target.innerHTML = renderSvg(laid, {editable})
    return {drawn: "map", laid}
  } catch (reason) {
    target.innerHTML = renderError(reason)
    return {drawn: "error", laid: null}
  }
}

// What a click on the map asks the page to do, as `{event, payload}`, or
// null. Every event is one the page's list already sends, with the payload
// the list sends it: a block's box selects it (`select-row`); a gap arms
// the insert right after its block (`insert-open`, as the row's "+");
// an empty slot's marker arms the insert at the head of that slot
// (`insert-open` with the slot named). A page that cannot edit gets only
// the selection. `target` is any element with `closest` and `dataset`.
export function mapGesture(target, editable) {
  const gap = target.closest("[data-map-gap]")
  if (gap) return editable ? {event: "insert-open", payload: {"block-id": gap.dataset.mapGap}} : null

  const empty = target.closest("[data-map-kind=empty]")
  if (empty) {
    if (!editable || empty.dataset.mapParent === undefined) return null
    return {
      event: "insert-open",
      payload: {"block-id": empty.dataset.mapParent, slot: empty.dataset.mapSlot},
    }
  }

  const box = target.closest("[data-map-kind=block]")
  if (box) return {event: "select-row", payload: {"block-id": box.dataset.mapNode}}

  return null
}

// Marks the box of the block the page has selected, and unmarks the rest.
export function markSelected(target, id) {
  for (const node of target.querySelectorAll("[data-map-kind=block]")) {
    node.classList.toggle("plan-map__block--selected", node.dataset.mapNode === id)
  }
}

// The LiveView hook. The graph arrives JSON-encoded in `data-graph` on the
// hook's element, the selected block's id in `data-selected`, and whether
// the page can edit in `data-editable`; the drawing goes into the child
// marked `data-map-canvas` (which the page keeps out of LiveView's
// patching) or, lacking one, into the element itself.
//
// A patch that changes only the selection re-marks the drawing rather than
// laying it out again. A layout still running when a newer graph arrives is
// dropped when it lands, so a slow layout never draws over a newer one.
//
// A click becomes the event `mapGesture` names, sent through the page's
// own handlers. After an insert armed from the map, the next patch scrolls
// the open picker into view, since it may sit below the map. The map is
// hidden from assistive technology; the list and the panel are the keyboard
// path to every one of these gestures but the insert into an empty slot.
export const PlanMap = {
  mounted() {
    this.el.addEventListener("click", (event) => {
      const gesture = mapGesture(event.target, this.el.dataset.editable === "true")
      if (!gesture) return
      if (gesture.event === "insert-open") this.revealPicker = true
      this.pushEvent(gesture.event, gesture.payload)
    })
    this.draw()
  },

  updated() {
    this.draw()
    if (this.revealPicker) {
      const picker = document.querySelector("[data-plan-picker=open]")
      if (picker) {
        this.revealPicker = false
        picker.scrollIntoView({block: "nearest"})
      }
    }
  },

  draw() {
    const target = this.el.querySelector("[data-map-canvas]") || this.el
    const editable = this.el.dataset.editable === "true"
    const source = `${editable}|${this.el.dataset.graph}`
    const selected = this.el.dataset.selected || null

    if (source === this.source) {
      markSelected(target, selected)
      return
    }

    this.source = source
    const token = (this.drawn = (this.drawn || 0) + 1)
    let graph

    try {
      graph = JSON.parse(this.el.dataset.graph)
    } catch (reason) {
      target.innerHTML = renderError(reason)
      return
    }

    const staging = {innerHTML: ""}
    drawMap(staging, graph, {editable}).then(() => {
      if (token !== this.drawn) return
      target.innerHTML = staging.innerHTML
      markSelected(target, this.el.dataset.selected || null)
    })
  },
}

export default {PlanMap}
