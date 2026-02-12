---@class LibsFarmAssistant
local LibsFarmAssistant = LibStub('AceAddon-3.0'):GetAddon('Libs-FarmAssistant')

local module = LibsFarmAssistant:NewLootingModule('Currency', 300)

---@param slotData LootSlotData
---@return LootingModuleResult?
function module:CanLoot(slotData)
	if slotData.slotType == Enum.LootSlotType.Currency or (slotData.currencyID and slotData.currencyID > 0) then
		return { loot = true, reason = 'Currency' }
	end
	return nil
end

LibsFarmAssistant:RegisterLootingModule(module)
