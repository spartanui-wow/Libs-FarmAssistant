---@class LibsFarmAssistant
local LibsFarmAssistant = LibStub('AceAddon-3.0'):GetAddon('Libs-FarmAssistant')

local module = LibsFarmAssistant:NewLootingModule('IgnoreBOP', 600)

local LE_ITEM_BIND_ON_ACQUIRE = 1

function module:IsEnabled()
	return LibsFarmAssistant.db.lootModules and LibsFarmAssistant.db.lootModules.ignoreBOP
end

---@param slotData LootSlotData
---@return LootingModuleResult?
function module:CanLoot(slotData)
	if slotData.slotType ~= Enum.LootSlotType.Item then
		return nil
	end

	if slotData.bindType and slotData.bindType == LE_ITEM_BIND_ON_ACQUIRE then
		return { forceBreak = true, reason = 'BoP' }
	end

	return nil
end

LibsFarmAssistant:RegisterLootingModule(module)
