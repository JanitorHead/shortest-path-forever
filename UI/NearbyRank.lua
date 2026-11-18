---@type string, SPFNamespace
local _, ns = ...

if ns.broken then
	return
end

-- One row's shortlist ranked by the planner's own journey cost, one Estimate per Step. The panel, the tracking menu and
-- /spfnear drain it inside a path job, whose estimates pause at the frame budget. The best starts as the straight-line
-- nearest, so a row always has an NPC, and stays so when no estimate can be made.
---@class SPFNearbyRank
---@field key? string
---@field candidates SPFNearbyPlace[]
---@field estimate SPFEstimate
---@field fromMap integer
---@field fromX number
---@field fromY number
---@field at integer
---@field best? SPFNearbyPlace
---@field seconds? number
---@field walks table<SPFNearbyPlace, number|false>
local Rank = {}
Rank.__index = Rank

function Rank:Step()
	local place = self.candidates[self.at]
	if not place then
		return self.best or self.candidates[1], self.seconds, false
	end
	self.at = self.at + 1
	local seconds = self.estimate(self.fromMap, self.fromX, self.fromY, place.map, place.x, place.y, self.walks[place])
	if seconds and (not self.seconds or seconds < self.seconds) then
		self.best, self.seconds = place, seconds
	end
	return self.best or self.candidates[1], self.seconds, self.at <= #self.candidates
end

---@param walks? table<SPFNearbyPlace, number|false> MeasureWalks' answer
local function NewRank(candidates, estimate, fromMap, fromX, fromY, walks)
	return setmetatable({
		candidates = candidates,
		walks = walks or {},
		estimate = estimate,
		fromMap = fromMap,
		fromX = fromX,
		fromY = fromY,
		at = 1,
	}, Rank)
end

-- The last finished measure: the panel asks again every tick, and while you stand on the same node its walks hold.
---@type { job: SPFPathJob, water: boolean, walks: table }?
local measured

-- The walks the journey would take from where you stand to each place: its own search, from its own start (your floor,
-- or your height band) to the spot it walks to (the NPC's own floor). An estimate built on them is the time the journey
-- shows; the straight line under a shop's walls is not (#1032). Calls back with each place's running yards, or false
-- where the search found no walk; a place it could not search is left out, and its estimate stays a lower bound.
---@param places SPFNearbyPlace[]
---@param callback fun(walks: table<SPFNearbyPlace, number|false>)
---@return SPFPathJob?
local function MeasureWalks(places, callback)
	local here = ns.JourneySearch.Here()
	if not (here and ns.Path.HasData(here.map)) then
		callback({})
		return nil
	end
	local water = ns.JourneyWaterWalking()
	if measured and measured.water == water and ns.Path.ReuseMany(measured.job, here) then
		local walks, known = {}, true
		for _, place in ipairs(places) do
			walks[place] = measured.walks[place]
			known = known and walks[place] ~= nil
		end
		if known then
			callback(walks)
			return nil
		end
	end
	local targets, of = {}, {}
	for _, place in ipairs(places) do
		local point = ns.WorldPoint(place.map, place.x, place.y)
		if point and point.map == here.map then
			targets[#targets + 1] = ns.OnSpawnFloor(point)
			of[#targets] = place
		end
	end
	if #targets == 0 then
		callback({})
		return nil
	end
	-- One batch walks to every place, so one profile: the zone you stand in is never charged, as a journey's start.
	local hazards = ns.Hazards.Profile(here, here)
	local job
	job = ns.Path.FindMany(here.map, here, targets, function(costs, reason)
		local walks = {}
		if not reason then
			for at, place in ipairs(of) do
				walks[place] = costs[at] or false
			end
			measured = { job = job, water = water, walks = walks }
		end
		callback(walks)
	end, water, false, nil, hazards)
	return job
end

---@alias SPFWalks table<SPFNearbyPlace, number|false> each place's measured walk; false where none was found
---@alias SPFMeasureWalks fun(places: SPFNearbyPlace[], callback: fun(walks: SPFWalks)): SPFPathJob?
---@class SPFNearbyRankAPI
---@field New SPFRank
---@field MeasureWalks SPFMeasureWalks
ns.NearbyRank = { New = NewRank, MeasureWalks = MeasureWalks }
