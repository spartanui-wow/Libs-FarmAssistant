---@class LibsFarmAssistant
local LibsFarmAssistant = LibStub('AceAddon-3.0'):GetAddon('Libs-FarmAssistant')

local module = LibsFarmAssistant:NewLootingModule('All', 99999)

function module:IsEnabled()
	return LibsFarmAssistant.db.autoLoot and LibsFarmAssistant.db.autoLoot.lootAll
end

---@param slotData LootSlotData
---@return LootingModuleResult?
function module:CanLoot(slotData)
	return { loot = true, reason = 'All' }
end

LibsFarmAssistant:RegisterLootingModule(module)
