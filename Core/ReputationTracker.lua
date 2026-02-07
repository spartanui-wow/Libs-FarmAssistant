---@class LibsFarmAssistant
local LibsFarmAssistant = LibStub('AceAddon-3.0'):GetAddon('Libs-FarmAssistant')

function LibsFarmAssistant:InitializeReputationTracker()
	if self.db.tracking.reputation then
		self:RegisterEvent('CHAT_MSG_COMBAT_FACTION_CHANGE', 'OnReputationGained')
	end
end

---Handle CHAT_MSG_COMBAT_FACTION_CHANGE event
---@param event string
---@param text string Chat message text
function LibsFarmAssistant:OnReputationGained(event, text)
	if not self:IsSessionActive() then
		return
	end

	-- Pattern: "Reputation with FactionName increased by X."
	local faction, amount = text:match('Reputation with (.+) increased by (%d+)')
	if not faction or not amount then
		return
	end

	amount = tonumber(amount)
	if not amount then
		return
	end

	local reputation = self.session.reputation
	reputation[faction] = (reputation[faction] or 0) + amount

	self:Log(string.format('Rep: %s +%d', faction, amount), 'debug')
	self:UpdateDisplay()
end
