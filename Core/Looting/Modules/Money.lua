---@class LibsFarmAssistant
local LibsFarmAssistant = LibStub('AceAddon-3.0'):GetAddon('Libs-FarmAssistant')

local module = LibsFarmAssistant:NewLootingModule('Money', 200)

---@param slotData LootSlotData
---@return LootingModuleResult?
function module:CanLoot(slotData)
	if slotData.slotType == Enum.LootSlotType.Money or slotData.isCoin then
		return { loot = true, reason = 'Money' }
	end
	return nil
end

LibsFarmAssistant:RegisterLootingModule(module)
