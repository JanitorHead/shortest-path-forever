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
L["Avoid this boat"] = "Avoid this boat"
L["Avoid this zeppelin"] = "Avoid this zeppelin"
L["Avoid this lift"] = "Avoid this lift"
L["Avoid this tram"] = "Avoid this tram"
L["Avoid this flight"] = "Avoid this flight"
L["Avoid this portal"] = "Avoid this portal"
L["Avoid this passage"] = "Avoid this passage"
L["Undo"] = "Undo"
L["Allow this transport again and find a new route."] = "Allow this transport again and find a new route."
L["Find a new route without this transport. You can clear avoided transport in Settings."] =
	"Find a new route without this transport. You can clear avoided transport in Settings."
L["No route remains without %s. Right-click to undo."] = "No route remains without %s. Right-click to undo."
L["Avoided transport"] = "Avoided transport"
L["Clear avoided transport (%d)"] = "Clear avoided transport (%d)"
L["Clear this character's avoided transport so the planner can use it again."] =
	"Clear this character's avoided transport so the planner can use it again."
