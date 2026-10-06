---@class LibsFarmAssistant
local LibsFarmAssistant = LibStub('AceAddon-3.0'):GetAddon('Libs-FarmAssistant')

-- A session is a ledger bucket plus a clock. The clock stores active seconds, never a start
-- timestamp, so a logout (or a reboot) can never inflate the time and wreck per-hour rates.
-- Coming back after a long break starts a fresh session on its own.

---@class LibsFarmAssistant.SessionManager : AceModule, AceEvent-3.0, AceTimer-3.0
local SessionManager = LibsFarmAssistant:NewModule('SessionManager')
LibsFarmAssistant.SessionManager = SessionManager

local Ledger = LibsFarmAssistant.Ledger
local Compat = LibsFarmAssistant.Compat
local Format = LibsFarmAssistant.Format

local TICK = 5

-- session.pausedFor says why tracking stopped by itself. A pause the player made leaves it nil and
-- never resumes on its own: 'away' and 'resting' resume when that ends, 'kill' on the next kill.
local AUTO_PAUSE = { away = true, resting = true }
local STATE_LABEL = { away = 'away', resting = 'resting', kill = 'waiting for a kill' }

-- How tracking starts at login (db.session.startMode)
SessionManager.START_MODES = {
	login = 'When I log in',
	kill = 'At my first kill',
	manual = 'Only when I press resume',
}
SessionManager.START_MODE_ORDER = { 'login', 'kill', 'manual' }

function SessionManager:OnInitialize()
	self.clockStart = nil -- GetTime() when the clock last started running
	self.lastReason = nil -- the away/resting reason seen last, so only changes act
end

function SessionManager:OnEnable()
	local char = LibsFarmAssistant.char
	local session = char.session
	local gap = session and session.lastSeen and (time() - session.lastSeen) or math.huge
	local limit = (LibsFarmAssistant.db.session.newAfterMinutes or 30) * 60

	if not session or not session.version then
		self:Begin()
	elseif limit > 0 and gap > limit then
		self:NewSession(true)
	else
		Ledger.Normalize(session)
	end

	Ledger:Prune()

	if self:IsActive() then
		self:StartClock()
	end

	self:RegisterEvent('PLAYER_LOGOUT', 'Flush')
	self:RegisterEvent('PLAYER_ENTERING_WORLD', 'OnEnteringWorld')
	self:RegisterEvent('PLAYER_FLAGS_CHANGED', 'UpdateAutoPause')
	self:RegisterEvent('PLAYER_UPDATE_RESTING', 'UpdateAutoPause')
	self:RegisterEvent('ZONE_CHANGED_NEW_AREA', 'Flush')
	self:ScheduleRepeatingTimer('Tick', TICK)
end

---Creates an empty session without archiving anything.
---@return table session
function SessionManager:Begin()
	local session = Ledger.NewBucket()
	session.version = 2
	session.active = true
	session.started = time()
	session.lastSeen = time()
	session.zones = {}
	LibsFarmAssistant.char.session = session
	return session
end

---@return table
function SessionManager:Get()
	return LibsFarmAssistant.char.session or self:Begin()
end

---@return boolean
function SessionManager:IsActive()
	local session = LibsFarmAssistant.char.session
	return session ~= nil and session.active ~= false
end

function SessionManager:StartClock()
	if not self.clockStart then
		self.clockStart = GetTime()
	end
end

---Moves running clock time into the ledger.
function SessionManager:Flush()
	local session = LibsFarmAssistant.char.session
	if not session then
		return
	end
	if self.clockStart then
		local now = GetTime()
		local elapsed = now - self.clockStart
		self.clockStart = now
		if elapsed > 0 and elapsed < 3600 then
			Ledger:AddTime(elapsed)
			local zone = Compat.CurrentZone()
			if zone ~= '' then
				session.zones = session.zones or {}
				session.zones[zone] = (session.zones[zone] or 0) + elapsed
			end
			LibsFarmAssistant:SendMessage('LIBSFA_TIME_ADDED', elapsed)
		end
	end
	session.lastSeen = time()
