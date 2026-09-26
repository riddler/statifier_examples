// Test driver for assets/js/plan_map.mjs, run by
// StatifierExamplesWeb.PlanMapLayoutTest through Node.
//
//   node plan_map_layout.mjs <graph.json>
//
// Lays the graph out through the real elkjs and draws it with the hook's
// own drawMap/3, then prints one JSON object: what was drawn ("map" or
// "error"), the drawn markup, and every box and edge of the SAME layout
// that markup was drawn from, in absolute coordinates.
import {readFileSync} from "node:fs"
import {boxes, drawMap, edgesOf} from "../../../assets/js/plan_map.mjs"

const graph = JSON.parse(readFileSync(process.argv[2], "utf8"))
const target = {innerHTML: ""}
const {drawn, laid} = await drawMap(target, graph)

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

process.stdout.write(JSON.stringify({drawn, html: target.innerHTML, boxes: laidOut, edges}))
