---@class LibsFarmAssistant
local LibsFarmAssistant = LibStub('AceAddon-3.0'):GetAddon('Libs-FarmAssistant')

-- Experience is measured from the bar itself, so every source counts (kills, quests, gathering,
-- exploring) and level-ups carry the overflow into the next level.

---@class LibsFarmAssistant.ExperienceTracker : AceModule, AceEvent-3.0
local ExperienceTracker = LibsFarmAssistant:NewModule('ExperienceTracker')
LibsFarmAssistant.ExperienceTracker = ExperienceTracker

local Compat = LibsFarmAssistant.Compat
local Ledger = LibsFarmAssistant.Ledger

function ExperienceTracker:OnEnable()
	self:Snapshot()
	self:RegisterEvent('PLAYER_XP_UPDATE', 'OnXP')
	self:RegisterEvent('PLAYER_LEVEL_UP', 'OnLevelUp')
	self:RegisterEvent('PLAYER_ENTERING_WORLD', 'Snapshot')
end

function ExperienceTracker:Snapshot()
	self.level = UnitLevel('player')
	self.xp = UnitXP('player')
	self.max = UnitXPMax('player')
end

function ExperienceTracker:OnLevelUp(_, level)
	self.leveledTo = level
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
		LibsFarmAssistant:UpdateDisplay()
	end
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
		rested = GetXPExhaustion and GetXPExhaustion() or 0,
		canGain = Compat.CanGainXP(),
	}
end

---Seconds and kills to the next level at the pace of this bucket, or nil without a pace yet.
---@param bucket FarmBucket
---@return number|nil seconds
---@return number|nil kills
function ExperienceTracker:TimeToLevel(bucket)
	local status = self:Status()
	local remaining = status.max - status.current
	local perHour = Ledger.PerHour(bucket.xp, bucket)
	local seconds = perHour and perHour > 0 and (remaining / perHour * 3600) or nil
	local kills = bucket.kills > 0 and bucket.xp > 0 and math.ceil(remaining / (bucket.xp / bucket.kills)) or nil
	return seconds, kills
end
