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
  const {graph: attached, owners} = onPorts(graph)
  const laid = await elk.layout(attached)

  if (!laid || !Array.isArray(laid.children) || laid.children.length === 0 ||
      !(laid.width > 0) || !(laid.height > 0)) {
    throw new Error("the layout came back empty")
  }

  return offPorts(laid, owners)
}

const PORT_SIDE = "org.eclipse.elk.port.side"

// A copy of `graph` with every edge into or out of a node that carries
// ports moved onto them: an edge out of the node leaves by its bottom
// port, an edge into it arrives by its top one. The server places a
// group's ports where its body's steps stand, so the happy path runs
// straight through the group (the PlanMap moduledoc's "The happy path
// runs straight"). Answers the copy and each port's owner.
export function onPorts(graph) {
  const copy = structuredClone(graph)
  const sides = new Map()
  const owners = new Map()
  const collect = (node) => {
    for (const port of node.ports || []) {
      const side = (port.layoutOptions || {})[PORT_SIDE]
      sides.set(`${node.id}|${side}`, port.id)
      owners.set(port.id, node.id)
    }
    for (const child of node.children || []) collect(child)
  }
  const attach = (node) => {
    for (const edge of node.edges || []) {
      edge.sources = edge.sources.map((id) => sides.get(`${id}|SOUTH`) || id)
      edge.targets = edge.targets.map((id) => sides.get(`${id}|NORTH`) || id)
    }
    for (const child of node.children || []) attach(child)
  }
  collect(copy)
  if (owners.size > 0) attach(copy)
  return {graph: copy, owners}
}

// The laid-out graph with every edge given back its own ends: a port's
// owner in place of the port, so an edge joins block to block again.
export function offPorts(laid, owners) {
  const detach = (node) => {
    for (const edge of node.edges || []) {
      edge.sources = edge.sources.map((id) => owners.get(id) || id)
      edge.targets = edge.targets.map((id) => owners.get(id) || id)
    }
    for (const child of node.children || []) detach(child)
  }
  if (owners.size > 0) detach(laid)
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

// Every edge with its points, and its labels' boxes, made absolute. An
// edge's points are relative to the node it is declared in, which is the
// container holding both of its ends; so are its labels'.
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
      const labels = (edge.labels || []).map((label) => ({...label, ...shift(label, dx, dy)}))
      out.push({...edge, sections, labels})
    }
    for (const child of node.children || []) walk(child, dx + child.x, dy + child.y)
  }
  walk(laid, 0, 0)
  return out
}

// Every group's interrupt edges, each with the points it is drawn through,
// absolute. They are not ELK's: the server hands them over on the group's
// node as `interrupts`, beside its `edges`, so the layout never sees them
// and they never move a box. Each is drawn from the boxes the layout
// placed: an `abandon` rule (`to: "exit"`) straight down from the bottom
// of its box to the group's bottom edge, which is where the group is left;
// a `resume` rule (`to: "body"`) up from the top of its box to the head of
// the group's body, and in from its side when the head sits to the left.
export function interruptsOf(laid) {
  const all = boxes(laid)
  const byId = new Map(all.map((box) => [box.id, box]))
  const out = []

  for (const group of all) {
    for (const edge of group.interrupts || []) {
      const rule = byId.get(edge.sources[0])
      if (!rule) continue
      const x = rule.x + rule.width / 2
      let points

      if (edge.to === "exit") {
        points = [{x, y: rule.y + rule.height}, {x, y: group.y + group.height}]
      } else {
        const head = byId.get(edge.head)
        if (head && head.x + head.width < x) {
          const y = head.y + head.height / 2
          points = [{x, y: rule.y}, {x, y}, {x: head.x + head.width, y}]
        } else {
          points = [{x, y: rule.y}, {x, y: head ? head.y + head.height : group.y}]
        }
      }

      out.push({id: edge.id, source: edge.sources[0], target: edge.targets[0], to: edge.to, points})
    }
  }

  return out
}

// A branch's band: one strip spanning every arm, in the room the server
// left between the branch's header and its arms, with the fork mark at its
// left and the branch's caption after it. Read from the boxes the layout
// placed, never stored; never narrower than the server's `caption_width`,
// the room the fork mark and the caption need. Answers
// `{x, y, width, height, fork: {x, y}, caption: {x, y} | null}` in the
// coordinates `node` is in (absolute, for a box out of `boxes`), or null
// for a node with no band or no arm.
const BAND_HEIGHT = 16
const BAND_GAP = 4
// The fork mark's room at the band's left, before the caption: the same
// 26px the server's `caption_width` counts.
const FORK_ROOM = 26

export function bandOf(node) {
  if (node.band !== true) return null
  const arms = (node.children || []).filter((c) => c.kind === "slot" && c.style === "arm")
  if (arms.length === 0) return null

  const left = Math.min(...arms.map((a) => a.x))
  const right = Math.max(...arms.map((a) => a.x + a.width))
  const top = Math.min(...arms.map((a) => a.y))
  const y = node.y + top - BAND_GAP - BAND_HEIGHT

  return {
    x: node.x + left,
    y,
    width: Math.max(right - left, node.caption_width || 0),
    height: BAND_HEIGHT,
    fork: {x: node.x + left + 6, y: y + 1},
    caption: node.caption ? {x: node.x + left + FORK_ROOM, y: y + BAND_HEIGHT - 4} : null,
  }
}

