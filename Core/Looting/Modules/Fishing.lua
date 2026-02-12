---@class LibsFarmAssistant
local LibsFarmAssistant = LibStub('AceAddon-3.0'):GetAddon('Libs-FarmAssistant')

local module = LibsFarmAssistant:NewLootingModule('Fishing', 1200)

function module:IsEnabled()
	return LibsFarmAssistant.db.lootModules and LibsFarmAssistant.db.lootModules.fishingMode
end

---@param slotData LootSlotData
---@return LootingModuleResult?
function module:CanLoot(slotData)
	if IsFishingLoot and IsFishingLoot() then
		return { loot = true, reason = 'Fishing' }
	end
	return nil
end

LibsFarmAssistant:RegisterLootingModule(module)
