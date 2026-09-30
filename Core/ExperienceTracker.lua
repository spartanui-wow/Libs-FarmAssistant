---@class LibsFarmAssistant
local LibsFarmAssistant = LibStub('AceAddon-3.0'):GetAddon('Libs-FarmAssistant')

-- Experience is measured from the bar itself, so every source counts (kills, quests, gathering,
-- exploring) and level-ups carry the overflow into the next level.
--
-- Experience per kill is kept for the current level only: what a mob is worth changes with the
-- player's level, so the record starts over on every level-up. Kills and experience arrive as
-- separate events in no fixed order, and several kills can share one bar update, so they are
-- gathered into short bursts and paired when the burst goes quiet.

---@class LibsFarmAssistant.ExperienceTracker : AceModule, AceEvent-3.0, AceTimer-3.0
local ExperienceTracker = LibsFarmAssistant:NewModule('ExperienceTracker')
LibsFarmAssistant.ExperienceTracker = ExperienceTracker

local Compat = LibsFarmAssistant.Compat
local Ledger = LibsFarmAssistant.Ledger

local BURST_QUIET = 1
local BURST_LONGEST = 6

---@class FarmLevelXP
---@field level number
---@field xp number Experience from kills at this level, rested bonus included
---@field rested number The rested bonus part of xp
---@field kills number Kills that gave experience
---@field sources table<string, { xp: number, kills: number }>

local function Rested()
	return GetXPExhaustion and GetXPExhaustion() or 0
end

function ExperienceTracker:OnEnable()
	self:Snapshot()
	self:RegisterEvent('PLAYER_XP_UPDATE', 'OnXP')
	self:RegisterEvent('PLAYER_LEVEL_UP', 'OnLevelUp')
	self:RegisterEvent('PLAYER_ENTERING_WORLD', 'Snapshot')
	Compat.RegisterEvent(self, 'UPDATE_EXHAUSTION', 'OnExhaustion')
	Compat.RegisterEvent(self, 'QUEST_TURNED_IN', 'OnQuestTurnedIn')
	self:RegisterMessage('LIBSFA_ATTEMPT', 'OnKill')
end

function ExperienceTracker:Snapshot()
	self.level = UnitLevel('player')
	self.xp = UnitXP('player')
	self.max = UnitXPMax('player')
	if not self.burst then
		self.rested = Rested()
	end
end

function ExperienceTracker:OnLevelUp(_, level)
	self.leveledTo = level
end

-- The rested pool can shrink a moment before the kill that used it is seen, so the value from
-- just before the change is kept for a burst that opens right after.
function ExperienceTracker:OnExhaustion()
	if self.burst then
		return
	end
	self.restedBefore, self.restedAt = self.rested, GetTime()
	self.rested = Rested()
end

function ExperienceTracker:OnXP(_, unit)
	if unit and unit ~= 'player' then
		return
	end
	local level, xp, max = UnitLevel('player'), UnitXP('player'), UnitXPMax('player')
	local gained
	if level > (self.level or level) or self.leveledTo then
		gained = math.max(0, (self.max or 0) - (self.xp or 0)) + xp
	else
		gained = xp - (self.xp or xp)
	end
	self.level, self.xp, self.max = math.max(level, self.leveledTo or level), xp, max
	self.leveledTo = nil

	if gained > 0 and LibsFarmAssistant:IsSessionActive() and LibsFarmAssistant.db.tracking.experience then
		Ledger:AddXP(gained)
		local burst = self:Burst()
		burst.xp = burst.xp + gained
		burst.gains = burst.gains + 1
		LibsFarmAssistant:UpdateDisplay()
	end
end

function ExperienceTracker:OnKill(_, key)
	if type(key) ~= 'string' or key:sub(1, 2) ~= 'c:' or not Compat.CanGainXP() then
		return
	end
	local burst = self:Burst()
	burst.kills = burst.kills + 1
	burst.sources[key] = (burst.sources[key] or 0) + 1
end

function ExperienceTracker:OnQuestTurnedIn(_, _, xpReward)
	xpReward = Compat.Readable(xpReward)
	if type(xpReward) == 'number' and xpReward > 0 then
		local burst = self:Burst()
		burst.quest = burst.quest + xpReward
		burst.quests = burst.quests + 1
	end
end

