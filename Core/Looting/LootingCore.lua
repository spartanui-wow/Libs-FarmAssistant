---@class LibsFarmAssistant
local LibsFarmAssistant = LibStub('AceAddon-3.0'):GetAddon('Libs-FarmAssistant')

-- Deduplication: items auto-looted in last 2 seconds are skipped by passive CHAT_MSG_LOOT tracker
local recentlyAutoLooted = {} -- { [itemID] = GetTime() }
local DEDUP_WINDOW = 2 -- seconds

---Check if an item was recently auto-looted (for deduplication with passive tracker)
---@param itemID number
---@return boolean
function LibsFarmAssistant:WasRecentlyAutoLooted(itemID)
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

---Initialize the auto-looting system
function LibsFarmAssistant:InitializeLootingSystem()
	if not self.db.autoLoot or not self.db.autoLoot.enabled then
		self:Log('Auto-looting disabled', 'debug')
		return
	end

	-- Register for the appropriate loot event
	local event = self.db.autoLoot.fastLoot and 'LOOT_READY' or 'LOOT_OPENED'
	self:RegisterEvent(event, 'OnLootWindowReady')

	self:Log(string.format('Auto-looting initialized (event: %s)', event), 'info')
end

---Handle loot window opening — process all slots through module chain
---@param event string
function LibsFarmAssistant:OnLootWindowReady(event)
	if not self.db.autoLoot or not self.db.autoLoot.enabled then
		return
	end

	local numSlots = GetNumLootItems()
	if numSlots == 0 then
		return
	end

	local modules = self:GetSortedLootingModules()
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
			-- looted == nil means no module handled it (ignored silently)
		end
	end

	-- Close loot window if enabled and we looted something
	if self.db.autoLoot.closeLoot and lootedCount > 0 then
		CloseLoot()
	end
end

---Build slot data table for a loot slot
---@param slotIndex number
---@return LootSlotData?
function LibsFarmAssistant:BuildSlotData(slotIndex)
	local icon, itemName, quantity, currencyID, quality, locked, isQuestItem, questID, isActive, isCoin = GetLootSlotInfo(slotIndex)
	if not itemName then
		return nil
	end

	local slotType = GetLootSlotType(slotIndex)
	local itemLink = nil
	local itemID = nil
	local sellPrice = nil
	local bindType = nil

	-- Only get item details for actual items (not money/currency)
	if slotType == Enum.LootSlotType.Item then
		itemLink = GetLootSlotLink(slotIndex)
		if itemLink then
			itemID = tonumber(itemLink:match('item:(%d+)'))
			-- Get extended item info
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
function LibsFarmAssistant:ProcessSlot(slotData, modules)
	local lastReason = nil

	for _, module in ipairs(modules) do
		local result = module:CanLoot(slotData)
		if result then
			if result.loot then
				-- Loot this item
				LootSlot(slotData.slotIndex)

				-- Record into session tracking (only for items, not money/currency handled by other trackers)
				if slotData.slotType == Enum.LootSlotType.Item and slotData.itemID then
					recentlyAutoLooted[slotData.itemID] = GetTime()
					self:RecordItem(slotData.itemID, slotData.itemName, slotData.itemLink or slotData.itemName, slotData.icon, slotData.quality, slotData.quantity, slotData.sellPrice or 0)
				end

				self:PrintLooted(slotData, result.reason or module.name)
				return true, result.reason or module.name
			end

			if result.forceBreak then
				return false, result.reason or module.name
			end

			-- Module returned a result but didn't loot or break (e.g., AlertList)
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
function LibsFarmAssistant:PrintLooted(slotData, reason)
	if not self.db.autoLoot.printLooted then
		return
	end

	local display = slotData.itemLink or slotData.itemName
	local msg = string.format('[Farm] Looted: %s', display)
	if slotData.quantity > 1 then
		msg = msg .. string.format(' x%d', slotData.quantity)
	end
	if self.db.autoLoot.printReason and reason then
		msg = msg .. string.format(' (%s)', reason)
	end

	self:Print(msg)
end

---Print ignored item to chat (if enabled)
---@param slotData LootSlotData
---@param reason string?
function LibsFarmAssistant:PrintIgnored(slotData, reason)
	if not self.db.autoLoot.printIgnored then
		return
	end

	local display = slotData.itemLink or slotData.itemName
	local msg = string.format('[Farm] Ignored: %s', display)
	if self.db.autoLoot.printReason and reason then
		msg = msg .. string.format(' (%s)', reason)
	end

	self:Print(msg)
end

---Cleanup stale dedup entries (called periodically)
function LibsFarmAssistant:CleanupDedupCache()
	local now = GetTime()
	for itemID, timestamp in pairs(recentlyAutoLooted) do
		if now - timestamp > DEDUP_WINDOW then
			recentlyAutoLooted[itemID] = nil
		end
	end
end
