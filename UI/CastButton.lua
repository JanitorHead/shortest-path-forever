---@class SPFNamespace
local ns = select(2, ...)

if ns.broken then
	return
end
local L = ns.L

-- The cast prompt's clickable icon: a secure action button that uses the step's Hearthstone or teleport item, or casts
-- its teleport spell. It copies the prompt's screen position onto UIParent and nothing anchors to it, since a frame
-- anchored to a protected frame turns protected, and the prompt and the movable arrow must stay free to move in
-- combat. Its attributes, position and visibility change only out of combat, so in combat a click keeps the action
-- last applied, and the tooltip says so when the prompt has moved on.

local ICON_SIZE = 36

---@type SecureActionButtonTemplate?
local button
-- The action a click performs now, and the teleport the prompt shows now.
---@type SPFTeleportPlace?
local applied
---@type SPFTeleportPlace?
local shown

local CastButton = {}
ns.CastButton = CastButton

local function HideTooltip(self)
	if GameTooltip:IsOwned(self) then
		GameTooltip:Hide()
	end
end

local function ShowTooltip(self)
	local teleport = applied
	if not teleport then
		return
	end
	local hint
	if teleport.item then
		hint = L["Click to use %s"]:format(C_Item.GetItemNameByID(teleport.item) or UNKNOWN)
	else
		hint = L["Click to cast %s"]:format(C_Spell.GetSpellName(teleport.spell) or UNKNOWN)
	end
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:SetText(hint)
	if InCombatLockdown() and teleport ~= shown then
		GameTooltip:AddLine(L["The travel action will update after combat."])
	end
	GameTooltip:Show()
end

---@return SPFTeleportPlace?
function CastButton.Applied()
	return applied
end

-- Redraws an open tooltip, for instance once the client has the item's name.
function CastButton.Refresh()
	if button and applied and GameTooltip:IsOwned(button) then
		ShowTooltip(button)
	end
end

-- The teleport the prompt shows now, or nil when it shows none.
---@param teleport SPFTeleportPlace?
function CastButton.Shows(teleport)
	shown = teleport
	CastButton.Refresh()
end

-- Out of combat only. Places the button over the prompt's icon with the teleport's action, or hides and clears it.
---@param prompt Frame?
---@param teleport SPFTeleportPlace?
---@param scale number?
function CastButton.Apply(prompt, teleport, scale)
	if not prompt or not teleport then
		if button and applied then
			button:Hide()
			button:SetAttribute("type", nil)
			button:SetAttribute("item", nil)
			button:SetAttribute("spell", nil)
			applied = nil
		end
		return
	end
	local x, top = prompt:GetCenter(), prompt:GetTop()
	if not x or not top then
		return
	end
	if not button then
		button = CreateFrame("Button", nil, UIParent, "SecureActionButtonTemplate")
		button:SetSize(ICON_SIZE, ICON_SIZE)
		button:SetFrameStrata("MEDIUM")
		button:SetFrameLevel(prompt:GetFrameLevel() + 1)
		button:EnableMouse(true)
		-- Let the secure handler honour ActionButtonUseKeyDown on either transition.
		button:RegisterForClicks("AnyUp", "AnyDown")
		button:SetScript("OnEnter", ShowTooltip)
		button:SetScript("OnLeave", HideTooltip)
		button:SetScript("OnHide", HideTooltip)
	end
	button:SetScale(scale or 1)
	button:ClearAllPoints()
	button:SetPoint("TOP", UIParent, "BOTTOMLEFT", x, top)
	button:SetAttribute("type", teleport.item and "item" or "spell")
	button:SetAttribute("item", teleport.item and ("item:" .. teleport.item) or nil)
	button:SetAttribute("spell", not teleport.item and teleport.spell or nil)
	applied = teleport
	button:Show()
	CastButton.Refresh()
end
