---@class LibsFarmAssistant
local LibsFarmAssistant = LibStub('AceAddon-3.0'):GetAddon('Libs-FarmAssistant')

local module = LibsFarmAssistant:NewLootingModule('Quest', 800)

local LE_ITEM_BIND_QUEST = 4
local ITEM_CLASS_QUESTITEM = Enum.ItemClass and Enum.ItemClass.Questitem

function module:IsEnabled()
	return LibsFarmAssistant.db.lootModules and LibsFarmAssistant.db.lootModules.lootQuest
end

---@param slotData LootSlotData
---@return LootingModuleResult?
function module:CanLoot(slotData)
	if slotData.slotType ~= Enum.LootSlotType.Item then
		return nil
	end

	-- Check the isQuestItem flag from GetLootSlotInfo
	if slotData.isQuestItem then
		return { loot = true, reason = 'Quest' }
	end

	-- Check bind type (quest item bind)
	if slotData.bindType and slotData.bindType == LE_ITEM_BIND_QUEST then
		return { loot = true, reason = 'Quest' }
	end

	-- Check item class ID
	if slotData.itemLink and ITEM_CLASS_QUESTITEM then
		local _, _, _, _, _, _, _, _, _, _, _, classID = C_Item.GetItemInfo(slotData.itemLink)
		if classID == ITEM_CLASS_QUESTITEM then
			return { loot = true, reason = 'Quest' }
		end
	end

	return nil
end

LibsFarmAssistant:RegisterLootingModule(module)
