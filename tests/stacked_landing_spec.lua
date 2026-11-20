-- A lift's landings share a spot on the map, one above the other (#1059). The nearest dock must be the landing you
-- are at, from your followed floor, the range checks' height band, or the floor you walked onto the landing on, and
-- only with none of them known the lowest dock ID, as before.
local ForeverCore = dofile("tests/forever_core.lua")
local env = setmetatable({
	ShortestPathForeverDB = {},
	SlashCmdList = {},
	C_Timer = {
		NewTicker = function()
			return { Cancel = function() end }
		end,
	},
	CreateFrame = function()
		local frame = { RegisterEvent = function() end, RegisterUnitEvent = function() end }
		frame.UnregisterEvent = frame.RegisterEvent
		frame.SetScript = function() end
		return frame
	end,
}, { __index = _G })
ForeverCore.load(env, "ForeverCore")
local ns = { Docks = {}, Routes = {} }
for _, file in ipairs({ "Locales/enUS.lua", "Data/Transports.lua", "Transport/Model.lua", "Core/Core.lua" }) do
	setfenv(assert(loadfile(file)), env)("ShortestPathForever", ns)
end
local TOP, BOTTOM = 1005, 1006 -- Thunder Bluff, west lift
local top, bottom = ns.Docks[TOP], ns.Docks[BOTTOM]
assert(top.x == bottom.x and top.y == bottom.y and top.z > bottom.z, "the landings stack")

local at = { x = top.x + 3, y = top.y, map = top.map }
ns.JourneyPosition = function()
	return at.x, at.y, nil, at.map
end
local height, landed, band
ns.Floor = {
	Height = function()
		return height
	end,
	Landed = function()
		return landed
	end,
}
ns.Band = {
	Measure = function()
		return band
	end,
	Holds = function(b, z)
		return z >= b.lo and z <= b.hi
	end,
}
local function nearest()
	local id, yards = ns.NearestDock()
	assert(yards and math.abs(yards - 3) < 0.01, "the yards are the map distance: " .. tostring(yards))
	return id
end

assert(nearest() == TOP, "with no height known the lowest ID stands")
landed = bottom.z + 1
assert(nearest() == BOTTOM, "walked onto the bottom landing, it is the bottom")
landed = top.z
assert(nearest() == TOP, "and onto the top, the top")
band = { lo = bottom.z - 10, hi = bottom.z + 10 }
assert(nearest() == BOTTOM, "a band that holds one landing names it, whatever you walked in on")
band = { lo = bottom.z - 10, hi = top.z + 10 }
assert(nearest() == TOP, "a band that holds both leaves the floor you walked in on")
landed = nil
assert(nearest() == TOP, "and with that unknown too, the lowest ID")
height = bottom.z + 0.5
assert(nearest() == BOTTOM, "a followed floor names the landing")
-- The same spot asked again after a ride: the landing is weighed afresh, not cached with the position.
height, band = top.z, nil
assert(nearest() == TOP, "a ride changes the landing without moving you on the map")

-- Every stacked pair in the data resolves both ways.
local pairs_ = 0
for id, dock in pairs(ns.Docks) do
	for other, o in pairs(ns.Docks) do
		if id < other and o.map == dock.map and o.x == dock.x and o.y == dock.y then
			pairs_ = pairs_ + 1
			at = { x = dock.x + 3, y = dock.y, map = dock.map }
			band = nil
			for _, want in ipairs({ id, other }) do
				height = ns.Docks[want].z
				assert(nearest() == want, ("dock %d at its own height"):format(want))
			end
		end
	end
end
assert(pairs_ >= 7, "the lifts of Thunder Bluff, the Undercity, the Great Lift and Freewind Post: " .. pairs_)
print("stacked_landing_spec: the nearest dock is the landing you are at")
