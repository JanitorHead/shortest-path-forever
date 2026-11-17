-- Road-safe pruning can retain more than 63 neighbours. Wide degrees must preserve node offsets and both directions.
local fixture = assert(loadfile("tests/nav_fixture.lua"))()
local cells, nodes, edges = {}, {}, {}
for x = 0, 65 do
	cells[x] = { [1] = { z = 0 } }
	nodes[#nodes + 1] = { x, 1, 1 }
	if x > 0 then
		edges[#edges + 1] = { x, 1, x + 10, x + 5 }
	end
end
nodes[1].out = edges
fixture.install(43, fixture.format3({ nx = 1, ny = 1, cell = cells, node = nodes, degreeWidth = 2 }))
local ns = {}
assert(loadfile("Routing/PathGrid.lua"))("ShortestPathForever", ns)
local Grid = ns.PathGrid
local st = assert(Grid.State(43))
local ids = Grid.nodesOf(st, 0)
assert(#ids == 66, "wide degrees preserve every node")
local adjacent = Grid.adjacent(st, ids[1])
assert(#adjacent == 65 * 3, "wide degrees preserve every outgoing edge")
local cell, layer, component = Grid.metadata(st, ids[66])
assert(cell == 65 * 67 + 1 and layer == 0 and component == 1, "metadata uses the wide node stride")
local preceding = Grid.preceding(st, ids[66])
assert(#preceding == 3 and preceding[1] == ids[1], "reverse search reads the same wide degrees")
assert(preceding[2] == 75 and preceding[3] == 70, "reverse search preserves the last edge's costs")
print("nav_degree_spec: ok")
