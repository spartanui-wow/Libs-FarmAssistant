---@class LibsFarmAssistant
local LibsFarmAssistant = LibStub('AceAddon-3.0'):GetAddon('Libs-FarmAssistant')

---@class LibsFarmAssistant.LootingCore : AceModule, AceEvent-3.0, AceTimer-3.0
local LootingCore = LibsFarmAssistant:NewModule('LootingCore')
LibsFarmAssistant.LootingCore = LootingCore

-- Deduplication: items auto-looted in last 2 seconds are skipped by passive CHAT_MSG_LOOT tracker
local recentlyAutoLooted = {} -- { [itemID] = GetTime() }
local DEDUP_WINDOW = 2 -- seconds

function LootingCore:OnEnable()
	if not LibsFarmAssistant.db.autoLoot or not LibsFarmAssistant.db.autoLoot.enabled then
		LibsFarmAssistant:Log('Auto-looting disabled', 'debug')
		return
	end

	local event = LibsFarmAssistant.db.autoLoot.fastLoot and 'LOOT_READY' or 'LOOT_OPENED'
	self:RegisterEvent(event, 'OnLootWindowReady')

	LibsFarmAssistant:Log(string.format('Auto-looting initialized (event: %s)', event), 'info')
end

function LootingCore:OnDisable()
	self:UnregisterAllEvents()
end

---Check if an item was recently auto-looted (for deduplication with passive tracker)
---@param itemID number
---@return boolean
function LootingCore:WasRecentlyAutoLooted(itemID)
	local timestamp = recentlyAutoLooted[itemID]
	if not timestamp then
		return false
	end

	if GetTime() - timestamp > DEDUP_WINDOW then
		recentlyAutoLooted[itemID] = nil
		return false
	end

	return true
end

---Handle loot window opening - process all slots through module chain
---@param event string
function LootingCore:OnLootWindowReady(event)
	if not LibsFarmAssistant.db.autoLoot or not LibsFarmAssistant.db.autoLoot.enabled then
		return
	end

	local numSlots = GetNumLootItems()
	if numSlots == 0 then
		return
	end

	local modules = LibsFarmAssistant:GetSortedLootingModules()
	if #modules == 0 then
		return
	end

	local lootedCount = 0
	local ignoredCount = 0

	for slotIndex = numSlots, 1, -1 do
		local slotData = self:BuildSlotData(slotIndex)
		if slotData then
			local looted, reason = self:ProcessSlot(slotData, modules)
			if looted then
				lootedCount = lootedCount + 1
			elseif looted == false then
				ignoredCount = ignoredCount + 1
				self:PrintIgnored(slotData, reason)
			end
		end
	end

	if LibsFarmAssistant.db.autoLoot.closeLoot and lootedCount > 0 then
		CloseLoot()
	end
end

---Build slot data table for a loot slot
---@param slotIndex number
---@return LootSlotData?
function LootingCore:BuildSlotData(slotIndex)
	local icon, itemName, quantity, currencyID, quality, locked, isQuestItem, questID, isActive, isCoin = GetLootSlotInfo(slotIndex)
	if not itemName then
		return nil
	end

	local slotType = GetLootSlotType(slotIndex)
	local itemLink = nil
	local itemID = nil
	local sellPrice = nil
	local bindType = nil

	if slotType == Enum.LootSlotType.Item then
		itemLink = GetLootSlotLink(slotIndex)
		if itemLink then
			itemID = tonumber(itemLink:match('item:(%d+)'))
			local _, _, _, _, _, _, _, _, _, _, itemSellPrice, _, _, bindTypeVal = C_Item.GetItemInfo(itemLink)
			sellPrice = itemSellPrice
			bindType = bindTypeVal
		end
	end

	---@type LootSlotData
	return {
		slotIndex = slotIndex,
		itemLink = itemLink,
		itemName = itemName,
		itemID = itemID,
		quality = quality or 0,
		quantity = quantity or 1,
		locked = locked or false,
		isQuestItem = isQuestItem or false,
		slotType = slotType,
		currencyID = currencyID,
		icon = icon,
		isCoin = isCoin or false,
		sellPrice = sellPrice,
		bindType = bindType,
	}
end

---Process a single loot slot through the module chain
---@param slotData LootSlotData
---@param modules LootingModule[]
---@return boolean? looted true=looted, false=explicitly ignored, nil=unhandled
---@return string? reason
function LootingCore:ProcessSlot(slotData, modules)
	local lastReason = nil

	for _, module in ipairs(modules) do
		local result = module:CanLoot(slotData)
		if result then
			if result.loot then
				LootSlot(slotData.slotIndex)

				if slotData.slotType == Enum.LootSlotType.Item and slotData.itemID then
					recentlyAutoLooted[slotData.itemID] = GetTime()
					LibsFarmAssistant:RecordItem(slotData.itemID, slotData.itemName, slotData.itemLink or slotData.itemName, slotData.icon, slotData.quality, slotData.quantity, slotData.sellPrice or 0)
				end

				self:PrintLooted(slotData, result.reason or module.name)
				return true, result.reason or module.name
			end

			if result.forceBreak then
				return false, result.reason or module.name
			end

			if result.reason then
				lastReason = result.reason
			end
		end
	end

	return nil, lastReason
end

---Print looted item to chat (if enabled)
---@param slotData LootSlotData
---@param reason string
function LootingCore:PrintLooted(slotData, reason)
	if not LibsFarmAssistant.db.autoLoot.printLooted then
		return
	end

	local display = slotData.itemLink or slotData.itemName
	local msg = string.format('[Farm] Looted: %s', display)
	if slotData.quantity > 1 then
		msg = msg .. string.format(' x%d', slotData.quantity)
	end
	if LibsFarmAssistant.db.autoLoot.printReason and reason then
		msg = msg .. string.format(' (%s)', reason)
	end

	LibsFarmAssistant:Print(msg)
end

---Print ignored item to chat (if enabled)
---@param slotData LootSlotData
---@param reason string?
function LootingCore:PrintIgnored(slotData, reason)
	if not LibsFarmAssistant.db.autoLoot.printIgnored then
		return
	end

	local display = slotData.itemLink or slotData.itemName
	local msg = string.format('[Farm] Ignored: %s', display)
	if LibsFarmAssistant.db.autoLoot.printReason and reason then
		msg = msg .. string.format(' (%s)', reason)
	end

	LibsFarmAssistant:Print(msg)
end

---Cleanup stale dedup entries (called periodically)
function LootingCore:CleanupDedupCache()
	local now = GetTime()
	for itemID, timestamp in pairs(recentlyAutoLooted) do
		if now - timestamp > DEDUP_WINDOW then
			recentlyAutoLooted[itemID] = nil
		end
	end
end

-- Bridge methods
function LibsFarmAssistant:WasRecentlyAutoLooted(itemID)
	if self.LootingCore then
		return self.LootingCore:WasRecentlyAutoLooted(itemID)
	end
	return false
end

function LibsFarmAssistant:OnLootWindowReady(event)
	if self.LootingCore then
		self.LootingCore:OnLootWindowReady(event)
	end
end

function LibsFarmAssistant:BuildSlotData(slotIndex)
	if self.LootingCore then
		return self.LootingCore:BuildSlotData(slotIndex)
	end
	return nil
end

function LibsFarmAssistant:ProcessSlot(slotData, modules)
	if self.LootingCore then
		return self.LootingCore:ProcessSlot(slotData, modules)
	end
	return nil, nil
end

function LibsFarmAssistant:CleanupDedupCache()
	if self.LootingCore then
		self.LootingCore:CleanupDedupCache()
	end
end
