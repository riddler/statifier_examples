// Test driver for assets/js/plan_map.mjs, run by
// StatifierExamplesWeb.PlanMapLayoutTest through Node.
//
//   node plan_map_layout.mjs <graph.json>
//
// Lays the graph out through the real elkjs, draws it with the hook's own
// drawMap/2, and prints one JSON object: what was drawn ("map" or
// "error"), the drawn markup, and every laid-out box by id.
import {readFileSync} from "node:fs"
import {boxes, drawMap, layout} from "../../../assets/js/plan_map.mjs"

const graph = JSON.parse(readFileSync(process.argv[2], "utf8"))
const target = {innerHTML: ""}
const drawn = await drawMap(target, structuredClone(graph))

let laidOut = {}
if (drawn === "map") {
  const laid = await layout(structuredClone(graph))
  for (const box of boxes(laid)) {
    laidOut[box.id] = {x: box.x, y: box.y, width: box.width, height: box.height}
  }
}

process.stdout.write(JSON.stringify({drawn, html: target.innerHTML, boxes: laidOut}))
