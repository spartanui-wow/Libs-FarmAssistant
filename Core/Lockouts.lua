---@class LibsFarmAssistant
local LibsFarmAssistant = LibStub('AceAddon-3.0'):GetAddon('Libs-FarmAssistant')

-- Raid, dungeon and world boss lockouts for every character on the account. Weekly mount farms
-- are run on many characters, so each character's saves and hunt counts are kept account-wide:
-- the Hunts page can then say which characters can still try this week and when the others reset.
-- Bosses are matched by name, the one thing both the lockout list and the kill events share.

---@class FarmLockoutBoss
---@field name string
---@field killed boolean

---@class FarmLockout
---@field instance string
---@field difficulty string
---@field raid boolean
---@field reset number epoch when it ends
---@field bosses FarmLockoutBoss[]

---@class FarmCharacter
---@field name string
---@field realm string
---@field class string|nil class file name
---@field level number
---@field scanned number|nil epoch of the last lockout scan
---@field lockouts FarmLockout[]
---@field hunts table<string, table> itemID -> { attempts, total, week, weekKey, found, updated }

---@class LibsFarmAssistant.Lockouts : AceModule, AceEvent-3.0, AceTimer-3.0
local Lockouts = LibsFarmAssistant:NewModule('Lockouts')
LibsFarmAssistant.Lockouts = Lockouts

local Compat = LibsFarmAssistant.Compat
local Ledger = LibsFarmAssistant.Ledger

local REQUEST_DELAY = 3

function Lockouts:OnEnable()
	self:Profile()
	self:RegisterEvent('UPDATE_INSTANCE_INFO', 'Scan')
	self:RegisterEvent('PLAYER_LEVEL_UP', 'Profile')
	Compat.RegisterEvent(self, 'BOSS_KILL', 'RequestSoon')
	Compat.RegisterEvent(self, 'ENCOUNTER_END', 'OnEncounterEnd')
	self:RegisterEvent('PLAYER_LOGOUT', 'SaveAllHunts')
	self:RegisterMessage('LIBSFA_HUNTS_CHANGED', 'SaveAllHunts')
	self:SaveAllHunts()
	self:Request()
end

---@return string
function Lockouts:CharKey()
	local keys = LibsFarmAssistant.dbobj and LibsFarmAssistant.dbobj.keys
	return (keys and keys.char) or ((UnitName('player') or '?') .. ' - ' .. (GetRealmName and GetRealmName() or ''))
end

---@return table<string, FarmCharacter>
local function Characters()
	return LibsFarmAssistant.global.characters
end

---This character's account-wide entry.
---@return FarmCharacter
function Lockouts:Me()
	local all = Characters()
	local key = self:CharKey()
	local me = all[key]
	if not me then
		me = { lockouts = {}, hunts = {} }
		all[key] = me
	end
	me.lockouts = me.lockouts or {}
	me.hunts = me.hunts or {}
	return me
end

function Lockouts:Profile()
	local me = self:Me()
	me.name = UnitName('player') or me.name
	me.realm = GetRealmName and GetRealmName() or me.realm or ''
	local _, class = UnitClass('player')
	me.class = class or me.class
	me.level = UnitLevel('player') or me.level or 0
end

function Lockouts:Request()
	if RequestRaidInfo then
		RequestRaidInfo()
	end
end

---Saves update a moment after a kill, so ask again shortly afterwards.
function Lockouts:RequestSoon()
	if self.requestTimer then
		return
	end
	self.requestTimer = self:ScheduleTimer(function()
		self.requestTimer = nil
		self:Request()
	end, REQUEST_DELAY)
end

function Lockouts:OnEncounterEnd(_, _, _, _, _, success)
	if success == 1 then
		self:RequestSoon()
	end
end

