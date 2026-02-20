---@class LibsFarmAssistant
local LibsFarmAssistant = LibStub('AceAddon-3.0'):GetAddon('Libs-FarmAssistant')

---@class LibsFarmAssistant.MinimapButton : AceModule, AceEvent-3.0, AceTimer-3.0
local MinimapButton = LibsFarmAssistant:NewModule('MinimapButton')
LibsFarmAssistant.MinimapButton = MinimapButton

function MinimapButton:OnEnable()
	local LibDBIcon = LibStub('LibDBIcon-1.0', true)
	if not LibDBIcon or not LibsFarmAssistant.dataObject then
		return
	end

	-- Smart default: hide minimap icon when Libs-DataBar is present (it shows LDB data already)
	if not LibsFarmAssistant.db.minimapDefaultApplied then
		LibsFarmAssistant.db.minimapDefaultApplied = true
		if C_AddOns.IsAddOnLoaded('Libs-DataBar') then
			LibsFarmAssistant.db.minimap.hide = true
		end
	end

	LibDBIcon:Register("Lib's FarmAssistant", LibsFarmAssistant.dataObject, LibsFarmAssistant.db.minimap)
end
