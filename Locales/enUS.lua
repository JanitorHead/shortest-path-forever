---@class SPFNamespace
local ns = select(2, ...)

-- English phrases are the keys, so a phrase with no translation reads as English.
---@type table<string, string>
local L = setmetatable({}, {
	__index = function(_, key)
		return key
	end,
})
ns.L = L

L["stop guiding"] = "stop guiding"
L["guide this journey"] = "guide this journey"
L["show it on the map"] = "show it on the map"
L["That guide has no step to follow."] = "That guide has no step to follow."
L["%s-right-click the map to mark a road or wall for a report."] =
	"%s-right-click the map to mark a road or wall for a report."
L["Mark: road missing here"] = "Mark: road missing here"
L["Mark: wall here"] = "Mark: wall here"
L["%s-right-click the map to copy the report or clear its marks."] =
	"%s-right-click the map to copy the report or clear its marks."
L["Save this spot in the report to help fix the walking map."] =
	"Save this spot in the report to help fix the walking map."
L["This spot has no world coordinates. Choose another spot."] =
	"This spot has no world coordinates. Choose another spot."
L["Copy road and wall report"] = "Copy road and wall report"
L["Open the report so you can copy and paste it into a bug report."] =
	"Open the report so you can copy and paste it into a bug report."
L["Clear marks"] = "Clear marks"
L["Remove all saved road and wall marks from the map and report."] =
	"Remove all saved road and wall marks from the map and report."
L["Road and wall report"] = "Road and wall report"
L["Journey start: %s"] = "Journey start: %s"
L["Journey goal: %s"] = "Journey goal: %s"
