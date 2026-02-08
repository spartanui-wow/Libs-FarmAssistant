---@class LibsFarmAssistant
local LibsFarmAssistant = LibStub('AceAddon-3.0'):GetAddon('Libs-FarmAssistant')

----------------------------------------------------------------------------------------------------
-- Smart Session Auto-Detection
-- Automatically starts/prompts a farming session when loot activity is detected
-- Auto-pauses on AFK
----------------------------------------------------------------------------------------------------

local recentLootTimes = {} -- timestamps of recent loot events

function LibsFarmAssistant:InitializeSmartSession()
	local settings = self.db.smartSession
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

	self:Log('Smart session initialized', 'debug')
end

---Check loot events for smart session triggering
function LibsFarmAssistant:SmartSessionLootCheck()
	local settings = self.db.smartSession
	if not settings or not settings.enabled then
		return
	end

	-- Only trigger when session is paused/inactive
	if self:IsSessionActive() then
		return
	end

	local now = GetTime()
	table.insert(recentLootTimes, now)

	-- Prune events outside the time window
	local windowStart = now - (settings.timeWindowSeconds or 30)
	local pruned = {}
	for _, t in ipairs(recentLootTimes) do
		if t >= windowStart then
			table.insert(pruned, t)
		end
	end
	recentLootTimes = pruned

	-- Check if threshold met
	if #recentLootTimes >= (settings.lootThreshold or 3) then
		recentLootTimes = {} -- Reset to avoid re-triggering

		if settings.autoStart then
			-- Auto-start immediately
			self:ResetSession()
			self:Print('Smart session auto-started (detected farming activity)')
		else
			-- Show prompt
			StaticPopup_Show('LIBSFA_SMART_SESSION_START')
		end
	end
end

---Check for AFK status changes to auto-pause
function LibsFarmAssistant:SmartSessionAFKCheck()
	local settings = self.db.smartSession
	if not settings or not settings.enabled then
		return
	end

	-- Auto-pause if player goes AFK during an active session
	if UnitIsAFK('player') and self:IsSessionActive() then
		self:ToggleSession() -- Pauses the session
		self:Print('Session auto-paused (AFK detected)')
	end
end
