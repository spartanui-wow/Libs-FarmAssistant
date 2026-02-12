---@class LibsFarmAssistant
local LibsFarmAssistant = LibStub('AceAddon-3.0'):GetAddon('Libs-FarmAssistant')

local module = LibsFarmAssistant:NewLootingModule('WhiteList', 400)

function module:IsEnabled()
	local whitelist = LibsFarmAssistant.db.lootModules and LibsFarmAssistant.db.lootModules.whitelist
	if not whitelist then
		return false
	end
	return next(whitelist) ~= nil
end

---@param slotData LootSlotData
---@return LootingModuleResult?
function module:CanLoot(slotData)
	if slotData.slotType ~= Enum.LootSlotType.Item then
		return nil
	end

	local whitelist = LibsFarmAssistant.db.lootModules.whitelist
	local itemKey = slotData.itemID and tostring(slotData.itemID)

	if itemKey and whitelist[itemKey] then
		return { loot = true, reason = 'Whitelist' }
	end

	return nil
end

LibsFarmAssistant:RegisterLootingModule(module)
