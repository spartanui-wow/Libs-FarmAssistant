---@class LibsFarmAssistant
local LibsFarmAssistant = LibStub('AceAddon-3.0'):GetAddon('Libs-FarmAssistant')

-- Reputation gains are measured, not read: every faction is folded into one ever-growing total
-- (standing value, renown levels, paragon progress), and a gain is the difference between two
-- readings. That catches bonuses, account-wide gains and renown level-ups in every language.
-- The chat line is only a hint for which faction moved, and its amount is used when a faction
-- was never read before.

---@class LibsFarmAssistant.ReputationTracker : AceModule, AceEvent-3.0, AceTimer-3.0
local ReputationTracker = LibsFarmAssistant:NewModule('ReputationTracker')
LibsFarmAssistant.ReputationTracker = ReputationTracker

local Compat = LibsFarmAssistant.Compat
local Ledger = LibsFarmAssistant.Ledger

local CHAT_FORMATS = {
	'FACTION_STANDING_INCREASED_ACH_BONUS_ACCOUNT_WIDE',
	'FACTION_STANDING_INCREASED_ACCOUNT_WIDE',
	'FACTION_STANDING_INCREASED_DOUBLE_BONUS',
	'FACTION_STANDING_INCREASED_ACH_BONUS',
	'FACTION_STANDING_INCREASED_BONUS',
	'FACTION_STANDING_INCREASED',
}

