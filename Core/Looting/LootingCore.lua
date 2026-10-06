---@class LibsFarmAssistant
local LibsFarmAssistant = LibStub('AceAddon-3.0'):GetAddon('Libs-FarmAssistant')

---@class LibsFarmAssistant.LootingCore : AceModule, AceEvent-3.0, AceTimer-3.0
local LootingCore = LibsFarmAssistant:NewModule('LootingCore')
LibsFarmAssistant.LootingCore = LootingCore

-- Taking a slot fires LOOT_SLOT_CLEARED, and the LootTracker records it from there with its
-- source, so this module only decides what to take.

function LootingCore:OnEnable()
	if not LibsFarmAssistant.db.autoLoot or not LibsFarmAssistant.db.autoLoot.enabled then
		LibsFarmAssistant:Log('Auto-looting disabled', 'debug')
		return
	end

	local event = LibsFarmAssistant.db.autoLoot.fastLoot and 'LOOT_READY' or 'LOOT_OPENED'
	self:RegisterEvent(event, 'OnLootWindowReady')

	LibsFarmAssistant:Log(string.format('Auto-looting initialized (event: %s)', event), 'info')

	if LibsFarmAssistant:AutoLootConflict() then
		LibsFarmAssistant:Print("The game's own auto loot is on, so it picks up everything and your Farm Assistant loot filters are skipped. Change it in Settings > Auto-Loot.")
	end
end

function LootingCore:OnDisable()
	self:UnregisterAllEvents()
end

---Both auto looters are on: the game takes everything before the filters here get a say.
---@return boolean
function LibsFarmAssistant:AutoLootConflict()
	local settings = self.db.autoLoot
	return settings and settings.enabled and (self.Compat.GameAutoLoot()) or false
end

---Handle loot window opening - process all slots through module chain
---@param event string
---@param gameAutoLoot boolean The game is taking every slot of this window itself
function LootingCore:OnLootWindowReady(event, gameAutoLoot)
	if not LibsFarmAssistant.db.autoLoot or not LibsFarmAssistant.db.autoLoot.enabled then
		return
	end
	-- The game's auto loot (or its auto loot key held down) is already taking every slot.
	-- Taking the same slots again would only race it; the loot is still counted.
	if gameAutoLoot and LibsFarmAssistant.Compat.CanAccess(gameAutoLoot) then
		return
	end

	local numSlots = GetNumLootItems()
	if numSlots == 0 then
		return
	end

	-- Read every slot with its source before anything is taken.
	if LibsFarmAssistant.LootTracker then
		LibsFarmAssistant.LootTracker:Snapshot()
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

	if slotType == ((Enum and Enum.LootSlotType and Enum.LootSlotType.Item) or LOOT_SLOT_ITEM or 1) then
		itemLink = GetLootSlotLink(slotIndex)
		if itemLink then
			itemID = tonumber(itemLink:match('item:(%d+)'))
			local _, _, _, itemSellPrice, bindTypeVal = LibsFarmAssistant.Compat.ItemInfo(itemLink)
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

-- Bridge methods
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
