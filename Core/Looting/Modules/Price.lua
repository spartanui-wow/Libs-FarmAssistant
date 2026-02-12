---@class LibsFarmAssistant
local LibsFarmAssistant = LibStub('AceAddon-3.0'):GetAddon('Libs-FarmAssistant')

local module = LibsFarmAssistant:NewLootingModule('Price', 1000)

function module:IsEnabled()
	return LibsFarmAssistant.db.lootModules and (LibsFarmAssistant.db.lootModules.minPrice or 0) > 0
end

---@param slotData LootSlotData
---@return LootingModuleResult?
function module:CanLoot(slotData)
	if slotData.slotType ~= Enum.LootSlotType.Item then
		return nil
	end

	local minPrice = LibsFarmAssistant.db.lootModules.minPrice
	if not slotData.sellPrice then
		return nil
	end

	if slotData.sellPrice >= minPrice then
		return { loot = true, reason = 'Price' }
	end

	return nil
end

LibsFarmAssistant:RegisterLootingModule(module)