// The fork mark, a 14px glyph: one stem splitting into three.
function drawFork({x, y}) {
  return `<path class="plan-map__fork" data-map-fork="true" ` +
    `d="M${x + 7} ${y} V${y + 5} M${x + 7} ${y + 5} L${x + 1} ${y + 13} ` +
    `M${x + 7} ${y + 5} V${y + 13} M${x + 7} ${y + 5} L${x + 13} ${y + 13}" style="${MARK_STYLE}"/>`
}

function drawBand(node) {
  const band = bandOf(node)
  if (band === null) return ""
  // Its own group, so the selected box's `> rect` outline stays on the box.
  return `<g class="plan-map__band-group">` +
    `<rect class="plan-map__band" data-map-band="${escapeText(node.id)}" ` +
    `x="${band.x}" y="${band.y}" width="${band.width}" height="${band.height}" rx="4" ` +
    `style="fill: var(--plan-map-band-fill, #e2e8f0); stroke: var(--plan-map-slot-stroke, #cbd5e1)"/>` +
    drawFork(band.fork) + drawCaption(band.caption, node.caption) + `</g>`
}

// A container's one-line caption: on a branch's band, or under a group's
// rules column's label. The text is the server's, from the host's one
// module of fixed type text.
function drawCaption(at, text) {
  if (!at || !text) return ""
  return `<text class="plan-map__caption" data-map-caption="true" x="${at.x}" y="${at.y}">` +
    `${escapeText(text)}</text>`
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

  // Where the document finishes: the state chart's final mark, a dot inside
  // a ring, one per outcome it finishes with - a solid ring for done, a
  // dashed one where an interrupt rule abandons the last step. It carries
  // no text (the outcome is named on the edge into it). Like the start dot
  // it is not a block: it carries its id, so the description region can
  // name it, but no data-map-kind, so a click on it selects nothing.
  if (node.kind === "end") {
    const abandon = node.outcome === "abandon"
    const cx = x + w / 2
    const cy = y + h / 2
    const r = Math.min(w, h) / 2 - 1
    return `<g class="plan-map__end plan-map__end--${abandon ? "abandon" : "done"}" ` +
      `data-map-end="${id}" data-map-node="${id}" data-map-outcome="${escapeText(node.outcome)}">` +
      `<circle class="plan-map__end-ring" cx="${cx}" cy="${cy}" r="${r}" ` +
      `style="fill: none; stroke: var(--plan-map-edge, #64748b); stroke-width: 1.5` +
      `${abandon ? "; stroke-dasharray: 3 2" : ""}"/>` +
      `<circle class="plan-map__end-dot" cx="${cx}" cy="${cy}" r="${r / 2}" ` +
      `style="fill: var(--plan-map-edge, #64748b)"/>` +
      `</g>`
  }

  // Where the document starts: the state chart's initial mark, a filled
  // dot with no text. Like the end mark it is not a block, and it carries
  // no data-map-kind, so a click on it selects nothing.
  if (node.kind === "start") {
    return `<g class="plan-map__start" data-map-start="${id}" data-map-node="${id}">` +
      `<circle cx="${x + w / 2}" cy="${y + h / 2}" r="${Math.min(w, h) / 2}" ` +
      `style="fill: var(--plan-map-edge, #64748b)"/>` +
      `</g>`
  }

  // A slot's box: an arm, a rail, a tray, or a group's body pane. A group's
  // rules column carries its caption on the line under its label.
  if (node.kind === "slot") {
    const style = escapeText(node.style || "arm")
    const top = y + HEADER_BASE + LINE_HEIGHT - 4
    const caption = {x: x + 12, y: top + (node.lines || []).length * LINE_HEIGHT}
    return `<g class="plan-map__slot plan-map__slot--${style}" data-map-node="${id}" data-map-kind="slot">` +
      `<rect x="${x}" y="${y}" width="${w}" height="${h}" rx="8" ` +
      `style="fill: var(--plan-map-slot-fill, #f8fafc); stroke: var(--plan-map-slot-stroke, #cbd5e1)"/>` +
      textLines(node, x + 12, top, "plan-map__slot-label") + drawCaption(caption, node.caption) +
      `</g>`
  }

  const caption = `<text class="plan-map__title" x="${x + 12}" y="${y + HEADER_BASE + LINE_HEIGHT - 4}">${escapeText(node.title)}</text>`
  const body = textLines(node, x + 12, y + HEADER_BASE + 2 * LINE_HEIGHT - 4, "plan-map__sentence")

  return `<g class="plan-map__block${container ? " plan-map__block--container" : ""}" data-map-node="${id}" data-map-kind="block">` +
    `<rect x="${x}" y="${y}" width="${w}" height="${h}" rx="8" ` +
    `style="fill: var(--plan-map-block-fill, #ffffff); stroke: var(--plan-map-block-stroke, #64748b)"/>` +
    caption + body + drawMark(node) + drawBand(node) +
    `</g>`
}

