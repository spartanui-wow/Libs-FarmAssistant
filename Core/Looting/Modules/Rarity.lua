---@class LibsFarmAssistant
local LibsFarmAssistant = LibStub('AceAddon-3.0'):GetAddon('Libs-FarmAssistant')

local module = LibsFarmAssistant:NewLootingModule('Rarity', 700)

function module:IsEnabled()
	local rarityTable = LibsFarmAssistant.db.lootModules and LibsFarmAssistant.db.lootModules.rarityTable
	if not rarityTable then
		return false
	end
	-- Enabled if any quality tier is toggled on
	for _, enabled in pairs(rarityTable) do
		if enabled then
			return true
		end
	end
	return false
end

---@param slotData LootSlotData
---@return LootingModuleResult?
function module:CanLoot(slotData)
	if slotData.slotType ~= Enum.LootSlotType.Item then
		return nil
	end

	local rarityTable = LibsFarmAssistant.db.lootModules.rarityTable
	if rarityTable[slotData.quality] then
		return { loot = true, reason = 'Quality' }
	end

	return nil
end

LibsFarmAssistant:RegisterLootingModule(module)
