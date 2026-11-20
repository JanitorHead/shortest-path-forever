-- #1155: a character whose flight points predate the addon flew nowhere until it opened a flight master's map
-- (#1064). At login the world map's query names the points it has (isUndiscovered false), and a continent with no
-- point learned takes them from there. A continent already learned at a flight master keeps that scan's list.
local fixture = assert(loadfile("tests/fixtures/taxi_stormwind_1463.lua"))()

local ns = {
	db = { taxiRoute = false },
	SetJourneyRoute = function() end,
	JourneyChanged = function() end,
}
ns.Init = function(fn)
	fn()
end
assert(loadfile("Data/Taxi.lua"))("ShortestPathForever", ns)

local KNOWN = { [2] = true, [4] = true, [6] = true, [7] = true, [8] = true }
local reports = {}
-- Eastern Kingdoms as the recorded Stormwind scan has it: the five points the character flew from are known.
reports[1415] = {}
for _, entry in ipairs(fixture.slots) do
	if ns.TaxiNodes[entry.nodeID] and ns.TaxiNodes[entry.nodeID].map == 0 then
		reports[1415][#reports[1415] + 1] =
			{ nodeID = entry.nodeID, name = entry.name, isUndiscovered = not KNOWN[entry.nodeID] }
	end
end
-- The Horde's Undercity reported as known must not become an Alliance flight point.
reports[1415][#reports[1415] + 1] = { nodeID = 11, name = "Undercity", isUndiscovered = false }
-- Kalimdor: Rut'theran (27) known on the map, but the character already learned Auberdine (26) at a flight master.
reports[1414] = {
	{ nodeID = 26, name = "Auberdine", isUndiscovered = false },
	{ nodeID = 27, name = "Rut'theran Village", isUndiscovered = false },
}

local eventFrame
local frame = {}
frame.__index = frame
function frame:RegisterEvent(event)
	self.events[event] = true
end
function frame:SetScript(_, fn)
	self.onEvent = fn
end

local policyChanges = 0
ns.TravelPolicyChanged = function()
	policyChanges = policyChanges + 1
end

local function Load(saved, query)
	eventFrame = nil
	local env = setmetatable({
		UnitFactionGroup = function()
			return "Alliance"
		end,
		C_TaxiMap = { GetTaxiNodesForMap = query },
		CreateFrame = function()
			eventFrame = setmetatable({ events = {} }, frame)
			return eventFrame
		end,
		hooksecurefunc = function() end,
		ShortestPathForeverCharDB = { taxi = saved, taxiNames = {} },
	}, { __index = _G })
	env._G = env
	setfenv(assert(loadfile("Transport/Taxi.lua")), env)("ShortestPathForever", ns)
	assert(eventFrame.events.PLAYER_ENTERING_WORLD, "the seed runs when the character enters the world")
	eventFrame.onEvent(eventFrame, "PLAYER_ENTERING_WORLD")
	return ns.KnownTaxiNodes()
end

local function Sorted(set)
	local list = {}
	for id in pairs(set) do
		list[#list + 1] = id
	end
	table.sort(list)
	return table.concat(list, ",")
end

local known = Load({ [26] = true }, function(uiMap)
	return reports[uiMap]
end)
assert(
	Sorted(known) == "2,4,6,7,8,26",
	"Eastern Kingdoms takes its five known points; Kalimdor keeps its scan: " .. Sorted(known)
)
assert(ns.charDB.taxiNames[2] == "Stormwind", "a seeded point keeps the client's name")
assert(policyChanges == 1, "seeding replans once")

-- A client that leaves isUndiscovered unset (as GetAllTaxiNodes does at a flight master) seeds nothing.
policyChanges = 0
known = Load({}, function(uiMap)
	local unset = {}
	for _, info in ipairs(reports[uiMap]) do
		unset[#unset + 1] = { nodeID = info.nodeID, name = info.name }
	end
	return unset
end)
assert(next(known) == nil and policyChanges == 0, "no answer from the client is no known point")

print("taxi login seed: known points come from the world map where no flight master taught them: ok")
