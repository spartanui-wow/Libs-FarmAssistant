---@class LibsFarmAssistant
local LibsFarmAssistant = LibStub('AceAddon-3.0'):GetAddon('Libs-FarmAssistant')

---@class LibsFarmAssistant.ReputationTracker : AceModule, AceEvent-3.0, AceTimer-3.0
local ReputationTracker = LibsFarmAssistant:NewModule('ReputationTracker')
LibsFarmAssistant.ReputationTracker = ReputationTracker

function ReputationTracker:OnEnable()
	if LibsFarmAssistant.db.tracking.reputation then
		self:RegisterEvent('CHAT_MSG_COMBAT_FACTION_CHANGE', 'OnReputationGained')
	end
end

function ReputationTracker:OnDisable()
	self:UnregisterAllEvents()
end

---Handle CHAT_MSG_COMBAT_FACTION_CHANGE event
---@param event string
---@param text string Chat message text
function ReputationTracker:OnReputationGained(event, text)
	if not LibsFarmAssistant:IsSessionActive() then
		return
	end

	local faction, amount = text:match('Reputation with (.+) increased by (%d+)')
	if not faction or not amount then
		return
	end

	amount = tonumber(amount)
	if not amount then
		return
	end

	local reputation = LibsFarmAssistant.session.reputation
	reputation[faction] = (reputation[faction] or 0) + amount

	LibsFarmAssistant:Log(string.format('Rep: %s +%d', faction, amount), 'debug')
	LibsFarmAssistant:UpdateDisplay()

	if LibsFarmAssistant.db.chatEcho then
		LibsFarmAssistant:Print(string.format('[Farm] %s +%d rep', faction, amount))
	end
end