function ReputationTracker:OnEnable()
	self.totals = {} -- factionID -> last total read
	self.firstRead = {} -- factionID -> GetTime() of a first reading that had nothing to compare with
	self.nameToID = {}
	self.scanned = false
	self.patterns = {}
	for _, key in ipairs(CHAT_FORMATS) do
		local pattern = Compat.FormatToPattern(_G[key])
		if pattern then
			self.patterns[#self.patterns + 1] = pattern
		end
	end

	self:RegisterEvent('PLAYER_ENTERING_WORLD', 'Prime')
	self:RegisterEvent('UPDATE_FACTION', 'OnUpdateFaction')
	self:RegisterEvent('CHAT_MSG_COMBAT_FACTION_CHANGE', 'OnChat')
	Compat.RegisterEvent(self, 'FACTION_STANDING_CHANGED', 'OnStandingChanged')
	Compat.RegisterEvent(self, 'MAJOR_FACTION_RENOWN_LEVEL_CHANGED', 'OnStandingChanged')
	self:Prime()
end

---Reads every faction the player can see so the next gain on any of them is exact.
function ReputationTracker:Prime()
	Compat.ForEachListedFaction(function(factionID)
		self:Read(factionID)
	end)
	if C_MajorFactions and C_MajorFactions.GetMajorFactionIDs then
		local ids = C_MajorFactions.GetMajorFactionIDs()
		for _, factionID in ipairs(ids or {}) do
			self:Read(factionID)
		end
	end
	for factionID in pairs(LibsFarmAssistant.char.factionTotals) do
		self:Read(factionID)
	end
end

---Reads a faction without recording anything.
---@param factionID number
---@return FarmFactionProgress|nil
function ReputationTracker:Read(factionID)
	local p = Compat.FactionProgress(factionID)
	if p then
		self.totals[factionID] = p.total
		self.nameToID[p.name] = factionID
	end
	return p
end

---Reads a faction and records the gain since the last reading.
---@param factionID number
---@return number|nil gained
function ReputationTracker:Check(factionID)
	local before = self.totals[factionID]
	local p = Compat.FactionProgress(factionID)
	if not p then
		return nil
	end
	self.totals[factionID] = p.total
	self.nameToID[p.name] = factionID
	if not before then
		self.firstRead[factionID] = GetTime()
		return nil
	end
	if p.total > before then
		local gained = p.total - before
		self:Record(factionID, gained)
		return gained
	end
	return 0
end

---@param factionID number
---@param amount number
function ReputationTracker:Record(factionID, amount)
	-- Remember the faction for next login, so its first gain then is exact too.
	LibsFarmAssistant.char.factionTotals[factionID] = true
	if not LibsFarmAssistant:IsSessionActive() or not LibsFarmAssistant.db.tracking.reputation then
		return
	end
	Ledger:AddRep(factionID, amount)
	LibsFarmAssistant:SendMessage('LIBSFA_REP_GAINED', factionID, amount)
	LibsFarmAssistant:UpdateDisplay()
end

function ReputationTracker:OnStandingChanged(_, factionID)
	factionID = Compat.Readable(factionID)
	if factionID then
		self:Check(factionID)
	end
end

function ReputationTracker:OnUpdateFaction()
	if self.updateTimer then
		return
	end
	self.updateTimer = self:ScheduleTimer(function()
		self.updateTimer = nil
		for factionID in pairs(self.totals) do
			self:Check(factionID)
		end
	end, 0.3)
end

---Finds a faction ID by its displayed name, scanning every faction ID once if needed.
---@param name string
---@return number|nil
function ReputationTracker:IDForName(name)
	if self.nameToID[name] then
		return self.nameToID[name]
	end
	if not self.scanned then
		self.scanned = true
		for factionID = 1, Compat.MAX_FACTION_ID do
			local factionName = Compat.FactionName(factionID)
			if factionName and not self.nameToID[factionName] then
				self.nameToID[factionName] = factionID
			end
		end
	end
	return self.nameToID[name]
end

---@param text string
---@return string|nil name
---@return number|nil amount
function ReputationTracker:ParseChat(text)
	for _, pattern in ipairs(self.patterns) do
		local name, amount, bonus = text:match(pattern)
		if name then
			local total = Compat.ParseNumber(amount) or 0
			local extra = bonus and tonumber((bonus:gsub(',', ''))) or 0
			return name, math.floor(total + extra + 0.5)
		end
	end
	return nil
end

function ReputationTracker:OnChat(_, text)
	if type(text) ~= 'string' or not Compat.CanAccess(text) then
		return
	end
	local name, amount = self:ParseChat(text)
	if not name then
		return
	end
	local factionID = self:IDForName(name)
	if not factionID then
		return
	end
	-- The standing data can update a moment after the chat line.
	self:ScheduleTimer(function()
		local gained = self:Check(factionID)
		local first = self.firstRead[factionID]
		if (gained == nil or (gained == 0 and first and GetTime() - first < 2)) and amount and amount > 0 then
			self.firstRead[factionID] = nil
			self:Record(factionID, amount)
		end
	end, 0.3)
end

---@class FarmRepGain
---@field factionID number
---@field gained number
---@field progress FarmFactionProgress
---@field perHour number|nil
---@field remaining number
---@field seconds number|nil time to the next step at this pace
---@field kills number|nil kills to the next step at this pace
---@field nextLabel string

---What comes after the faction's current step, in words.
---@param p FarmFactionProgress
---@return string
function ReputationTracker:NextLabel(p)
	if p.kind == 'paragon' then
		return 'reward'
	elseif p.kind == 'renown' then
		return 'Renown ' .. (p.level + 1)
	elseif p.kind == 'friendship' then
		return 'next rank'
	end
	local label = _G['FACTION_STANDING_LABEL' .. math.min(8, p.level + 1)]
	return label or 'next standing'
end

---Factions that gained reputation in the bucket, most gained first, with pace estimates.
---@param bucket FarmBucket
---@return FarmRepGain[]
function ReputationTracker:Gains(bucket)
	local list = {}
	for factionID, gained in pairs(bucket.rep) do
		local p = Compat.FactionProgress(factionID)
		if p then
			local perHour = Ledger.PerHour(gained, bucket)
			local remaining = p.capped and 0 or math.max(0, p.max - p.value)
			list[#list + 1] = {
				factionID = factionID,
				gained = gained,
				progress = p,
				perHour = perHour,
				remaining = remaining,
				seconds = perHour and perHour > 0 and remaining > 0 and (remaining / perHour * 3600) or nil,
				kills = bucket.kills > 0 and remaining > 0 and math.ceil(remaining / (gained / bucket.kills)) or nil,
				perKill = bucket.kills > 0 and gained / bucket.kills or nil,
				nextLabel = self:NextLabel(p),
			}
		end
	end
	table.sort(list, function(a, b)
		return a.gained > b.gained
	end)
	return list
end
