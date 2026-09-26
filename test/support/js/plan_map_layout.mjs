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
// own mapGesture/2 turns a click on it into.
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

// A stand-in for the element a click lands on: one drawn `<g>`, its data
// attributes as `dataset`, and a `closest` that answers the three selectors
// mapGesture asks. The markup is the hook's own, so what is read here is
// what a browser would hand the click handler.
const unescape = (v) => v.replace(/&quot;/g, "\"").replace(/&#39;/g, "'")
  .replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&amp;/g, "&")
const camel = (name) => name.replace(/-([a-z])/g, (_m, c) => c.toUpperCase())

function element(tag) {
  const dataset = {}
  for (const [, name, value] of tag.matchAll(/data-([a-z-]+)="([^"]*)"/g)) {
    dataset[camel(name)] = unescape(value)
  }
  const matches = (selector) =>
    (selector === "[data-map-gap]" && dataset.mapGap !== undefined) ||
    (selector === "[data-map-kind=empty]" && dataset.mapKind === "empty") ||
    (selector === "[data-map-kind=block]" && dataset.mapKind === "block")
  return {dataset, closest: (selector) => (matches(selector) ? element(tag) : null)}
}

const gestures = []
for (const [tag] of target.innerHTML.matchAll(/<g [^>]*>/g)) {
  const el = element(tag)
  if (el.dataset.mapGap === undefined && el.dataset.mapKind === undefined) continue
  gestures.push({
    element: el.dataset.mapGap !== undefined ? `gap:${el.dataset.mapGap}` : `${el.dataset.mapKind}:${el.dataset.mapNode}`,
    gesture: mapGesture(el, editable),
  })
}

process.stdout.write(JSON.stringify({drawn, html: target.innerHTML, boxes: laidOut, edges, gestures}))
