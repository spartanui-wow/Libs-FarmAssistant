---@class LibsFarmAssistant
local LibsFarmAssistant = LibStub('AceAddon-3.0'):GetAddon('Libs-FarmAssistant')

---@class LibsFarmAssistant.LootTracker : AceModule, AceEvent-3.0, AceTimer-3.0
local LootTracker = LibsFarmAssistant:NewModule('LootTracker')
LibsFarmAssistant.LootTracker = LootTracker

function LootTracker:OnEnable()
	if LibsFarmAssistant.db.tracking.loot then
		self:RegisterEvent('CHAT_MSG_LOOT', 'OnLootReceived')
		self:RegisterEvent('ITEM_DATA_LOAD_RESULT', 'OnItemDataLoaded')
	end

	-- Backfill sellPrice for any items missing it (e.g., after /rl)
	for key, item in pairs(LibsFarmAssistant.session.items) do
		if not item.sellPrice then
			local itemID = tonumber(key)
			if itemID then
				C_Item.RequestLoadItemDataByID(itemID)
			end
		end
	end
end

function LootTracker:OnDisable()
	self:UnregisterAllEvents()
end

---Handle CHAT_MSG_LOOT event
---@param event string
---@param text string Chat message text
function LootTracker:OnLootReceived(event, text)
	if not LibsFarmAssistant:IsSessionActive() then
		return
	end

	if not text or not canaccessvalue(text) then
		return
	end

	local itemLink = text:match('|c%x+|Hitem:[%d:]+|h%[.-%]|h|r')
	if not itemLink then
		return
	end

	-- Deduplication: skip items that were just auto-looted (already recorded by LootingCore)
	local dedupItemID = tonumber(itemLink:match('item:(%d+)'))
	if dedupItemID and LibsFarmAssistant:WasRecentlyAutoLooted(dedupItemID) then
		return
	end

	local quantity = tonumber(text:match('x(%d+)')) or 1

	local itemName, _, quality, _, _, _, _, _, _, icon, sellPrice = C_Item.GetItemInfo(itemLink)
	if not itemName then
		local itemID = tonumber(itemLink:match('item:(%d+)'))
		if itemID then
			C_Item.RequestLoadItemDataByID(itemID)
			LibsFarmAssistant:RecordItem(itemID, itemLink, itemLink, nil, nil, quantity, 0)
		end
		return
	end

	local itemID = tonumber(itemLink:match('item:(%d+)'))
	if not itemID then
		return
	end

	if quality and quality < LibsFarmAssistant.db.qualityFilter then
		return
	end

	LibsFarmAssistant:RecordItem(itemID, itemName, itemLink, icon, quality, quantity, sellPrice or 0)
end

---Handle ITEM_DATA_LOAD_RESULT for async backfill
---@param event string
---@param itemID number
---@param success boolean
function LootTracker:OnItemDataLoaded(event, itemID, success)
	if not success then
		return
	end

	local key = tostring(itemID)
	local item = LibsFarmAssistant.session.items[key]
	if not item then
		return
	end

	local itemName, itemLink, quality, _, _, _, _, _, _, icon, sellPrice = C_Item.GetItemInfo(itemID)
	if not itemName then
		return
	end

	if not item.icon then
		item.icon = icon
		item.name = itemName
		item.link = itemLink
		item.quality = quality
	end
	if (item.sellPrice or 0) == 0 and sellPrice and sellPrice > 0 then
		item.sellPrice = sellPrice
	end
end

-- RecordItem stays on main addon since it's called by both LootTracker and LootingCore
function LibsFarmAssistant:RecordItem(itemID, name, link, icon, quality, count, sellPrice)
	local items = self.session.items
	local key = tostring(itemID)

	if items[key] then
		items[key].count = items[key].count + count
		if icon and not items[key].icon then
			items[key].icon = icon
			items[key].name = name
			items[key].link = link
			items[key].quality = quality
		end
		if sellPrice and sellPrice > 0 and (items[key].sellPrice or 0) == 0 then
			items[key].sellPrice = sellPrice
		end
	else
		items[key] = {
			name = name,
			link = link,
			icon = icon,
			quality = quality or 0,
			count = count,
			sellPrice = sellPrice or 0,
		}
	end

	self:Log(string.format('Looted: %s x%d', name, count), 'debug')
	self:UpdateDisplay()

	if self.db.chatEcho then
		self:Print(string.format('[Farm] %s x%d', link or name, count))
	end
end
