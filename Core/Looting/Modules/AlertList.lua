---@class LibsFarmAssistant
local LibsFarmAssistant = LibStub('AceAddon-3.0'):GetAddon('Libs-FarmAssistant')

local module = LibsFarmAssistant:NewLootingModule('AlertList', 1)

function module:IsEnabled()
	local alertList = LibsFarmAssistant.db.lootModules and LibsFarmAssistant.db.lootModules.alertList
	if not alertList then
		return false
	end
	return next(alertList) ~= nil
end

---@param slotData LootSlotData
---@return LootingModuleResult?
function module:CanLoot(slotData)
	if slotData.slotType ~= Enum.LootSlotType.Item then
		return nil
	end

	local alertList = LibsFarmAssistant.db.lootModules.alertList
	local itemKey = slotData.itemID and tostring(slotData.itemID)

	if not itemKey or not alertList[itemKey] then
		return nil
	end

	-- Fire alert: sound + raid warning
	local soundID = LibsFarmAssistant.db.lootModules.alertSound
	if soundID then
		PlaySound(soundID)
	end

	local display = slotData.itemLink or slotData.itemName
	if RaidNotice_AddMessage then
		RaidNotice_AddMessage(RaidWarningFrame, string.format('ALERT: %s dropped!', display), ChatTypeInfo['RAID_WARNING'])
	end

	LibsFarmAssistant:Log(string.format('Alert triggered for: %s', slotData.itemName), 'info')

	-- Return reason but don't affect loot decision (no loot or forceBreak)
	return { reason = 'Alert' }
end

LibsFarmAssistant:RegisterLootingModule(module)
