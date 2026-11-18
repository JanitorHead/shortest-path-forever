-- options.withoutOpening bars one step of an offered route, where it leaves, so the journey can ask whether anything
-- beats the offer without the step it cannot take back (#1032). A walk to a flight master and a connecting flight are
-- the cases a first-step match misses: the flight is not the first leg, and its one leg ends past its first hop.
local ns = {}
assert(loadfile("Locales/enUS.lua"))("ShortestPathForever", ns)
assert(loadfile("Transport/Model.lua"))("ShortestPathForever", ns)
assert(loadfile("Routing/Savings.lua"))("ShortestPathForever", ns)
assert(loadfile("Routing/Planner.lua"))("ShortestPathForever", ns)

local function point(x)
	return { map = 1, x = x, y = 0 }
end

-- Start --walk--> 1 --flight--> 2 --flight--> 3 --walk--> goal, far quicker than the walk straight there.
local function Fixture()
	return {
		from = point(0),
		to = point(10100),
		now = 0,
		walkSpeed = 7,
		faction = "Alliance",
		taxiNodes = { [1] = point(1000), [2] = point(5000), [3] = point(10000) },
		taxiPaths = {
			{ from = 1, to = 2, seconds = 10 },
			{ from = 2, to = 3, seconds = 10 },
		},
		taxiKnown = { [1] = true, [2] = true, [3] = true },
		exactMaps = { [1] = true },
		walks = {
			{ from = point(0), to = point(1000), cost = 1000 },
			{ from = point(0), to = point(10100), cost = 10100 },
			{ from = point(10000), to = point(10100), cost = 100 },
		},
	}
end

local offered = assert(ns.Planner.Plan(Fixture()))
local flight
for _, leg in ipairs(offered.legs) do
	if leg.mode == "flight" then
		flight = leg
	end
end
assert(offered.legs[1].mode == "walk" and flight, "the offer walks to the master, then flies")
assert(flight.to.x == 10000 and #flight.hops == 2, "the connecting flight is one leg of two hops")

local options = Fixture()
options.withoutOpening = flight
local without = assert(ns.Planner.Plan(options))
for _, leg in ipairs(without.legs) do
	assert(leg.mode ~= "flight", "without the flight, no flight leaves its master, not even its first hop")
end
assert(without.arrive > offered.arrive, "the plan without the flight is the slower walk")
print("planner_without_opening_spec: ok")
