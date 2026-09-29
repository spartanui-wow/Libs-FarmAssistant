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

function SessionManager:OnInitialize()
	self.clockStart = nil -- GetTime() when the clock last started running
	self.autoPaused = false
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
	self:RegisterEvent('PLAYER_FLAGS_CHANGED', 'OnFlagsChanged')
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
function SessionManager:SetPaused(paused, silent)
	local session = self:Get()
	if paused == (session.active == false) then
		return
	end
	self:Flush()
	if paused then
		session.active = false
		self.clockStart = nil
	else
		session.active = true
		self.autoPaused = false
		self:StartClock()
	end
	if not silent then
		LibsFarmAssistant:Print(paused and 'Tracking paused.' or 'Tracking resumed.')
	end
	LibsFarmAssistant:SendMessage('LIBSFA_SESSION_STATE')
	LibsFarmAssistant:UpdateDisplay()
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
	self.autoPaused = false
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

function SessionManager:OnFlagsChanged(_, unit)
	if unit and unit ~= 'player' then
		return
	end
	if not LibsFarmAssistant.db.session.pauseWhenAFK then
		return
	end
	local afk = UnitIsAFK('player')
	if not Compat.CanAccess(afk) then
		return
	end
	if afk and self:IsActive() then
		self.autoPaused = true
		self:SetPaused(true, true)
		LibsFarmAssistant:Print('Tracking paused while you are away.')
	elseif not afk and self.autoPaused and not self:IsActive() then
		self:SetPaused(false, true)
		LibsFarmAssistant:Print('Welcome back. Tracking resumed.')
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
		LibsFarmAssistant:Print(string.format('  Experience: %s', Format.Number(session.xp)))
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