---The open burst, opening one if needed. Every event pushes its end back, up to a limit.
function ExperienceTracker:Burst()
	local now = GetTime()
	local burst = self.burst
	if not burst then
		local rested = self.rested or Rested()
		if self.restedAt and now - self.restedAt <= BURST_QUIET and self.restedBefore then
			rested = math.max(rested, self.restedBefore)
		end
		burst = { level = UnitLevel('player'), rested = rested, started = now, xp = 0, gains = 0, quest = 0, quests = 0, kills = 0, sources = {} }
		self.burst = burst
	end
	if self.burstTimer then
		self:CancelTimer(self.burstTimer)
	end
	local wait = math.max(0, math.min(BURST_QUIET, burst.started + BURST_LONGEST - now))
	self.burstTimer = self:ScheduleTimer('CloseBurst', wait)
	return burst
end

function ExperienceTracker:CloseBurst()
	local burst = self.burst
	self.burst, self.burstTimer = nil, nil
	local restedNow = Rested()
	self.rested, self.restedBefore, self.restedAt = restedNow, nil, nil
	if not burst or burst.kills == 0 or burst.level ~= UnitLevel('player') then
		return
	end
	local xp = burst.xp - burst.quest
	if xp <= 0 then
		return
	end
	-- Kills can be counted late (from the corpse) or several can share one bar update, so the
	-- larger of the two counts is the number of kills this experience came from.
	local kills = math.max(burst.kills, burst.gains - burst.quests)
	local rested = math.max(0, math.min(burst.rested - restedNow, xp / 2))

	local record = self:LevelRecord()
	record.xp = record.xp + xp
	record.rested = record.rested + rested
	record.kills = record.kills + kills
	local each = xp / kills
	for key, count in pairs(burst.sources) do
		local source = record.sources[key]
		if not source then
			source = { xp = 0, kills = 0 }
			record.sources[key] = source
		end
		source.xp = source.xp + each * count
		source.kills = source.kills + count
	end
	LibsFarmAssistant:UpdateDisplay()
end

---This level's kill record, started fresh when the level changed.
---@return FarmLevelXP
function ExperienceTracker:LevelRecord()
	local char = LibsFarmAssistant.char
	local level = UnitLevel('player')
	local record = char.levelXP
	if type(record) ~= 'table' or record.level ~= level then
		record = { level = level, xp = 0, rested = 0, kills = 0, sources = {} }
		char.levelXP = record
	end
	return record
end

---Average experience per kill at this level.
---@return number|nil perKill Rested bonus included, as it was earned
---@return number|nil base Without the rested bonus
---@return number kills How many kills the average is built from
function ExperienceTracker:PerKill()
	local record = self:LevelRecord()
	if record.kills < 1 or record.xp <= 0 then
		return nil, nil, record.kills
	end
	return record.xp / record.kills, (record.xp - record.rested) / record.kills, record.kills
end

---Average experience per kill of one creature at this level.
---@param key string
---@return number|nil perKill
---@return number kills
function ExperienceTracker:SourcePerKill(key)
	local source = self:LevelRecord().sources[key]
	if not source or source.kills < 1 then
		return nil, 0
	end
	return source.xp / source.kills, source.kills
end

---Kills left to the next level at this level's average. Rested experience doubles a kill until
---the pool runs out, so the pool is spent first.
---@return number|nil
function ExperienceTracker:KillsToLevel()
	local _, base = self:PerKill()
	if not base or base <= 0 or not Compat.CanGainXP() then
		return nil
	end
	local status = self:Status()
	local remaining = status.max - status.current
	if remaining <= 0 then
		return nil
	end
	local kills
	if status.rested >= remaining / 2 then
		kills = remaining / (2 * base)
	else
		kills = (remaining - status.rested) / base
	end
	return math.max(1, math.ceil(kills))
end

---@class FarmXPStatus
---@field level number
---@field current number
---@field max number
---@field rested number
---@field canGain boolean

---@return FarmXPStatus
function ExperienceTracker:Status()
	return {
		level = UnitLevel('player'),
		current = UnitXP('player'),
		max = math.max(1, UnitXPMax('player')),
		rested = Rested(),
		canGain = Compat.CanGainXP(),
	}
end

---Seconds to the next level at the pace of this bucket, and kills at this level's average.
---@param bucket FarmBucket
---@return number|nil seconds
---@return number|nil kills
function ExperienceTracker:TimeToLevel(bucket)
	local status = self:Status()
	local remaining = status.max - status.current
	local perHour = Ledger.PerHour(bucket.xp, bucket)
	local seconds = perHour and perHour > 0 and (remaining / perHour * 3600) or nil
	return seconds, self:KillsToLevel()
end