end

function SessionManager:Tick()
	self:Flush()
	LibsFarmAssistant:UpdateDisplay()
end

---Active seconds including the part of the clock not yet flushed.
---@return number
function SessionManager:Duration()
	local session = self:Get()
	local pending = self.clockStart and (GetTime() - self.clockStart) or 0
	return (session.time or 0) + math.max(0, pending)
end

---@param paused boolean
---@param silent? boolean
---@param reason? string Why tracking paused by itself ('away', 'resting', 'kill'); nil when the player paused it
function SessionManager:SetPaused(paused, silent, reason)
	local session = self:Get()
	if paused == (session.active == false) then
		return
	end
	self:Flush()
	if paused then
		session.active = false
		session.pausedFor = reason
		self.clockStart = nil
	else
		session.active = true
		session.pausedFor = nil
		self:StartClock()
	end
	if not silent then
		LibsFarmAssistant:Print(paused and 'Tracking paused.' or 'Tracking resumed.')
	end
	LibsFarmAssistant:SendMessage('LIBSFA_SESSION_STATE')
	LibsFarmAssistant:UpdateDisplay()
end

---Why tracking paused by itself, or nil.
---@return string|nil
function SessionManager:PausedFor()
	local session = LibsFarmAssistant.char.session
	return session and session.active == false and session.pausedFor or nil
end

---Short state for headers: farming, paused, away, resting or waiting for a kill.
---@return string
function SessionManager:StateLabel()
	if self:IsActive() then
		return 'farming'
	end
	return STATE_LABEL[self:PausedFor()] or 'paused'
end

---The state label with a capital first letter, for text that starts a line.
---@return string
function SessionManager:StateText()
	local label = self:StateLabel()
	return label:sub(1, 1):upper() .. label:sub(2)
end

function SessionManager:Toggle()
	self:SetPaused(self:IsActive())
end

---Archives the current session and starts a new one.
---@param quiet? boolean
function SessionManager:NewSession(quiet)
	self:Flush()
	local old = LibsFarmAssistant.char.session
	if old and old.version then
		local topZone, topTime = nil, 0
		for zone, seconds in pairs(old.zones or {}) do
			if seconds > topTime then
				topZone, topTime = zone, seconds
			end
		end
		old.zone = topZone
		Ledger:Archive(old)
	end

	self:Begin()
	self.clockStart = nil
	self:StartClock()

	if LibsFarmAssistant.ResetGoalCompletion then
		LibsFarmAssistant:ResetGoalCompletion()
	end
	LibsFarmAssistant:SendMessage('LIBSFA_SESSION_STARTED')
	LibsFarmAssistant:UpdateDisplay()
	if not quiet then
		LibsFarmAssistant:Print('New session started.')
	end
end

-- Fires on every loading screen; only the first one, at login or after a reload, matters.
function SessionManager:OnEnteringWorld(_, _, isReloadingUi)
	if self.enteredWorld then
		return
	end
	self.enteredWorld = true
	if isReloadingUi then
		-- A reload is not a login: keep the state and only act on what changes from here
		self.lastReason = self:AutoPauseReason()
		return
	end
	self:ApplyStartMode()
	self:UpdateAutoPause()
end

---At login the player's choice decides, whatever state the last session was left in: track at once,
---wait for the first kill, or stay paused until they resume.
function SessionManager:ApplyStartMode()
	local mode = LibsFarmAssistant.db.session.startMode
	local session = self:Get()
	if mode == 'manual' or mode == 'kill' then
		self:SetPaused(true, true)
		session.pausedFor = mode == 'kill' and 'kill' or nil
	else
		self:SetPaused(false, true)
	end
	LibsFarmAssistant:SendMessage('LIBSFA_SESSION_STATE')
end

