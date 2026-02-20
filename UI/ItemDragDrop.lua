---@class LibsFarmAssistant
local LibsFarmAssistant = LibStub('AceAddon-3.0'):GetAddon('Libs-FarmAssistant')

---@class LibsFarmAssistant.ItemDragDrop : AceModule, AceEvent-3.0, AceTimer-3.0
local ItemDragDrop = LibsFarmAssistant:NewModule('ItemDragDrop')
LibsFarmAssistant.ItemDragDrop = ItemDragDrop

function ItemDragDrop:OnEnable()
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

	LibsFarmAssistant:Log('Item drag-drop initialized', 'debug')
end

---Handle an item being dropped onto the minimap button
---Modifier keys determine which list the item is added to:
---  No modifier: Watched Items
---  Shift: Whitelist (always auto-loot)
---  Ctrl: Blacklist (never auto-loot)
---  Alt: Alert List (sound + raid warning on drop)
function ItemDragDrop:HandleItemDrop()
	local cursorType, itemID = GetCursorInfo()
	if cursorType ~= 'item' or not itemID then
		return
	end

	ClearCursor()

	local targetList = 'watched'
	if IsShiftKeyDown() then
		targetList = 'whitelist'
	elseif IsControlKeyDown() then
		targetList = 'blacklist'
	elseif IsAltKeyDown() then
		targetList = 'alertList'
	end

	local itemName, itemLink, itemQuality, _, _, _, _, _, _, itemIcon = C_Item.GetItemInfo(itemID)
	if not itemName then
		local listTarget = targetList
		C_Timer.After(0.5, function()
			local name, link, quality, _, _, _, _, _, _, icon = C_Item.GetItemInfo(itemID)
			if name then
				LibsFarmAssistant:AddItemToList(listTarget, itemID, name, link, quality, icon)
			else
				LibsFarmAssistant:Print('Could not retrieve item info. Try again.')
			end
		end)
		return
	end

	LibsFarmAssistant:AddItemToList(targetList, itemID, itemName, itemLink, itemQuality, itemIcon)
end

---Add an item to the specified list
---@param listName string 'watched', 'whitelist', 'blacklist', or 'alertList'
---@param itemID number
---@param name string
---@param link string
---@param quality number
---@param icon number|string
function ItemDragDrop:AddItemToList(listName, itemID, name, link, quality, icon)
	if listName == 'watched' then
		self:AddWatchedItem(itemID, name, link, quality, icon)
		return
	end

	local list = LibsFarmAssistant.db.lootModules and LibsFarmAssistant.db.lootModules[listName]
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
		LibsFarmAssistant:Print(string.format('Already on %s: %s', listDisplayName, link or name))
		return
	end

	list[key] = name
	LibsFarmAssistant:Print(string.format('Added to %s: %s', listDisplayName, link or name))
	LibsFarmAssistant:InvalidateLootingModuleCache()
end

---Add an item to the watch list
---@param itemID number
---@param name string
---@param link string
---@param quality number
---@param icon number|string
function ItemDragDrop:AddWatchedItem(itemID, name, link, quality, icon)
	if not LibsFarmAssistant.session.watchedItems then
		LibsFarmAssistant.session.watchedItems = {}
	end

	local key = tostring(itemID)

	if LibsFarmAssistant.session.watchedItems[key] then
		LibsFarmAssistant:Print('Already watching: ' .. (link or name))
		return
	end

	LibsFarmAssistant.session.watchedItems[key] = {
		itemID = itemID,
		name = name,
		link = link,
		icon = icon,
		quality = quality or 1,
	}

	LibsFarmAssistant:Print('Now watching: ' .. (link or name))
	LibsFarmAssistant:UpdateDisplay()
end

---Remove an item from the watch list
---@param itemID number|string
function ItemDragDrop:UnwatchItem(itemID)
	if not LibsFarmAssistant.session.watchedItems then
		return
	end

	local key = tostring(itemID)
	local item = LibsFarmAssistant.session.watchedItems[key]
	if item then
		LibsFarmAssistant:Print('Stopped watching: ' .. (item.link or item.name or key))
		LibsFarmAssistant.session.watchedItems[key] = nil
		LibsFarmAssistant:UpdateDisplay()
	end
end

---Get the watched items table
---@return table watchedItems
function ItemDragDrop:GetWatchedItems()
	return LibsFarmAssistant.session.watchedItems or {}
end

-- Bridge methods
function LibsFarmAssistant:AddItemToList(listName, itemID, name, link, quality, icon)
	if self.ItemDragDrop then
		self.ItemDragDrop:AddItemToList(listName, itemID, name, link, quality, icon)
	end
end

function LibsFarmAssistant:AddWatchedItem(itemID, name, link, quality, icon)
	if self.ItemDragDrop then
		self.ItemDragDrop:AddWatchedItem(itemID, name, link, quality, icon)
	end
end

function LibsFarmAssistant:UnwatchItem(itemID)
	if self.ItemDragDrop then
		self.ItemDragDrop:UnwatchItem(itemID)
	end
end

function LibsFarmAssistant:GetWatchedItems()
	if self.ItemDragDrop then
		return self.ItemDragDrop:GetWatchedItems()
	end
	return {}
end
