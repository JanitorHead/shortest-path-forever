-- Search adjacency must expose the plain-pruned graph unless Follow roads is enabled.
local fixture = assert(loadfile("tests/nav_fixture.lua"))()
fixture.install(
	44,
	fixture.format3({
		nx = 1,
		ny = 1,
		degreeWidth = 2,
		baseDegreeWidth = 2,
		cell = { [1] = { [1] = { z = 0 } }, [2] = { [1] = { z = 0 } }, [3] = { [1] = { z = 0 } } },
		node = {
			{ 1, 1, 1, base = 1, out = { { 2, 1, 10, 11 }, { 3, 1, 20, 21 } } },
			{ 2, 1, 1, base = 0, out = { { 3, 1, 30, 31 } } },
			{ 3, 1, 1, base = 1, out = { { 1, 1, 40, 41 } } },
		},
	})
)
local ns = {}
assert(loadfile("Routing/PathGrid.lua"))("ShortestPathForever", ns)
local Grid = ns.PathGrid
local st = assert(Grid.State(44))
local ids = Grid.nodesOf(st, 0)
assert(#Grid.adjacent(st, ids[1], true) == 6, "road adjacency can be decoded before the base prefix")
for _, roads in ipairs({ false, true, false }) do
	local out = Grid.adjacent(st, ids[1], roads)
	assert(#out == (roads and 6 or 3), "forward search must omit road-only edges when roads are off")
	assert(out[1] == ids[2] and out[2] == 10 and out[3] == 11, "base edge retains its physical costs")
	local into = Grid.preceding(st, ids[3], roads)
	assert(#into == (roads and 6 or 0), "reverse search must omit road-only edges when roads are off")
	assert(#Grid.adjacent(st, ids[2], roads) == (roads and 3 or 0), "zero base degree is an empty prefix")
	local cell = Grid.metadata(st, ids[3])
	assert(cell == 3 * 67 + 1, "metadata skips the base count")
end
print("nav_base_edges_spec: ok")
