// Test driver for assets/js/plan_map.mjs, run by
// StatifierExamplesWeb.PlanMapLayoutTest and StatifierExamplesWeb.PlanLiveTest
// through Node.
//
//   node plan_map_layout.mjs <graph.json> [editable]
//
// Lays the graph out through the real elkjs and draws it with the hook's
// own drawMap/3, then prints one JSON object: what was drawn ("map" or
// "error"), the drawn markup, every box and edge of the SAME layout that
// markup was drawn from in absolute coordinates, `interrupts` - every
// interrupt path in the markup, with its dash and its path data as drawn -
// `marks`, each block's timer marks as the markup carries them,
// `bands` - each branch's band and fork mark as drawn - `rejoins`, every
// rejoin path with its join dot, and `headers`, the lines under each
// block's title in the order they are drawn - `captions`, every caption
// with its text and place, keyed by the node it is drawn in - and
// `gestures` - for every clickable element the markup carries, the event
// and payload the hook's own mapGesture/2 turns a click on it into - and
// `starts`, every start dot as drawn with what a click on it asks, and
// `childGestures`, the same
// asked of a click on each of that element's children (the rect, text,
// circle or path a real click lands on), which reach the element by walking
// up exactly as a browser's `closest` does.
import {readFileSync} from "node:fs"
import {boxes, drawMap, edgesOf, interruptsOf, mapGesture} from "../../../assets/js/plan_map.mjs"

const graph = JSON.parse(readFileSync(process.argv[2], "utf8"))
const editable = process.argv[3] === "editable"
const target = {innerHTML: ""}
const {drawn, laid} = await drawMap(target, graph, {editable})

const laidOut = {}
const edges = []
const drawnPoints = {}
if (laid) {
  for (const box of boxes(laid)) {
    laidOut[box.id] = {x: box.x, y: box.y, width: box.width, height: box.height}
  }
  for (const edge of edgesOf(laid)) {
    const sections = edge.sections || []
    edges.push({
      id: edge.id,
      source: edge.sources[0],
      target: edge.targets[0],
      kind: edge.kind,
      sections: sections.length,
      start: sections.length ? sections[0].startPoint : null,
      end: sections.length ? sections[sections.length - 1].endPoint : null,
      labels: (edge.labels || []).map((l) => ({text: l.text, x: l.x, y: l.y, width: l.width, height: l.height})),
    })
  }
  for (const edge of interruptsOf(laid)) drawnPoints[edge.id] = edge
}

// A small element tree over the drawn markup: every tag with its data
// attributes as `dataset`, its parent, and a `closest` that walks from the
// element up through its ancestors, as the DOM's does, matching the
// attribute selectors mapGesture asks (`[name]` and `[name=value]`).
const unescape = (v) => v.replace(/&quot;/g, "\"").replace(/&#39;/g, "'")
  .replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&amp;/g, "&")
const camel = (name) => name.replace(/-([a-z])/g, (_m, c) => c.toUpperCase())

function matches(el, selector) {
  const [, name, value] = selector.match(/^\[([a-z-]+)(?:=([^\]]+))?\]$/)
  const key = camel(name.replace(/^data-/, ""))
  if (!(key in el.dataset)) return false
  return value === undefined || el.dataset[key] === value
}

function parse(markup) {
  const root = {tag: "#root", dataset: {}, parent: null, children: []}
  let current = root
  for (const [token, closing, tag, attrs, selfClosing] of
    markup.matchAll(/<(\/?)([a-zA-Z]+)([^>]*?)(\/?)>/g)) {
    if (closing) {
      current = current.parent || root
      continue
    }
    const dataset = {}
    for (const [, name, value] of attrs.matchAll(/data-([a-z-]+)="([^"]*)"/g)) {
      dataset[camel(name)] = unescape(value)
    }
    const el = {tag, dataset, parent: current, children: [], token}
    el.closest = (selector) => {
      for (let at = el; at && at.tag !== "#root"; at = at.parent) {
        if (matches(at, selector)) return at
      }
      return null
    }
    current.children.push(el)
    if (!selfClosing) current = el
  }
  return root
}

const all = []
const walk = (el) => { for (const child of el.children) { all.push(child); walk(child) } }
walk(parse(target.innerHTML))

const keyOf = (el) =>
  el.dataset.mapGap !== undefined ? `gap:${el.dataset.mapGap}` : `${el.dataset.mapKind}:${el.dataset.mapNode}`

const gestures = []
const childGestures = []
for (const el of all.filter((e) => e.tag === "g" && (e.dataset.mapGap !== undefined || e.dataset.mapKind !== undefined))) {
  gestures.push({element: keyOf(el), gesture: mapGesture(el, editable)})
  for (const child of el.children) {
    childGestures.push({element: keyOf(el), child: child.tag, gesture: mapGesture(child, editable)})
  }
}

