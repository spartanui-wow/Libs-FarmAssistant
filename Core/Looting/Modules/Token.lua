---@class LibsFarmAssistant
local LibsFarmAssistant = LibStub('AceAddon-3.0'):GetAddon('Libs-FarmAssistant')

local module = LibsFarmAssistant:NewLootingModule('Token', 900)

function module:IsEnabled()
	return LibsFarmAssistant.db.lootModules and LibsFarmAssistant.db.lootModules.lootTokens
end

---@param slotData LootSlotData
---@return LootingModuleResult?
function module:CanLoot(slotData)
	if slotData.slotType ~= Enum.LootSlotType.Item then
		return nil
	end

	-- Tokens are items with no vendor sell price
	if slotData.sellPrice and slotData.sellPrice > 0 then
		return nil
	end

	-- Don't double-loot quest items (Quest module handles those)
	if slotData.isQuestItem then
		return nil
	end

	return { loot = true, reason = 'Token' }
end

LibsFarmAssistant:RegisterLootingModule(module)
