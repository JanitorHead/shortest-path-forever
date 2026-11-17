---@class SPFNamespace
local ns = select(2, ...)

if ns.broken then
	return
end
local L = ns.L

-- The groups the Nearby services list offers, by what a vendor sells and by the service an NPC's flags name. The
-- list and the map's town services read the same labels, so a bank is a bank in both places. The group shapes are in
-- types/Addon.lua (SPFVendorGroup and SPFServiceGroup).
--
-- `icon` is what the Nearby services row shows: the goods' own item for a vendor, the tracking atlas for a service.
-- `tracking` is the client's minimap tracking icon the world map's service pins wear (the tracking menu's own art),
-- when that sheet has one for exactly this service. It has none for bags, trade goods, books or weapons and armour
-- (its `Gear` element is the treasure coin), so those groups leave `tracking` out and their pins wear the same item
-- icon as their row (UI/Nearby.lua). A pin never borrows another service's art: a weapons pin in the transmogrifier's
-- crystal read as a town full of transmogrifiers (#978).

-- Vendors grouped by what they sell: QuestieDB's item class and subclass, and the food and drink item IDs in
-- Data/Services.lua.
---@type SPFVendorGroup[]
local VENDOR_GROUPS = {
	{ key = "arrows", label = L["Arrows"], icon = 2512, tracking = "Ammunition" },
	{ key = "bullets", label = L["Bullets"], icon = 2516, tracking = "Ammunition" },
	{ key = "food", label = L["Food"], icon = 4540, tracking = "Food" },
	{ key = "drink", label = L["Drink"], icon = 159, tracking = "Food" },
	{ key = "bags", label = L["Bags"], icon = 4498 },
	{ key = "trade", label = L["Trade supplies"], icon = 2320 },
	{ key = "reagents", label = L["Reagents"], icon = 2928, tracking = "Reagents" },
	{ key = "books", label = L["Books and recipes"], icon = 2555 },
	{ key = "gear", label = L["Weapons and armour"], icon = 851 },
}

-- The other services keep their own keys and the client's tracking atlases; their tracking is the atlas itself.
---@type SPFServiceGroup[]
local SERVICES = {
	{ key = "innkeeper", flag = "INNKEEPER", label = L["Innkeeper"], icon = "innkeeper", tracking = "Innkeeper" },
	{
		key = "flight",
		flag = "FLIGHT_MASTER",
		label = L["Flight master"],
		icon = "flightmaster",
		tracking = "FlightMaster",
	},
	{
		key = "stable",
		flag = "STABLEMASTER",
		label = L["Stable master"],
		icon = "stablemaster",
		tracking = "StableMaster",
	},
	{ key = "repair", flag = "REPAIR", label = L["Repair"], icon = "repair", tracking = "Repair" },
	{ key = "bank", flag = "BANKER", label = L["Bank"], icon = "banker", tracking = "Banker" },
	{ key = "auction", flag = "AUCTIONEER", label = L["Auction house"], icon = "auctioneer", tracking = "Auctioneer" },
	{
		key = "transmog",
		flag = "TRANSMOGRIFIER",
		label = L["Transmogrifier"],
		icon = "poi-transmogrifier",
		tracking = "poi-transmogrifier",
	},
}

local SECTION_LABELS = {
	vendors = L["Vendors"],
	trainers = L["Trainers"],
	services = L["Services"],
	entrances = L["Dungeons and raids"],
}

ns.NearbyGroups = {
	vendors = VENDOR_GROUPS,
	services = SERVICES,
	sections = SECTION_LABELS,
}
