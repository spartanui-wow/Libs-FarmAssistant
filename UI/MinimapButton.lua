---@class LibsFarmAssistant
local LibsFarmAssistant = LibStub('AceAddon-3.0'):GetAddon('Libs-FarmAssistant')

function LibsFarmAssistant:InitializeMinimapButton()
	local LibDBIcon = LibStub('LibDBIcon-1.0', true)
	if not LibDBIcon or not self.dataObject then
		return
	end

	-- Smart default: hide minimap icon when Libs-DataBar is present (it shows LDB data already)
	if not self.db.minimapDefaultApplied then
		self.db.minimapDefaultApplied = true
		if C_AddOns.IsAddOnLoaded('Libs-DataBar') then
			self.db.minimap.hide = true
		end
	end

	LibDBIcon:Register("Lib's FarmAssistant", self.dataObject, self.db.minimap)
end
