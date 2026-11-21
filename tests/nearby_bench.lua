-- Nearby bench: real Eastern Kingdoms nav, rows of real trainers and flight masters, ranked as the panel does.
local driver = assert(loadfile("tests/journey_driver.lua"))()
local ns = driver.ns
for _, f in ipairs({
	"Data/Routes.lua",
	"Data/Transports.lua",
	"Data/Taxi.lua",
	"Data/Portals.lua",
	"Data/Walks.lua",
	"Data/TownAreas.lua",
	"Data/Heights.lua",
	"Data/IdleSpawns.lua",
	"Data/Services.lua",
	"Routing/PathGrid.lua",
	"Routing/Path.lua",
	"Routing/PathJobs.lua",
}) do
	driver.load(f)
end
assert(loadfile("tools/load_nav.lua"))(0)
driver.load("Core/APIInput.lua")
driver.load("Core/API.lua")
driver.env._G = driver.env
local project = driver.env.C_Map.GetWorldPosFromMapPos
driver.env.C_Map.GetWorldPosFromMapPos = function(map, point)
	local _, world = project(map, point)
	return 0, world
end
driver.env.C_Timer = { After = function() end }
for _, f in ipairs({
	"UI/MenuModifier.lua",
	"UI/NearbyGroups.lua",
	"UI/NearbyQuestie.lua",
	"UI/NearbyEntrances.lua",
	"UI/NearbyRoles.lua",
	"UI/NearbyProfessions.lua",
	"UI/NearbyRank.lua",
	"UI/Nearby.lua",
}) do
	driver.load(f)
end
local nextFrame
ns.Path.after = function(fn)
	nextFrame = fn
end
ns.faction, ns.water, ns.speed, ns.known = "Alliance", false, 7, {}
for id in pairs(ns.TaxiNodes) do
	ns.known[id] = true
end
ns.teleports, ns.teleportReady = {}, {}
driver.load("Routing/Floor.lua")

local function ui(x, y)
	return 0.5 - y / 50000, 0.5 - x / 50000
end
local rows = {}
local function add(key, id, x, y)
	rows[key] = rows[key] or {}
	local p = { map = 1453, id = id, name = key .. id, world = { map = 0, x = x, y = y } }
	p.x, p.y = ui(x, y)
	table.insert(rows[key], p)
end
local spawns = ns.IdleSpawns[0]
for _, tbl in ipairs({ { "class", ns.ClassTrainers }, { "prof", ns.ProfessionTrainers } }) do
	for npc, what in pairs(tbl[2]) do
		local s = spawns[npc]
		if s then
			local x, y = s:match("^(%S+) (%S+)")
			add(tbl[1] .. tostring(what), npc, tonumber(x), tonumber(y))
		end
	end
end
for id, node in pairs(ns.TaxiNodes) do
	if node.map == 0 then
		add("flight", id, node.x, node.y)
	end
end

local function shortlist(list, at)
	table.sort(list, function(a, b)
		local da = (a.world.x - at.x) ^ 2 + (a.world.y - at.y) ^ 2
		local db = (b.world.x - at.x) ^ 2 + (b.world.y - at.y) ^ 2
		return da < db or da == db and a.id < b.id
	end)
	local out = {}
	for i = 1, math.min(5, #list) do
		out[i] = list[i]
	end
	return out
end

local LIMIT = 60 * 600
local function drain(stop)
	local frames = 0
	while nextFrame and frames < LIMIT do
		local fn = nextFrame
		nextFrame = nil
		fn()
		frames = frames + 1
		if stop and stop() then
			break
		end
	end
	return frames
end

-- The panel's Queue and RankRows, as on main.
local NORANK = os.getenv("NORANK")
local function Queue(at)
	local queue, places = {}, {}
	for key, list in pairs(rows) do
		local c = shortlist(list, at)
		queue[#queue + 1] = { key = key, candidates = c }
		for _, p in ipairs(c) do
			places[#places + 1] = p
		end
	end
	local mx, my = ui(at.x, at.y)
	local painted, decided, frame, done = 0, 0, 0, nil
	local first = {}
	local ranking, latest, again
	local function Rank()
		if ranking then
			again = true
			return
		end
		local walks, pending = latest.walks, latest.pending
		ranking = ns.Path.Run(function(job)
			local function est(...)
				return ns.EstimateIn(job, ...)
			end
			for _, item in ipairs(queue) do
				if not item.decided then
					local rank = ns.NearbyServices.Rank(item.candidates, est, 1453, mx, my, walks, pending)
					repeat
						local _, _, more = rank:Step()
					until not more
					item.decided = rank.exact or not pending
					if item.decided and not first[item.key] then
						first[item.key] = frame
					end
				end
			end
		end, function()
			ranking = nil
			if again then
				again = false
				Rank()
			end
		end)
	end
	local job = ns.NearbyServices.MeasureWalks(places, function(walks, pending)
		latest = { walks = walks, pending = pending }
		if not pending then
			done = frame
		end
		if not NORANK then
			Rank()
		end
	end)
	local total = drain(function()
		frame = frame + 1
		return false
	end)
	local n, last, firstAny = 0, 0, nil
	for _, f in pairs(first) do
		n = n + 1
		last = math.max(last, f)
		firstAny = math.min(firstAny or f, f)
	end
	return {
		rows = #queue,
		places = #places,
		decidedRows = n,
		firstRow = firstAny,
		allRows = last,
		measured = done,
		frames = total,
	}
end

local here = { map = 0, x = -8832.076, y = 595.038 }
local steps = { here, { map = 0, x = here.x + 5, y = here.y }, { map = 0, x = here.x + 10, y = here.y + 3 } }
for i, at in ipairs(steps) do
	driver.move(at)
	ns.Floor.Sample(0, at.x, at.y)
	drain()
	local t0 = os.clock()
	local r = Queue(at)
	print(
		string.format(
			"%s rows=%d places=%d decided=%d first=%s all=%s measured=%s frames=%d (%.1fs @60Hz) cpu=%.2fs budget=%s",
			i == 1 and "reload" or ("move" .. (i - 1)),
			r.rows,
			r.places,
			r.decidedRows,
			tostring(r.firstRow),
			tostring(r.allRows),
			tostring(r.measured),
			r.frames,
			r.frames / 60,
			os.clock() - t0,
			tostring(ns.Path.budget)
		)
	)
end
