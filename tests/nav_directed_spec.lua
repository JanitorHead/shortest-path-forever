-- A directed corner crossing, two floor landings and a same-cell drop.
local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local function enc(value, width)
	local out = ""
	for _ = 1, width do
		local digit = value % 64 + 1
		out = alphabet:sub(digit, digit) .. out
		value = math.floor(value / 64)
	end
	return out
end
local function cell(value, mask)
	return enc(value * 256 + mask, 2)
end
local function header(delta, mask)
	return enc(delta, 1) .. enc(1, 1) .. enc(2050, 2) .. enc(mask, 2)
end
_G.ShortestPathForeverPathData = {
	[44] = {
		format = 4,
		cells = 2,
		cx0 = 0,
		cy0 = 0,
		nx = 2,
		ny = 1,
		swim = 3,
		zstep = 2,
		graph = {},
		grid = {
			"D" .. cell(1, 16) .. cell(1, 1) .. cell(0, 0) .. "ABA" .. "v" .. cell(1, 0),
			"C" .. cell(0, 0) .. cell(2, 0) .. "ABx",
		},
		height = { "Xy", "Xx" },
		floor = {
			enc(6, 3)
				.. header(3, 2)
				.. header(0, 0):rep(5)
				.. enc(1, 3)
				.. "AAQ"
				.. "BAACBG"
				.. enc(1, 3)
				.. "AAEIIAAH"
				.. "AEBBAA",
		},
	},
}
local ns = {}
assert(loadfile("Routing/PathGrid.lua"))("ShortestPathForever", ns)
local Grid = ns.PathGrid
local st = assert(Grid.State(44))
assert(st.steep == nil)
local ks, nodes, costs = {}, {}, {}
local function steps(k, node, dx, dy, water)
	local lc = Grid.cellOf(st, k, node)
	return Grid.neighbours(st, k, node, k * 2 + math.floor(lc / 2), lc % 2, dx, dy, water, ks, nodes, costs)
end
assert(Grid.grid(st, 0))
assert(Grid.grid(st, 1))
assert(steps(0, 0, 1, 1, true) == 3 and nodes[1] == 3 and nodes[2] == 4 and nodes[3] == 9)
assert(steps(0, 0, 1, 1, false) == 2 and nodes[1] == 3 and nodes[2] == 9, "only one landing needs water")
assert(steps(0, 1, 1, 0, true) == 1 and steps(0, 1, 1, 0, false) == 0, "two dry endpoints can require water")
assert(steps(0, 3, -1, -1, false) == 0, "a diagonal never implies its reverse")
assert(steps(0, 4, -1, 0, false) == 1 and nodes[1] == 1)
assert(steps(0, 4, 0, 0, false) == 1 and nodes[1] == 3 and costs[1] == 7)
assert(st.linksIn[0][5] and #st.linksIn[0][5] == 1)
assert(steps(0, 2, 1, 1, true) == 1 and ks[1] == 1 and nodes[1] == 1)
assert(steps(0, 2, 1, 1, false) == 0, "dry travel cannot enter water")
assert(steps(0, 0, 0, 2, true) == 0, "a long offset cannot alias a step bit")
assert(steps(1, 1, -1, -1, true) == 0)
local src = assert(io.open("Routing/Path.lua"))
local search = src:read("*a")
src:close()
assert(loadstring(search .. "\nns.SpecSearch, ns.SpecTree = search, Tree", "@Routing/Path.lua"))(
	"ShortestPathForever",
	ns
)
local function route(from, to, reverse)
	return ns.SpecSearch(st, 0, 1, from, ns.SpecTree(), to, nil, nil, nil, nil, reverse)
end
assert(route(0, 3, false) and route(3, 0, true))
assert(not route(3, 0, false) and not route(0, 3, true))
print("nav_directed_spec: ok")
