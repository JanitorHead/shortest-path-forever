-- A walk from a pier starts on its planks, not in the water below (#889): the water is the base surface at the
-- point's cell, and the planks are a floor six to eight yards above it.
local fixture = assert(loadfile("tests/nav_fixture.lua"))()
local ns = {}
for _, file in ipairs({ "Routing/PathGrid.lua", "Routing/Path.lua", "Routing/PathJobs.lua" }) do
	assert(loadfile(file))("ShortestPathForever", ns)
end
local Path = ns.Path
local TILE = 1600 / 3
local CS = TILE / 67
local MAP = 46

fixture.install(
	MAP,
	fixture.format3({
		map = MAP,
		nx = 1,
		ny = 1,
		cell = {
			[5] = {
				[10] = { z = 0, water = true },
				[11] = { z = 7 },
			},
		},
		-- The planks stand 7 yards over the water, stepping on to the quay in +y.
		floor = { { 5, 10, 7, 1, { [2] = 0 } } },
		node = { { 5, 10, 1 } },
	})
)
local from = { x = (5 + 0.5) * CS, y = (10 + 0.5) * CS }
local to = { x = (5 + 0.5) * CS, y = (11 + 0.5) * CS, z = 7 }
local points = assert(Path.FindSync(MAP, from, to))
assert(#points >= 2, "the walk must leave the pier")
assert(
	math.abs((points[2].z or -1) - 7) < 1e-6,
	"the start snaps to the planks, not the water: " .. tostring(points[2].z)
)
assert(points.wet < 1, "the start is on the dry planks: " .. tostring(points.wet))
print("pier_start_spec: ok")
