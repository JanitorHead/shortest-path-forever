local map, loaded, jobs = 1, {}, {}
local ns = {
	JourneySearch = {
		Walks = {},
		SamePlace = function(a, b)
			return a.map == b.map and a.x == b.x and a.y == b.y
		end,
	},
	PlanContext = {},
	db = {},
	JourneyPosition = function()
		return 0, 0, 0, map
	end,
	Planner = {
		WalkPoints = function(a, b)
			return { a, b }
		end,
	},
	Path = {
		HasData = function()
			return true
		end,
		IsLoaded = function(m)
			return loaded[m] == true
		end,
		Find = function(m, from, to, callback)
			local job = { map = m, from = from, to = to, callback = callback }
			jobs[#jobs + 1] = job
			return job
		end,
		Cancel = function() end,
	},
}
assert(loadfile("Journey/JourneyWalks.lua"))("ShortestPathForever", ns)
local Walks = ns.JourneySearch.Walks
local function plan(estimated)
	return {
		legs = {
			{
				mode = "walk",
				from = { map = 0, x = 1, y = 2 },
				to = { map = 0, x = 3, y = 4 },
				yards = 195,
				estimated = estimated,
			},
		},
	}
end
local distant = plan()
Walks.Prepare(distant, nil, false, function() end)
assert(#jobs == 0 and Walks.Pending() == 0, "exact distant geometry must not load a continent")
assert(distant.legs[1].yards == 195 and distant.legs[1].walkCost == 195)
assert(not distant.legs[1].walkError and not distant.legs[1].measured)
assert(not Walks.NeedsPrepare(distant))
map = 0
assert(Walks.NeedsPrepare(distant))
local arrived = distant
Walks.Prepare(arrived, nil, false, function() end)
assert(#jobs == 1 and jobs[1].map == 0, "geometry must be searched on arrival")
local points = { arrived.legs[1].from, arrived.legs[1].to, wet = 0 }
jobs[1].callback(points, 195, jobs[1])
assert(arrived.legs[1].measured and Walks.Pending() == 0)
Walks.Clear()
map = 1
local unproved = plan(true)
Walks.Prepare(unproved, nil, false, function() end)
assert(#jobs == 2, "estimated costs must still be proved even on another continent")
Walks.Cancel()
loaded[0] = true
Walks.Prepare(plan(), nil, false, function() end)
assert(#jobs == 3, "already loaded terrain should still refine distant geometry")
print("journey_walks_spec: ok")

-- A failed search never leaves its straight placeholder as the leg's points, and never caches it as a measured
-- walk: a later Prepare must not resurrect the line (#894).
do
	Walks.Clear()
	Walks.Cancel()
	map = 0
	local failed = plan()
	local before = #jobs
	Walks.Prepare(failed, nil, false, function() end)
	assert(#jobs == before + 1, "the walk is searched")
	jobs[#jobs].callback(nil, "offmesh", jobs[#jobs])
	local leg = failed.legs[1]
	assert(not leg.measured and leg.walkPlaceholder, "a failed walk is an unmeasured placeholder")
	assert(#leg.walkPoints == 0, "the failed search drops the straight line")
	assert(Walks.Pending() == 0)
	local again = plan()
	local searched = #jobs
	Walks.Prepare(again, nil, false, function() end)
	leg = again.legs[1]
	assert(#jobs == searched, "the failure is cached, not searched again")
	assert(not leg.measured and leg.walkPlaceholder, "the cached failure stays unmeasured")
	assert(#leg.walkPoints == 0, "the cache does not resurrect the straight line")
end
