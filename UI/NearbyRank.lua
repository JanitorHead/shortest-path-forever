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

-- Each place's walking end, on the NPC's own floor. Spawns do not move, and the height scan is the costly part of a
-- measure, so each place's is found once.
local spawns = setmetatable({}, { __mode = "k" })

---@param place SPFNearbyPlace
---@return SPFPoint|false
local function Spawn(place)
	local point = spawns[place]
	if point == nil then
		local world = ns.WorldPoint(place.map, place.x, place.y)
		point = world and ns.OnSpawnFloor(world) or false
		spawns[place] = point
	end
	return point
end

-- The last finished measures, one per hazard profile: the panel asks again every tick, and while you stand on the
-- same node with the same settings their walks hold.
---@type table<string, { job: SPFPathJob, water: boolean, walks: SPFWalks }>
local measured = {}

-- The places that walk under one hazard profile: the journey's own, which never charges the zone or town you start or
-- end in (Hazards.Profile), so places in different zones may need different profiles.
---@param here SPFPoint
---@param places SPFNearbyPlace[]
---@return table<string, { hazards: SPFHazards, targets: SPFPoint[], of: SPFNearbyPlace[] }>
local function Groups(here, places)
	local Context = ns.PlanContext
	local mass = Context.Landmass(here)
	local groups, profiles, seen = {}, {}, {}
	for _, place in ipairs(places) do
		-- A place on another landmass is no walk: the journey crosses by boat or flight, as its own batches assume.
		local point = not seen[place] and Spawn(place)
		seen[place] = true
		if point and point.map == here.map and Context.Landmass(point) == mass then
			local zone = ns.ZoneMap(point.map, point.x, point.y) or 0
			local hazards = profiles[zone]
			if not hazards then
				hazards = ns.Hazards.Profile(here, point, here)
				profiles[zone] = hazards
			end
			local group = groups[hazards.key]
			if not group then
				group = { hazards = hazards, targets = {}, of = {} }
				groups[hazards.key] = group
			end
			group.targets[#group.targets + 1] = point
			group.of[#group.targets] = place
		end
		ns.Path.Checkpoint()
	end
	return groups
end

-- The walks the journey would take from where you stand to each place: its own search, from its own start (your floor,
-- or your height band) to the spot it walks to (the NPC's own floor), under its own hazards. An estimate built on them
-- is the time the journey shows; the straight line under a shop's walls is not (#1032). Calls back with each place's
-- running yards, or false where the search found no walk; a place it could not search is left out, and its estimate
-- stays a lower bound. The work runs under the frame budget; Cancel stops all of it.
---@param places SPFNearbyPlace[]
---@param callback fun(walks: SPFWalks)
---@return SPFPathJob?
local function MeasureWalks(places, callback)
	local here = ns.JourneySearch.Here()
	if not (here and ns.Path.HasData(here.map)) then
		callback({})
		return nil
	end
	local water = ns.JourneyWaterWalking()
	local handle
	handle = ns.Path.Run(function()
		return Groups(here, places)
	end, function(groups)
		local walks, pending, last = {}, 1, measured
		measured = {}
		local function Settled()
			pending = pending - 1
			if pending == 0 then
				callback(walks)
			end
		end
		for key, group in pairs(groups) do
			local kept = last[key]
			local known = kept and kept.water == water and ns.Path.ReuseMany(kept.job, here)
			for _, place in ipairs(known and group.of or {}) do
				known = known and kept.walks[place] ~= nil
			end
			if known then
				measured[key] = kept
				for _, place in ipairs(group.of) do
					walks[place] = kept.walks[place]
				end
			else
				pending = pending + 1
				local job
				job = ns.Path.FindMany(here.map, here, group.targets, function(costs, reason)
					handle.walking[job] = nil
					if not reason then
						local found = {}
						for at, place in ipairs(group.of) do
							found[place] = costs[at] or false
							walks[place] = found[place]
						end
						measured[key] = { job = job, water = water, walks = found }
					end
					Settled()
				end, water, false, nil, group.hazards)
				handle.walking[job] = true
			end
		end
		Settled()
	end)
	handle.walking = {}
	return handle
end

-- Stops a measure, with the walking searches it started, or a ranking.
---@param job SPFPathJob
local function Cancel(job)
	ns.Path.Cancel(job)
	for walking in pairs(job.walking or {}) do
		ns.Path.Cancel(walking)
	end
end

---@alias SPFWalks table<SPFNearbyPlace, number|false> each place's measured walk; false where none was found
---@alias SPFMeasureWalks fun(places: SPFNearbyPlace[], callback: fun(walks: SPFWalks)): SPFPathJob?
---@class SPFNearbyRankAPI
---@field New SPFRank
---@field MeasureWalks SPFMeasureWalks
---@field Cancel fun(job: SPFPathJob)
ns.NearbyRank = { New = NewRank, MeasureWalks = MeasureWalks, Cancel = Cancel }
