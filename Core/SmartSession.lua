---@class LibsFarmAssistant
local LibsFarmAssistant = LibStub('AceAddon-3.0'):GetAddon('Libs-FarmAssistant')

---@class LibsFarmAssistant.SmartSession : AceModule, AceEvent-3.0, AceTimer-3.0
local SmartSession = LibsFarmAssistant:NewModule('SmartSession')
LibsFarmAssistant.SmartSession = SmartSession

function SmartSession:OnEnable()
	self.recentLootTimes = {}

	local settings = LibsFarmAssistant.db.smartSession
	if not settings or not settings.enabled then
		return
	end

	-- Monitor loot events when session is inactive
	self:RegisterEvent('CHAT_MSG_LOOT', 'SmartSessionLootCheck')

	-- Monitor AFK for auto-pause
	self:RegisterEvent('PLAYER_FLAGS_CHANGED', 'SmartSessionAFKCheck')

	-- Static popup for session start prompt
	StaticPopupDialogs['LIBSFA_SMART_SESSION_START'] = {
		text = "Lib's Farm Assistant detected farming activity. Start a tracking session?",
		button1 = 'Start Session',
		button2 = 'Not Now',
		OnAccept = function()
			LibsFarmAssistant:ResetSession()
			LibsFarmAssistant:Print('Smart session started!')
		end,
		timeout = 30,
		whileDead = false,
		hideOnEscape = true,
	}

	LibsFarmAssistant:Log('Smart session initialized', 'debug')
end

function SmartSession:OnDisable()
	self:UnregisterAllEvents()
end

---Check loot events for smart session triggering
function SmartSession:SmartSessionLootCheck()
	local settings = LibsFarmAssistant.db.smartSession
	if not settings or not settings.enabled then
		return
	end

	-- Only trigger when session is paused/inactive
	if LibsFarmAssistant:IsSessionActive() then
		return
	end

	local now = GetTime()
	table.insert(self.recentLootTimes, now)

	-- Prune events outside the time window
	local windowStart = now - (settings.timeWindowSeconds or 30)
	local pruned = {}
	for _, t in ipairs(self.recentLootTimes) do
		if t >= windowStart then
			table.insert(pruned, t)
		end
	end
	self.recentLootTimes = pruned

	-- Check if threshold met
	if #self.recentLootTimes >= (settings.lootThreshold or 3) then
		self.recentLootTimes = {}

		if settings.autoStart then
			LibsFarmAssistant:ResetSession()
			LibsFarmAssistant:Print('Smart session auto-started (detected farming activity)')
		else
			StaticPopup_Show('LIBSFA_SMART_SESSION_START')
		end
	end
end

---Check for AFK status changes to auto-pause
function SmartSession:SmartSessionAFKCheck()
	local settings = LibsFarmAssistant.db.smartSession
	if not settings or not settings.enabled then
		return
	end

	if UnitIsAFK('player') and LibsFarmAssistant:IsSessionActive() then
		LibsFarmAssistant:ToggleSession()
		LibsFarmAssistant:Print('Session auto-paused (AFK detected)')
	end
end
