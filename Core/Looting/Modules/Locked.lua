---@class LibsFarmAssistant
local LibsFarmAssistant = LibStub('AceAddon-3.0'):GetAddon('Libs-FarmAssistant')

local module = LibsFarmAssistant:NewLootingModule('Locked', 100)

---@param slotData LootSlotData
---@return LootingModuleResult?
function module:CanLoot(slotData)
	if slotData.locked then
		return { forceBreak = true, reason = 'Locked' }
	end
	return nil
end

LibsFarmAssistant:RegisterLootingModule(module)
