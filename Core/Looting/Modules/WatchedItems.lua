---@class LibsFarmAssistant
local LibsFarmAssistant = LibStub('AceAddon-3.0'):GetAddon('Libs-FarmAssistant')

local module = LibsFarmAssistant:NewLootingModule('WatchedItems', 150)

function module:IsEnabled()
	local watched = LibsFarmAssistant.session and LibsFarmAssistant.session.watchedItems
	if not watched then
		return false
	end
	return next(watched) ~= nil
end

---@param slotData LootSlotData
---@return LootingModuleResult?
function module:CanLoot(slotData)
	if slotData.slotType ~= Enum.LootSlotType.Item then
		return nil
	end

	local itemKey = slotData.itemID and tostring(slotData.itemID)
	if not itemKey then
		return nil
	end

	local watched = LibsFarmAssistant.session.watchedItems
	if watched[itemKey] then
		return { loot = true, reason = 'Watched' }
	end

	return nil
end

LibsFarmAssistant:RegisterLootingModule(module)
