---@class LibsFarmAssistant
local LibsFarmAssistant = LibStub('AceAddon-3.0'):GetAddon('Libs-FarmAssistant')
local canaccessvalue = canaccessvalue or function() return true end

---@class LibsFarmAssistant.HonorTracker : AceModule, AceEvent-3.0, AceTimer-3.0
local HonorTracker = LibsFarmAssistant:NewModule('HonorTracker')
LibsFarmAssistant.HonorTracker = HonorTracker

function HonorTracker:OnEnable()
	if LibsFarmAssistant.db.tracking.honor then
		self:RegisterEvent('CHAT_MSG_COMBAT_HONOR_GAIN', 'OnHonorGained')
	end
end

function HonorTracker:OnDisable()
	self:UnregisterAllEvents()
end

---Handle CHAT_MSG_COMBAT_HONOR_GAIN event
---@param event string
---@param text string Chat message text
function HonorTracker:OnHonorGained(event, text)
	if not LibsFarmAssistant:IsSessionActive() then
		return
	end

	if not text or not canaccessvalue(text) then
		return
	end

	local amount = tonumber(text:match('(%d+) [Hh]onor'))
	if not amount then
		return
	end

	LibsFarmAssistant.session.honor = (LibsFarmAssistant.session.honor or 0) + amount

	LibsFarmAssistant:Log(string.format('Honor: +%d', amount), 'debug')
	LibsFarmAssistant:UpdateDisplay()

	if LibsFarmAssistant.db.chatEcho then
		LibsFarmAssistant:Print(string.format('[Farm] +%d honor', amount))
	end
end
