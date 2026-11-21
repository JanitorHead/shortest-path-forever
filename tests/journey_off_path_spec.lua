local function OffPathSearches(tolerance)
	local driver = assert(loadfile("tests/journey_driver.lua"))()
	local path = driver.path
	driver.ns.db.offPathTolerance = tolerance or driver.ns.db.offPathTolerance
	driver.begin({ map = 1, x = 0, y = 0 }, { map = 1, x = 1000, y = 0 })
	local leg = driver.shown().legs[1]
	assert(leg.mode == "walk" and leg.measured, "the initial walk is measured")
	local before = #path.batches
	driver.move({ map = 1, x = 50, y = 30 })
	driver.update(5)
	return #path.batches - before
end

assert(OffPathSearches() == 1, "a 30-yard detour starts a new search at the default tolerance")
assert(OffPathSearches(40) == 0, "a 30-yard detour keeps the existing walk at 40 yards")
