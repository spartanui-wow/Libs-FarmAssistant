---@class LibsFarmAssistant
local LibsFarmAssistant = LibStub('AceAddon-3.0'):GetAddon('Libs-FarmAssistant')

-- While tracking is paused, several loots in a short time mean the player is farming again:
-- offer to resume (or resume on its own when the player asked for that).

---@class LibsFarmAssistant.SmartSession : AceModule, AceEvent-3.0, AceTimer-3.0
local SmartSession = LibsFarmAssistant:NewModule('SmartSession')
LibsFarmAssistant.SmartSession = SmartSession

StaticPopupDialogs['LIBSFA_SMART_SESSION_START'] = {
	text = "Looks like you're farming. Resume tracking?",
	button1 = 'Resume',
	button2 = 'Not now',
	OnAccept = function()
		LibsFarmAssistant.SessionManager:SetPaused(false)
	end,
	timeout = 30,
	whileDead = false,
	hideOnEscape = true,
}

function SmartSession:OnEnable()
	self.recentLoots = {}
	self:RegisterEvent('LOOT_READY', 'OnLoot')
end

function SmartSession:OnLoot()
	local settings = LibsFarmAssistant.db.smartSession
	if not settings or not settings.enabled or LibsFarmAssistant:IsSessionActive() then
		return
	end

	local now = GetTime()
	local windowStart = now - (settings.timeWindowSeconds or 30)
	local kept = {}
	for _, t in ipairs(self.recentLoots) do
		if t >= windowStart then
			kept[#kept + 1] = t
		end
	end
	kept[#kept + 1] = now
	self.recentLoots = kept

	if #kept >= (settings.lootThreshold or 3) then
		self.recentLoots = {}
		if settings.autoStart then
			LibsFarmAssistant.SessionManager:SetPaused(false, true)
			LibsFarmAssistant:Print('Farming noticed. Tracking resumed.')
		else
			StaticPopup_Show('LIBSFA_SMART_SESSION_START')
		end
	end
end
