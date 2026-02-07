---@class LibsFarmAssistant
local LibsFarmAssistant = LibStub('AceAddon-3.0'):GetAddon('Libs-FarmAssistant')

function LibsFarmAssistant:InitializeMinimapButton()
	local LibDBIcon = LibStub('LibDBIcon-1.0', true)
	if not LibDBIcon or not self.dataObject then
		return
	end

	LibDBIcon:Register("Lib's FarmAssistant", self.dataObject, self.db.minimap)
end
