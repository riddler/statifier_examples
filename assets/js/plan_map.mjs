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

function drawNode(node) {
  const x = node.x
  const y = node.y
  const w = node.width
  const h = node.height
  const container = Array.isArray(node.children) && node.children.length > 0
  const id = escapeText(node.id)

  if (node.kind === "empty") {
    return `<g class="plan-map__empty" data-map-node="${id}" data-map-kind="empty">` +
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
export function renderSvg(laid) {
  const nodes = boxes(laid).map(drawNode).join("")
  const edges = edgesOf(laid).map(drawEdge).join("")
  const width = Math.ceil(laid.width)
  const height = Math.ceil(laid.height)

  return `<svg xmlns="${SVG_NS}" class="plan-map__svg" data-map-svg="true" ` +
    `width="${width}" height="${height}" viewBox="0 0 ${width} ${height}" ` +
    `aria-hidden="true" focusable="false">` +
    `<defs><marker id="plan-map-arrow" viewBox="0 0 10 10" refX="10" refY="5" ` +
    `markerWidth="7" markerHeight="7" orient="auto-start-reverse">` +
    `<path d="M0 0 L10 5 L0 10 z" style="fill: var(--plan-map-edge, #64748b)"/></marker></defs>` +
    nodes + edges +
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
// read the very positions it drew from.
export async function drawMap(target, graph, elk = elkInstance()) {
  try {
    const laid = await layout(graph, elk)
    target.innerHTML = renderSvg(laid)
    return {drawn: "map", laid}
  } catch (reason) {
    target.innerHTML = renderError(reason)
    return {drawn: "error", laid: null}
  }
}

// Marks the box of the block the page has selected, and unmarks the rest.
export function markSelected(target, id) {
  for (const node of target.querySelectorAll("[data-map-kind=block]")) {
    node.classList.toggle("plan-map__block--selected", node.dataset.mapNode === id)
  }
}

// The LiveView hook. The graph arrives JSON-encoded in `data-graph` on the
// hook's element and the selected block's id in `data-selected`; the
// drawing goes into the child marked `data-map-canvas` (which the page
// keeps out of LiveView's patching) or, lacking one, into the element
// itself.
//
// A patch that changes only the selection re-marks the drawing rather than
// laying it out again. A layout still running when a newer graph arrives is
// dropped when it lands, so a slow layout never draws over a newer one.
//
// A click on a block's box sends the page the same `select-row` event the
// list's own row button sends, so the two views select through one handler.
// The map is hidden from assistive technology; the list is the keyboard
// path to the same selection.
export const PlanMap = {
  mounted() {
    this.el.addEventListener("click", (event) => {
      const box = event.target.closest("[data-map-kind=block]")
      if (box) this.pushEvent("select-row", {"block-id": box.dataset.mapNode})
    })
    this.draw()
  },

  updated() { this.draw() },

  draw() {
    const target = this.el.querySelector("[data-map-canvas]") || this.el
    const source = this.el.dataset.graph
    const selected = this.el.dataset.selected || null

    if (source === this.source) {
      markSelected(target, selected)
      return
    }

    this.source = source
    const token = (this.drawn = (this.drawn || 0) + 1)
    let graph

    try {
      graph = JSON.parse(source)
    } catch (reason) {
      target.innerHTML = renderError(reason)
      return
    }

    const staging = {innerHTML: ""}
    drawMap(staging, graph).then(() => {
      if (token !== this.drawn) return
      target.innerHTML = staging.innerHTML
      markSelected(target, this.el.dataset.selected || null)
    })
  },
}

export default {PlanMap}