// A timer block's mark, a 14px glyph at the box's top right, level with the
// title (the server left the title room for it): an hourglass for a wait
// (`core.await`), a clock face for a delayed send. It is drawn inside the
// block's group, so a click on it selects the block and nothing else.
const MARK_STYLE = "fill: none; stroke: var(--plan-map-mark, #64748b); stroke-width: 1.5"

function drawMark(node) {
  if (node.mark !== "wait" && node.mark !== "clock") return ""
  const x = node.x + node.width - 22
  const y = node.y + HEADER_BASE - 4
  const glyph = node.mark === "wait"
    ? `<path d="M${x + 2} ${y} H${x + 12} M${x + 2} ${y + 14} H${x + 12} ` +
      `M${x + 3} ${y} L${x + 11} ${y + 14} M${x + 11} ${y} L${x + 3} ${y + 14}" style="${MARK_STYLE}"/>`
    : `<circle cx="${x + 7}" cy="${y + 7}" r="6.5" style="${MARK_STYLE}"/>` +
      `<path d="M${x + 7} ${y + 3} V${y + 7} H${x + 10}" style="${MARK_STYLE}"/>`

  return `<g class="plan-map__mark plan-map__mark--${node.mark}" data-map-mark="${node.mark}">` +
    glyph + `</g>`
}

// A layout edge. A branch's rejoin is drawn heavier, with a join dot where
// it leaves the branch's bottom edge: the point the arms come back
// together. An edge into an end mark carries its outcome, and the one into
// an abandon end is dashed, as the interrupt edges that lead there are.
function drawEdge(edge) {
  const rejoin = edge.kind === "rejoin"
  const outcome = edge.outcome === undefined ? "" : ` data-map-outcome="${escapeText(edge.outcome)}"`
  return (edge.sections || []).map((section) => {
    const points = [section.startPoint, ...(section.bendPoints || []), section.endPoint]
    const d = points.map((p, i) => `${i === 0 ? "M" : "L"}${p.x} ${p.y}`).join(" ")
    const path = rejoin
      ? `<path class="plan-map__edge plan-map__edge--rejoin" data-map-edge="${escapeText(edge.id)}" ` +
        `data-map-edge-kind="rejoin"${outcome} d="${d}" marker-end="url(#plan-map-arrow)" ` +
        `style="fill: none; stroke: var(--plan-map-edge, #64748b); stroke-width: 1.5"/>`
      : edge.kind === "end"
        ? `<path class="plan-map__edge plan-map__edge--end" data-map-edge="${escapeText(edge.id)}" ` +
          `data-map-edge-kind="end"${outcome} d="${d}" marker-end="url(#plan-map-arrow)" ` +
          `style="fill: none; stroke: var(--plan-map-edge, #64748b)` +
          `${edge.outcome === "abandon" ? "; stroke-dasharray: 5 4" : ""}"/>`
        : `<path class="plan-map__edge" data-map-edge="${escapeText(edge.id)}" d="${d}" ` +
          `marker-end="url(#plan-map-arrow)" style="fill: none; stroke: var(--plan-map-edge, #64748b)"/>`
    const dot = rejoin
      ? `<circle class="plan-map__join" data-map-join="${escapeText(edge.id)}" ` +
        `data-map-edge="${escapeText(edge.id)}" ` +
        `cx="${section.startPoint.x}" cy="${section.startPoint.y}" r="3.5" ` +
        `style="fill: var(--plan-map-edge, #64748b)"/>`
      : ""
    return path + dot
  }).join("") + drawEdgeLabels(edge)
}

// An edge's caption - the start edge's sentence, or the outcome on an edge
// into an end mark - written where the layout placed its label (the server
// sized it, so the layout left it room). It carries the edge's id, so
// pointing at the caption names the edge.
function drawEdgeLabels(edge) {
  const which = edge.kind === "start" ? "start" : "end"
  return (edge.labels || []).map((label) =>
    `<text class="plan-map__caption plan-map__${which}-caption" data-map-caption="true" ` +
    `data-map-edge="${escapeText(edge.id)}" ` +
    `x="${label.x}" y="${label.y + label.height - 4}">${escapeText(label.text)}</text>`,
  ).join("")
}

// An interrupt edge, dashed: it is not a step that follows the one before
// it but a way out of (or back into) the group that fires whenever the
// rule's event arrives.
function drawInterrupt(edge) {
  const d = edge.points.map((p, i) => `${i === 0 ? "M" : "L"}${p.x} ${p.y}`).join(" ")
  return `<path class="plan-map__edge plan-map__edge--interrupt" data-map-edge="${escapeText(edge.id)}" ` +
    `data-map-edge-kind="interrupt" data-map-edge-to="${escapeText(edge.to)}" d="${d}" ` +
    `marker-end="url(#plan-map-arrow)" ` +
    `style="fill: none; stroke: var(--plan-map-edge, #64748b); stroke-dasharray: 5 4"/>`
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
  const edges = edgesOf(laid).map(drawEdge).join("") + interruptsOf(laid).map(drawInterrupt).join("")
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