---Reads this character's saved instances and world bosses.
function Lockouts:Scan()
	local now = time()
	local list = {}
	local count = GetNumSavedInstances and GetNumSavedInstances() or 0
	for index = 1, count do
		local name, _, reset, _, locked, extended, _, isRaid, _, difficultyName, numEncounters = GetSavedInstanceInfo(index)
		if name and (locked or extended) and reset and reset > 0 then
			local lockout = { instance = name, difficulty = difficultyName or '', raid = isRaid and true or false, reset = now + reset, bosses = {} }
			for encounter = 1, numEncounters or 0 do
				local bossName, _, isKilled = GetSavedInstanceEncounterInfo(index, encounter)
				if bossName then
					lockout.bosses[#lockout.bosses + 1] = { name = bossName, killed = isKilled and true or false }
				end
			end
			list[#list + 1] = lockout
		end
	end
	local worldBosses = GetNumSavedWorldBosses and GetNumSavedWorldBosses() or 0
	for index = 1, worldBosses do
		local name, _, reset = GetSavedWorldBossInfo(index)
		if name and reset and reset > 0 then
			list[#list + 1] = { instance = name, difficulty = 'World boss', raid = false, reset = now + reset, bosses = { { name = name, killed = true } } }
		end
	end

	local me = self:Me()
	me.lockouts = list
	me.scanned = now
	self:Profile()
	LibsFarmAssistant:SendMessage('LIBSFA_LOCKOUTS_UPDATED')
	LibsFarmAssistant:UpdateDisplay()
end

----------------------------------------------------------------------------------------------------
-- Hunts across characters
----------------------------------------------------------------------------------------------------

---Stores this character's count for a hunt where other characters can read it.
---@param hunt FarmHunt
function Lockouts:SaveHunt(hunt)
	local me = self:Me()
	local weekKey = Ledger.WeekStartKey()
	me.hunts[tostring(hunt.id)] = {
		attempts = hunt.attempts or 0,
		total = hunt.totalAttempts or 0,
		week = hunt.weekKey == weekKey and (hunt.weekAttempts or 0) or 0,
		weekKey = weekKey,
		found = #(hunt.found or {}),
		updated = time(),
	}
end

function Lockouts:SaveAllHunts()
	local me = self:Me()
	local current = {}
	for key, hunt in pairs(LibsFarmAssistant.char.hunts) do
		current[key] = true
		self:SaveHunt(hunt)
	end
	for key in pairs(me.hunts) do
		if not current[key] then
			me.hunts[key] = nil
		end
	end
end

---Lower-case names of every boss that has a lockout or an encounter on this account.
---@return table<string, boolean>
local function LockoutBossNames()
	local set = {}
	for _, entry in pairs(Characters()) do
		for _, lockout in ipairs(entry.lockouts or {}) do
			for _, boss in ipairs(lockout.bosses) do
				set[boss.name:lower()] = true
			end
		end
	end
	for key, meta in pairs(LibsFarmAssistant.global.sourceMeta) do
		if key:sub(1, 2) == 'e:' and meta.n then
			set[meta.n:lower()] = true
		end
	end
	return set
end

---Lower-case boss names a hunt is linked to: bosses picked by name, its encounter sources, and
---creature sources that are bosses with a lockout (never ordinary mobs).
---@param hunt FarmHunt
---@return table<string, string> lowerName -> display name
function Lockouts:BossNames(hunt)
	local names = {}
	for lower, display in pairs(hunt.bosses or {}) do
		names[lower] = display
	end
	local bosses
	for key in pairs(hunt.sources or {}) do
		local prefix = key:sub(1, 2)
		if prefix == 'c:' or prefix == 'e:' then
			local meta = LibsFarmAssistant.global.sourceMeta[key]
			if meta and meta.n then
				bosses = bosses or LockoutBossNames()
				if prefix == 'e:' or bosses[meta.n:lower()] then
					names[meta.n:lower()] = meta.n
				end
			end
		end
	end
	return names
end

---@param hunt FarmHunt
---@return boolean
function Lockouts:HasBosses(hunt)
	return next(self:BossNames(hunt)) ~= nil
end

---Whether a character has already killed one of the named bosses on a lockout that has not reset.
---@param entry FarmCharacter
---@param names table<string, string>
---@return string status 'done', 'open' or 'unknown'
---@return number|nil reset epoch
---@return FarmLockout|nil lockout
function Lockouts:Status(entry, names)
	if not entry.scanned then
		return 'unknown'
	end
	local now = time()
	local best
	for _, lockout in ipairs(entry.lockouts or {}) do
		if lockout.reset > now then
			for _, boss in ipairs(lockout.bosses) do
				if boss.killed and names[boss.name:lower()] and (not best or lockout.reset > best.reset) then
					best = lockout
				end
			end
		end
	end
	if best then
		return 'done', best.reset, best
	end
	return 'open'
end

---This character's lockout for a hunt, when it has one.
---@param hunt FarmHunt
---@return string|nil status 'done' or 'open', nil when the hunt has no boss
---@return number|nil reset
function Lockouts:MyStatus(hunt)
	local names = self:BossNames(hunt)
	if not next(names) then
		return nil
	end
	local status, reset = self:Status(self:Me(), names)
	return status, reset
end

---@class FarmHuntCharacterRow
---@field key string
---@field name string
---@field realm string
---@field class string|nil
---@field level number
---@field current boolean
---@field status string 'done', 'open' or 'unknown'
---@field reset number|nil
---@field lockout FarmLockout|nil
---@field attempts number
---@field week number
---@field total number
---@field hasHunt boolean

---Every character that hunts this item (and the current one), with their lockout and counts.
---@param hunt FarmHunt
---@return FarmHuntCharacterRow[]
function Lockouts:HuntRows(hunt)
	self:SaveHunt(hunt)
	local names = self:BossNames(hunt)
	local id = tostring(hunt.id)
	local myKey = self:CharKey()
	local weekKey = Ledger.WeekStartKey()
	local rows = {}
	for key, entry in pairs(Characters()) do
		local counts = entry.hunts and entry.hunts[id]
		if counts or key == myKey then
			local status, reset, lockout = 'unknown', nil, nil
			if next(names) then
				status, reset, lockout = self:Status(entry, names)
			end
			rows[#rows + 1] = {
				key = key,
				name = entry.name or key,
				realm = entry.realm or '',
				class = entry.class,
				level = entry.level or 0,
				current = key == myKey,
				status = status,
				reset = reset,
				lockout = lockout,
				attempts = counts and counts.attempts or 0,
				week = counts and counts.weekKey == weekKey and counts.week or 0,
				total = counts and counts.total or 0,
				hasHunt = counts ~= nil,
			}
		end
	end
	table.sort(rows, function(a, b)
		if a.current ~= b.current then
			return a.current
		end
		if a.status ~= b.status then
			return a.status == 'open'
		end
		return a.name < b.name
	end)
	return rows
end

---@class FarmHuntAccount
---@field characters number characters hunting it
---@field open number of those, how many can still kill the boss before reset
---@field done number
---@field total number all attempts on the account
---@field week number attempts this week on the account

---@param hunt FarmHunt
---@return FarmHuntAccount
function Lockouts:Summary(hunt)
	local summary = { characters = 0, open = 0, done = 0, total = 0, week = 0 }
	for _, row in ipairs(self:HuntRows(hunt)) do
		if row.hasHunt then
			summary.characters = summary.characters + 1
			summary.total = summary.total + row.total
			summary.week = summary.week + row.week
			if row.status == 'open' then
				summary.open = summary.open + 1
			elseif row.status == 'done' then
				summary.done = summary.done + 1
			end
		end
	end
	return summary
end

---Bosses the player can link a hunt to: kills this lockout and recent boss encounters.
---@return table[] list of { name, detail, key }
function Lockouts:KnownBosses()
	local list, seen = {}, {}
	local function Add(name, detail, key)
		if name and name ~= '' and not seen[name:lower()] then
			seen[name:lower()] = true
			list[#list + 1] = { name = name, detail = detail, key = key }
		end
	end
	for _, entry in pairs(Characters()) do
		for _, lockout in ipairs(entry.lockouts or {}) do
			for _, boss in ipairs(lockout.bosses) do
				local detail = lockout.instance
				if lockout.difficulty ~= '' and lockout.difficulty ~= 'World boss' then
					detail = detail .. ', ' .. lockout.difficulty
				elseif lockout.difficulty == 'World boss' then
					detail = 'World boss'
				end
				Add(boss.name, detail)
			end
		end
	end
	for key, meta in pairs(LibsFarmAssistant.global.sourceMeta) do
		if key:sub(1, 2) == 'e:' then
			Add(meta.n, 'Boss you killed', key)
		end
	end
	table.sort(list, function(a, b)
		return a.name < b.name
	end)
	return list
end
