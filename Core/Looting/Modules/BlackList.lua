---@class LibsFarmAssistant
local LibsFarmAssistant = LibStub('AceAddon-3.0'):GetAddon('Libs-FarmAssistant')

local module = LibsFarmAssistant:NewLootingModule('BlackList', 500)

function module:IsEnabled()
	local blacklist = LibsFarmAssistant.db.lootModules and LibsFarmAssistant.db.lootModules.blacklist
	if not blacklist then
		return false
	end
	return next(blacklist) ~= nil
end

---@param slotData LootSlotData
---@return LootingModuleResult?
function module:CanLoot(slotData)
	if slotData.slotType ~= Enum.LootSlotType.Item then
		return nil
	end

	local blacklist = LibsFarmAssistant.db.lootModules.blacklist
	local itemKey = slotData.itemID and tostring(slotData.itemID)

	if itemKey and blacklist[itemKey] then
		return { forceBreak = true, reason = 'Blacklist' }
	end

	return nil
end

LibsFarmAssistant:RegisterLootingModule(module)
