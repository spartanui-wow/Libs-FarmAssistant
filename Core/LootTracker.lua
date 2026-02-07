---@class LibsFarmAssistant
local LibsFarmAssistant = LibStub('AceAddon-3.0'):GetAddon('Libs-FarmAssistant')

function LibsFarmAssistant:InitializeLootTracker()
	if self.db.tracking.loot then
		self:RegisterEvent('CHAT_MSG_LOOT', 'OnLootReceived')
	end
end

---Handle CHAT_MSG_LOOT event
---@param event string
---@param text string Chat message text
function LibsFarmAssistant:OnLootReceived(event, text)
	if not self:IsSessionActive() then
		return
	end

	-- Only track loot received by the player
	-- Pattern: "You receive loot: |cff...|Hitem:ID:...|h[Name]|h|r"
	-- Also: "You receive item: ..."
	local itemLink = text:match('|c%x+|Hitem:[%d:]+|h%[.-%]|h|r')
	if not itemLink then
		return
	end

	-- Extract quantity (e.g., "x5" at the end)
	local quantity = tonumber(text:match('x(%d+)')) or 1

	-- Get item info from link
	local itemName, _, quality, _, _, _, _, _, _, icon = C_Item.GetItemInfo(itemLink)
	if not itemName then
		-- Item info not cached yet, try to extract ID and queue
		local itemID = tonumber(itemLink:match('item:(%d+)'))
		if itemID then
			-- Store with minimal info, will be updated when info is available
			self:RecordItem(itemID, itemLink, itemLink, nil, nil, quantity)
		end
		return
	end

	local itemID = tonumber(itemLink:match('item:(%d+)'))
	if not itemID then
		return
	end

	-- Quality filter
	if quality and quality < self.db.qualityFilter then
		return
	end

	self:RecordItem(itemID, itemName, itemLink, icon, quality, quantity)
end

---Record an item into session data
---@param itemID number
---@param name string
---@param link string
---@param icon string?
---@param quality number?
---@param count number
function LibsFarmAssistant:RecordItem(itemID, name, link, icon, quality, count)
	local items = self.session.items
	local key = tostring(itemID)

	if items[key] then
		items[key].count = items[key].count + count
		-- Update link/icon if we got better info
		if icon and not items[key].icon then
			items[key].icon = icon
			items[key].name = name
			items[key].link = link
			items[key].quality = quality
		end
	else
		items[key] = {
			name = name,
			link = link,
			icon = icon,
			quality = quality or 0,
			count = count,
		}
	end

	self:Log(string.format('Looted: %s x%d', name, count), 'debug')
	self:UpdateDisplay()
end
