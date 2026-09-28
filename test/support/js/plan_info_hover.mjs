// Test driver for assets/js/plan_info.mjs, run by
// StatifierExamplesWeb.PlanInfoHoverTest through Node.
//
//   node plan_info_hover.mjs <page.json>
//
// `page.json` is what the Plan page rendered: `graph`, the map's graph as
// the page hands it to the map hook; `region`, the description region's
// inner markup; and `entries`, the hidden store's entries as
// `{id, html}`; and, optionally, `patched`, the region's inner markup
// after a later patch (a row selected once the page is up). The driver draws the map with the map hook's own drawMap/3
// through the real elkjs, mounts the real PlanInfo hook over a small
// document (the region, the store, and listeners it records), and then
// points at every element the drawing carries, and at every child of each
// (the rect, text, circle or path a real pointer lands on), each time
// followed by a pointer over nothing the map draws.
//
// It prints one JSON object:
//
// - `hovers`: for every element pointed at, the id it resolved to, whether
//   the region then held exactly that id's stored entry and was marked with
//   it, and whether the pointer moving off put the region back byte for
//   byte;
// - `missing`: every drawn id the store has no entry for;
// - `chained`: pointing at one element and then straight at another shows
//   the second, and moving off then restores the region's first content,
//   not the first element's;
// - `outOfWindow`: a pointer leaving the window restores the region;
// - `gaps`: a gap's "+" describes nothing, and pointing at one restores;
// - `stale`: after a patch redraws the region mid-hover (the mark gone),
//   moving off leaves the patched content in place;
// - `pushes`: every event the hook pushed to the server;
// - `listening`: how many listeners the hook left on the document after
//   `destroyed()`.
import {readFileSync} from "node:fs"
import {drawMap} from "../../../assets/js/plan_map.mjs"
import {PlanInfo} from "../../../assets/js/plan_info.mjs"

const page = JSON.parse(readFileSync(process.argv[2], "utf8"))
const target = {innerHTML: ""}
const {drawn} = await drawMap(target, page.graph, {editable: true})
if (drawn !== "map") throw new Error(`the map did not draw: ${target.innerHTML}`)

// A small element tree over the drawn markup: every tag with its data
// attributes as `dataset`, its parent, and a `closest` that walks from the
// element up through its ancestors, as the DOM's does, matching attribute
// selectors (`[name]` and `[name=value]`).
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
  for (const [, closing, tag, attrs, selfClosing] of
    markup.matchAll(/<(\/?)([a-zA-Z]+)([^>]*?)(\/?)>/g)) {
    if (closing) {
      current = current.parent || root
      continue
    }
    const dataset = {}
    for (const [, name, value] of attrs.matchAll(/data-([a-z-]+)="([^"]*)"/g)) {
      dataset[camel(name)] = unescape(value)
    }
    const el = {tag, dataset, parent: current, children: []}
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
const svg = all.find((el) => el.tag === "svg")

// The page: the region, the store, and a document that records listeners.
let resting = page.region
const region = {innerHTML: resting, dataset: {}}
const store = {
  children: page.entries.map((entry) => ({dataset: {describes: entry.id}, innerHTML: entry.html})),
}
const html = new Map(page.entries.map((entry) => [entry.id, entry.html]))
const listeners = {}
const doc = {
  getElementById: (id) => ({"plan-description": region, "plan-descriptions": store})[id] || null,
  addEventListener: (type, fn) => { (listeners[type] ||= []).push(fn) },
  removeEventListener: (type, fn) => {
    listeners[type] = (listeners[type] || []).filter((f) => f !== fn)
  },
}
const fire = (type, event) => { for (const fn of listeners[type] || []) fn(event) }
const over = (el) => fire("mouseover", {target: el, relatedTarget: null})

const pushes = []
const hook = {
  el: {dataset: {region: "plan-description", store: "plan-descriptions"}, ownerDocument: doc},
  pushEvent: (...args) => pushes.push(args),
  pushEventTo: (...args) => pushes.push(args),
}
PlanInfo.mounted.call(hook)

// A patch after mount redraws the region; that is what a hover must then
// put back.
if (page.patched !== undefined) {
  region.innerHTML = page.patched
  resting = page.patched
}

// Every drawn element the map gives an id: a group carrying data-map-node,
// or a path carrying data-map-edge.
const drawnEls = all.filter((el) =>
  (el.tag === "g" && el.dataset.mapNode !== undefined) || el.dataset.mapEdge !== undefined)
const idOf = (el) => el.dataset.mapNode ?? el.dataset.mapEdge

const hovers = []
const point = (el, element, child) => {
  over(el)
  const id = region.dataset.planHover ?? null
  const shown = id !== null && region.innerHTML === html.get(id)
  over(svg)
  hovers.push({element, child, id, shown, restored: region.innerHTML === resting &&
    region.dataset.planHover === undefined})
}

for (const el of drawnEls) {
  point(el, idOf(el), null)
  for (const child of el.children) point(child, idOf(el), child.tag)
}

const missing = [...new Set(drawnEls.map(idOf))].filter((id) => !html.has(id))

// One element, then straight at another, then off.
const [first, second] = drawnEls
over(first)
over(second)
const chainedShown = region.dataset.planHover === idOf(second) &&
  region.innerHTML === html.get(idOf(second))
over(svg)
const chained = chainedShown && region.innerHTML === resting

// The pointer leaves the window.
over(first)
fire("mouseout", {target: first, relatedTarget: null})
const outOfWindow = region.innerHTML === resting && region.dataset.planHover === undefined

// A gap's "+" and whatever is inside it.
const gapEls = all.filter((el) => el.dataset.mapGap !== undefined)
const gaps = gapEls.length > 0 && gapEls.every((gap) => {
  over(first)
  over(gap.children[0] || gap)
  return region.innerHTML === resting && region.dataset.planHover === undefined
})

// A patch mid-hover: the server's content is back and the mark is gone.
over(first)
region.innerHTML = "<p>patched</p>"
delete region.dataset.planHover
over(svg)
const stale = region.innerHTML === "<p>patched</p>"
region.innerHTML = resting

PlanInfo.destroyed.call(hook)
const listening = Object.values(listeners).reduce((n, fns) => n + fns.length, 0)

process.stdout.write(JSON.stringify({hovers, missing, chained, outOfWindow, gaps, stale, pushes, listening}))
