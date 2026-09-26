// Test driver for assets/js/plan_map.mjs, run by
// StatifierExamplesWeb.PlanMapLayoutTest and StatifierExamplesWeb.PlanLiveTest
// through Node.
//
//   node plan_map_layout.mjs <graph.json> [editable]
//
// Lays the graph out through the real elkjs and draws it with the hook's
// own drawMap/3, then prints one JSON object: what was drawn ("map" or
// "error"), the drawn markup, every box and edge of the SAME layout that
// markup was drawn from in absolute coordinates, and `gestures` - for every
// clickable element the markup carries, the event and payload the hook's
// own mapGesture/2 turns a click on it into - and `childGestures`, the same
// asked of a click on each of that element's children (the rect, text,
// circle or path a real click lands on), which reach the element by walking
// up exactly as a browser's `closest` does.
import {readFileSync} from "node:fs"
import {boxes, drawMap, edgesOf, mapGesture} from "../../../assets/js/plan_map.mjs"

const graph = JSON.parse(readFileSync(process.argv[2], "utf8"))
const editable = process.argv[3] === "editable"
const target = {innerHTML: ""}
const {drawn, laid} = await drawMap(target, graph, {editable})

const laidOut = {}
const edges = []
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
      sections: sections.length,
      start: sections.length ? sections[0].startPoint : null,
      end: sections.length ? sections[sections.length - 1].endPoint : null,
    })
  }
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

process.stdout.write(JSON.stringify({drawn, html: target.innerHTML, boxes: laidOut, edges, gestures, childGestures}))