---Starts tracking on a kill when the player chose to start that way. Called before the kill is
---counted, so the first kill is part of the session.
function SessionManager:StartOnKill()
	if self:PausedFor() == 'kill' then
		self:SetPaused(false, true)
		LibsFarmAssistant:Print('First kill. Tracking started.')
	end
end

---@return string|nil reason 'away' or 'resting' when tracking should pause by itself
function SessionManager:AutoPauseReason()
	local settings = LibsFarmAssistant.db.session
	if settings.pauseWhenAFK then
		local afk = UnitIsAFK('player')
		if Compat.CanAccess(afk) and afk then
			return 'away'
		end
	end
	if settings.pauseWhenResting and IsResting then
		local resting = IsResting()
		if Compat.CanAccess(resting) and resting then
			return 'resting'
		end
	end
	return nil
end

---Pauses while away or resting and resumes afterwards. Acts only when the reason changes, so a
---player who resumes by hand in town is not paused again until they leave and come back.
function SessionManager:UpdateAutoPause(event, unit)
	if event == 'PLAYER_FLAGS_CHANGED' and unit and unit ~= 'player' then
		return
	end
	local reason = self:AutoPauseReason()
	if reason == self.lastReason then
		return
	end
	local previous = self.lastReason
	self.lastReason = reason
	local session = self:Get()

	if reason then
		if self:IsActive() then
			self:SetPaused(true, true, reason)
			LibsFarmAssistant:Print(reason == 'away' and 'Tracking paused while you are away.' or 'Tracking paused while you rest.')
		elseif AUTO_PAUSE[session.pausedFor] then
			session.pausedFor = reason
			LibsFarmAssistant:SendMessage('LIBSFA_SESSION_STATE')
		end
	elseif AUTO_PAUSE[session.pausedFor] and not self:IsActive() then
		self:SetPaused(false, true)
		LibsFarmAssistant:Print(previous == 'away' and 'Welcome back. Tracking resumed.' or 'Tracking resumed.')
	end
end

---Prints the current session to chat.
function SessionManager:PrintSummary()
	local session = self:Get()
	self:Flush()
	local total = Ledger.ItemCounts(session)
	local value = Ledger.TotalValue(session)
	local perHour = Ledger.PerHour(value, session)

	LibsFarmAssistant:Print(string.format('Session: %s farming', Format.Duration(self:Duration())))
	LibsFarmAssistant:Print(string.format('  Value: %s%s', Format.Money(value), perHour and (' (' .. Format.Money(perHour) .. ' per hour)') or ''))
	if total > 0 then
		LibsFarmAssistant:Print(string.format('  Items: %s', Format.Number(total)))
	end
	if session.kills > 0 then
		LibsFarmAssistant:Print(string.format('  Kills: %s', Format.Number(session.kills)))
	end
	if session.xp > 0 then
		local perKill = LibsFarmAssistant.ExperienceTracker:PerKill()
		LibsFarmAssistant:Print(string.format('  Experience: %s%s', Format.Number(session.xp), perKill and (' (' .. Format.Number(math.floor(perKill + 0.5)) .. ' per kill at this level)') or ''))
	end
	local rep = Ledger.RepTotal(session)
	if rep > 0 then
		LibsFarmAssistant:Print(string.format('  Reputation: %s', Format.Number(rep)))
	end
	if session.honor > 0 then
		LibsFarmAssistant:Print(string.format('  Honor: %s', Format.Number(session.honor)))
	end
end

-- Bridges used by the UI and the older modules
function LibsFarmAssistant:IsSessionActive()
	return self.SessionManager:IsActive()
end

function LibsFarmAssistant:ToggleSession()
	self.SessionManager:Toggle()
end

function LibsFarmAssistant:ResetSession()
	self.SessionManager:NewSession()
end

function LibsFarmAssistant:GetSessionDuration()
	return self.SessionManager:Duration()
end

function LibsFarmAssistant:PrintSummary()
	self.SessionManager:PrintSummary()
end
