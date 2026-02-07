---@class LibsFarmAssistant
local LibsFarmAssistant = LibStub('AceAddon-3.0'):GetAddon('Libs-FarmAssistant')

function LibsFarmAssistant:InitializeHonorTracker()
	if self.db.tracking.honor then
		self:RegisterEvent('CHAT_MSG_COMBAT_HONOR_GAIN', 'OnHonorGained')
	end
end

---Handle CHAT_MSG_COMBAT_HONOR_GAIN event
---@param event string
---@param text string Chat message text
function LibsFarmAssistant:OnHonorGained(event, text)
	if not self:IsSessionActive() then
		return
	end

	-- Pattern: "PlayerName dies, honorable kill Rank: Whatever (X honor)"
	-- Also: "You have been awarded X honor."
	local amount = tonumber(text:match('(%d+) [Hh]onor'))
	if not amount then
		return
	end

	self.session.honor = (self.session.honor or 0) + amount

	self:Log(string.format('Honor: +%d', amount), 'debug')
	self:UpdateDisplay()
end
