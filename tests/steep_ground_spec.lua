-- A step whose stored heights climb more than the client's 50 degree limit is refused even when the bake left the
-- steep flag off the face (#897): the plain grid's search and the abstract graph's cluster-to-cluster links.
local fixture = assert(loadfile("tests/nav_fixture.lua"))()
local ns = {}
for _, file in ipairs({ "Routing/PathGrid.lua", "Routing/Path.lua", "Routing/PathJobs.lua" }) do
	assert(loadfile(file))("ShortestPathForever", ns)
end
local Path, Grid = ns.Path, ns.PathGrid
local TILE = 1600 / 3
local CS = TILE / 67

local function point(gx, gy, z)
	return { x = (gx + 0.5) * CS, y = (gy + 0.5) * CS, z = z }
end

-- Inside one cluster, two ordinary ground cells 20 yards apart with no steep flag: the decoder used to let the
-- search walk up the face because only the missing flag marked it.
fixture.install(
	43,
	fixture.format2({
		map = 43,
		nx = 1,
		ny = 1,
		cell = {
			[10] = { [10] = { z = 10 }, [11] = { z = 30 } },
		},
		node = { { 10, 10, 1 } },
	})
)
local walk, why = Path.FindSync(43, point(10, 10, 10), point(10, 11, 30))
assert(walk == nil and why == "unreachable", "the plain grid must refuse a 20 yard climb in 8 yards")
assert(Path.FindSync(43, point(10, 11, 30), point(10, 10, 10)), "and still walk it downhill")

-- Across two clusters, the breadcrumb edge is one ordinary cell step too: its stored ends must clear the same
-- limit before the abstract search takes it.
local edge = math.floor(CS)
fixture.install(
	44,
	fixture.format2({
		map = 44,
		nx = 2,
		ny = 1,
		cell = {
			[66] = { [10] = { z = 10 } },
			[67] = { [10] = { z = 30 } },
		},
		node = {
			{ 66, 10, 1, out = { { 67, 10, edge, edge } } },
			{ 67, 10, 1, out = { { 66, 10, edge, edge } } },
		},
	})
)
walk, why = Path.FindSync(44, point(66, 10, 10), point(67, 10, 30))
assert(walk == nil and why == "unreachable", "the abstract edge must refuse the climb too")
assert(Path.FindSync(44, point(67, 10, 30), point(66, 10, 10)), "and still walk it downhill")

-- A reverse batch walks the stored edge the other way, so its climb test must face the direction it travels.
local function many(from, to, reverse)
	return Path.FindManySync(44, from, { to }, nil, reverse)[1]
end
assert(many(point(66, 10, 10), point(67, 10, 30), true) ~= false, "a reverse batch walks the face down")
assert(many(point(67, 10, 30), point(66, 10, 10), true) == false, "a reverse batch must not climb it")

-- The rule reads stored heights, not the map's steep flag: neither fixture set it.
assert(not Grid.State(43).D.steep and not Grid.State(44).D.steep)
print("steep_ground_spec: ok")