// The start dot, and what a click on it or on any of its children asks
// for: the dot selects nothing, so every answer is expected to be null.
const starts = []
for (const el of all.filter((e) => e.dataset.mapStart !== undefined)) {
  starts.push({
    id: el.dataset.mapStart,
    kind: el.dataset.mapKind === undefined ? null : el.dataset.mapKind,
    children: el.children.map((c) => c.tag),
    gestures: [el, ...el.children].map((c) => mapGesture(c, editable)),
  })
}

// An interrupt edge is read off the markup: a path marked
// data-map-edge-kind="interrupt", with its dash and its points as drawn.
const interrupts = []
for (const [path] of target.innerHTML.matchAll(/<path [^>]*data-map-edge-kind="interrupt"[^>]*>/g)) {
  const attr = (name) => (path.match(new RegExp(`\\s${name}="([^"]*)"`)) || [])[1]
  const id = unescape(attr("data-map-edge"))
  const edge = drawnPoints[id]
  interrupts.push({
    id,
    to: attr("data-map-edge-to"),
    dashed: /stroke-dasharray:\s*[1-9]/.test(attr("style") || ""),
    d: attr("d"),
    source: edge ? edge.source : null,
    target: edge ? edge.target : null,
  })
}

// Every block's timer marks: the data-map-mark of every element inside
// the block's own group, keyed by the block's id.
const marks = {}
for (const el of all.filter((e) => e.dataset.mapMark !== undefined)) {
  const box = el.closest("[data-map-kind=block]")
  if (box) (marks[box.dataset.mapNode] ||= []).push(el.dataset.mapMark)
}

// Every branch's band: the rect marked data-map-band, the block group it
// is drawn in, and the first point of the fork mark drawn in that group.
const num = (el, name) => Number((el.token.match(new RegExp(`\\s${name}="([^"]*)"`)) || [])[1])
const bands = {}
for (const el of all.filter((e) => e.dataset.mapBand !== undefined)) {
  const box = el.closest("[data-map-kind=block]")
  const fork = all.find((f) => f.dataset.mapFork !== undefined &&
    f.closest("[data-map-kind=block]") === box)
  const [, fx, fy] = fork ? fork.token.match(/d="M(-?[\d.]+) (-?[\d.]+)/) : [null, null, null]
  ;(bands[el.dataset.mapBand] ||= []).push({
    in: box ? box.dataset.mapNode : null,
    x: num(el, "x"), y: num(el, "y"), width: num(el, "width"), height: num(el, "height"),
    fork: fork ? {x: Number(fx), y: Number(fy)} : null,
  })
}

// Every rejoin path, with its path data, and the join dot drawn for it.
const rejoins = []
for (const el of all.filter((e) => e.dataset.mapEdgeKind === "rejoin")) {
  const dot = all.find((c) => c.dataset.mapJoin === el.dataset.mapEdge)
  rejoins.push({
    id: el.dataset.mapEdge,
    d: unescape((el.token.match(/\sd="([^"]*)"/) || [])[1] || ""),
    dot: dot ? {x: num(dot, "cx"), y: num(dot, "cy")} : null,
  })
}

// Every caption, read off the markup: its text, where it is drawn, and the
// node whose group it is drawn in (a branch, for the caption on its band;
// a group's rules column, for the one under its label).
const captions = {}
for (const el of all.filter((e) => e.dataset.mapCaption !== undefined)) {
  const node = el.closest("[data-map-node]")
  const edge = node ? null : el.closest("[data-map-edge]")
  const text = (target.innerHTML.slice(target.innerHTML.indexOf(el.token) + el.token.length).match(/^([^<]*)<\/text>/) || [])[1]
  ;(captions[node ? node.dataset.mapNode : edge ? edge.dataset.mapEdge : ""] ||= []).push({
    text: unescape(text || ""), x: num(el, "x"), y: num(el, "y"),
  })
}

// The lines under each block's title, read off the markup from the block's
// own group to the next node's.
const headers = {}
const html = target.innerHTML
for (const [, id, rest] of html.matchAll(/data-map-node="([^"]*)" data-map-kind="block">(.*?)(?=data-map-node=|$)/g)) {
  headers[unescape(id)] = [...rest.matchAll(/<text class="plan-map__sentence"[^>]*>([^<]*)<\/text>/g)]
    .map((m) => unescape(m[1]))
}

process.stdout.write(JSON.stringify({drawn, html: target.innerHTML, boxes: laidOut, edges, interrupts, marks, bands, rejoins, headers, captions, gestures, childGestures, starts}))
