---@class LibsFarmAssistant
local LibsFarmAssistant = LibStub('AceAddon-3.0'):GetAddon('Libs-FarmAssistant')

---@class LootingModuleResult
---@field loot boolean? Whether to loot this item
---@field reason string? Reason string for chat output
---@field forceBreak boolean? Stop processing further modules for this slot

---@class LootingModule
---@field name string Module name
---@field priority number Lower = checked first
---@field CanLoot fun(self: LootingModule, slotData: LootSlotData): LootingModuleResult?
---@field IsEnabled fun(self: LootingModule): boolean

---@class LootSlotData
---@field slotIndex number Loot window slot index
---@field itemLink string? Item link (nil for money/currency)
---@field itemName string Display name from GetLootSlotInfo
---@field itemID number? Parsed item ID
---@field quality number Item quality (rarity)
---@field quantity number Stack count
---@field locked boolean Whether the item is locked
---@field isQuestItem boolean Whether flagged as quest item
---@field slotType number Enum.LootSlotType value
---@field currencyID number? Currency ID if applicable
---@field icon string Texture path
---@field isCoin boolean Whether this is a coin slot
---@field sellPrice number? Vendor sell price per unit
---@field bindType number? Bind type from GetItemInfo

-- Registry of all looting modules
LibsFarmAssistant.lootingModules = LibsFarmAssistant.lootingModules or {}

-- Sorted module cache (invalidated on register)
local sortedModulesCache = nil

---Register a looting module
---@param module LootingModule
function LibsFarmAssistant:RegisterLootingModule(module)
	if not module.name or not module.priority or not module.CanLoot then
		self:Log('RegisterLootingModule: missing required fields (name, priority, CanLoot)', 'warning')
		return
	end

	self.lootingModules[module.name] = module
	sortedModulesCache = nil -- Invalidate cache

	self:Log(string.format('Looting module registered: %s (priority %d)', module.name, module.priority), 'debug')
end

---Get all enabled modules sorted by priority (cached)
---@return LootingModule[]
function LibsFarmAssistant:GetSortedLootingModules()
	if sortedModulesCache then
		return sortedModulesCache
	end

	local modules = {}
	for _, module in pairs(self.lootingModules) do
		if not module.IsEnabled or module:IsEnabled() then
			table.insert(modules, module)
		end
	end

	table.sort(modules, function(a, b)
		return a.priority < b.priority
	end)

	sortedModulesCache = modules
	return modules
end

---Invalidate the sorted module cache (call when settings change)
function LibsFarmAssistant:InvalidateLootingModuleCache()
	sortedModulesCache = nil
end

---Create a new looting module with defaults
---@param name string
---@param priority number
---@return LootingModule
function LibsFarmAssistant:NewLootingModule(name, priority)
	---@type LootingModule
	local module = {
		name = name,
		priority = priority,
		CanLoot = function()
			return nil
		end,
		IsEnabled = function()
			return true
		end,
	}
	return module
end
