---@class LibsFarmAssistant
local LibsFarmAssistant = LibStub('AceAddon-3.0'):GetAddon('Libs-FarmAssistant')

----------------------------------------------------------------------------------------------------
-- Drag-and-Drop Item Tracking
-- Drag items from bags onto the minimap button to add them to the watch list
----------------------------------------------------------------------------------------------------

function LibsFarmAssistant:InitializeItemDragDrop()
	-- Hook the minimap button to accept item drops
	local LibDBIcon = LibStub('LibDBIcon-1.0', true)
	if not LibDBIcon then
		return
	end

	local minimapButton = LibDBIcon:GetMinimapButton("Lib's FarmAssistant")
	if not minimapButton then
		return
	end

	minimapButton:SetScript('OnReceiveDrag', function()
		self:HandleItemDrop()
	end)

	self:Log('Item drag-drop initialized', 'debug')
end

---Handle an item being dropped onto the minimap button
---Modifier keys determine which list the item is added to:
---  No modifier: Watched Items
---  Shift: Whitelist (always auto-loot)
---  Ctrl: Blacklist (never auto-loot)
---  Alt: Alert List (sound + raid warning on drop)
function LibsFarmAssistant:HandleItemDrop()
	local cursorType, itemID = GetCursorInfo()
	if cursorType ~= 'item' or not itemID then
		return
	end

	ClearCursor()

	-- Determine target list based on modifier keys
	local targetList = 'watched'
	if IsShiftKeyDown() then
		targetList = 'whitelist'
	elseif IsControlKeyDown() then
		targetList = 'blacklist'
	elseif IsAltKeyDown() then
		targetList = 'alertList'
	end

	-- Get item info
	local itemName, itemLink, itemQuality, _, _, _, _, _, _, itemIcon = C_Item.GetItemInfo(itemID)
	if not itemName then
		-- Item info not yet cached, try again shortly
		local listTarget = targetList
		C_Timer.After(0.5, function()
			local name, link, quality, _, _, _, _, _, _, icon = C_Item.GetItemInfo(itemID)
			if name then
				self:AddItemToList(listTarget, itemID, name, link, quality, icon)
			else
				self:Print('Could not retrieve item info. Try again.')
			end
		end)
		return
	end

	self:AddItemToList(targetList, itemID, itemName, itemLink, itemQuality, itemIcon)
end

---Add an item to the specified list
---@param listName string 'watched', 'whitelist', 'blacklist', or 'alertList'
---@param itemID number
---@param name string
---@param link string
---@param quality number
---@param icon number|string
function LibsFarmAssistant:AddItemToList(listName, itemID, name, link, quality, icon)
	if listName == 'watched' then
		self:AddWatchedItem(itemID, name, link, quality, icon)
		return
	end

	-- Add to the appropriate loot module list
	local list = self.db.lootModules and self.db.lootModules[listName]
	if not list then
		return
	end

	local key = tostring(itemID)
	local listDisplayName = ({
		whitelist = 'Whitelist',
		blacklist = 'Blacklist',
		alertList = 'Alert List',
	})[listName] or listName

	if list[key] then
		self:Print(string.format('Already on %s: %s', listDisplayName, link or name))
		return
	end

	list[key] = name
	self:Print(string.format('Added to %s: %s', listDisplayName, link or name))
	self:InvalidateLootingModuleCache()
end

---Add an item to the watch list
---@param itemID number
---@param name string
---@param link string
---@param quality number
---@param icon number|string
function LibsFarmAssistant:AddWatchedItem(itemID, name, link, quality, icon)
	if not self.session.watchedItems then
		self.session.watchedItems = {}
	end

	local key = tostring(itemID)

	if self.session.watchedItems[key] then
		self:Print('Already watching: ' .. (link or name))
		return
	end

	self.session.watchedItems[key] = {
		itemID = itemID,
		name = name,
		link = link,
		icon = icon,
		quality = quality or 1,
	}

	self:Print('Now watching: ' .. (link or name))
	self:UpdateDisplay()
end

---Remove an item from the watch list
---@param itemID number|string
function LibsFarmAssistant:UnwatchItem(itemID)
	if not self.session.watchedItems then
		return
	end

	local key = tostring(itemID)
	local item = self.session.watchedItems[key]
	if item then
		self:Print('Stopped watching: ' .. (item.link or item.name or key))
		self.session.watchedItems[key] = nil
		self:UpdateDisplay()
	end
end

---Get the watched items table
---@return table watchedItems
function LibsFarmAssistant:GetWatchedItems()
	return self.session.watchedItems or {}
end
