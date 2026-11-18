-- A finished search's callback replans synchronously (JourneySearch's consider, two Planner.Plan calls),
-- and a plan never yields (#717). Running that callback in the same pump frame as the search slice that
-- settled it stacks the plan on the 2 ms slice and breaks the 3 ms frame ceiling, so a completion
-- callback waits for the next frame once its pump has searched. Progress callbacks still run in-frame.
local ns = {}
assert(loadfile("Locales/enUS.lua"))("ShortestPathForever", ns)
assert(loadfile("Transport/Model.lua"))("ShortestPathForever", ns)
assert(loadfile("tools/load_nav.lua"))(0)
for _, file in ipairs({
	"Routing/PathGrid.lua",
	"Routing/Path.lua",
	"Routing/PathJobs.lua",
	"Routing/Savings.lua",
	"Routing/Planner.lua",
}) do
	assert(loadfile(file))("ShortestPathForever", ns)
end
local Path = ns.Path

local frames = {}
Path.after = function(fn)
	frames[#frames + 1] = fn
end
local now = 0
Path.clock = function()
	now = now + 1
	return now
end
-- A wide budget, so the search finishes with frame to spare: the stacking case, where the old pump
-- ran the callback in the same frame and the plan landed on top of the slice.
Path.budget = 1000000000
rawset(_G, "geterrorhandler", function()
	return function() end
end)

local pumpCount, callbackPump, donePump = 0, nil, nil
local answered = false
local job = Path.Find(0, { x = -9459, y = 43 }, { x = -8840.56, y = 489.7 }, function(points)
	if points then
		callbackPump, answered = pumpCount, true
	end
end)
while #frames > 0 do
	pumpCount = pumpCount + 1
	table.remove(frames, 1)()
	if job.done and not donePump then
		donePump = pumpCount
	end
	assert(pumpCount < 20000, "the search did not settle")
end
assert(answered, "the callback received its walk")
assert(
	callbackPump and donePump and callbackPump > donePump,
	"completion callback shared the frame that finished its search"
)

print("path job schedule: completion callback waits a frame after its search: ok")
