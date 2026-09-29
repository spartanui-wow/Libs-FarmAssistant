---@class LibsFarmAssistant
local LibsFarmAssistant = LibStub('AceAddon-3.0'):GetAddon('Libs-FarmAssistant')

-- Knows what things are and when they die. Every creature is counted once per GUID no matter
-- how many signals report it (a kill event, a target death, looting the corpse, skinning it),
-- which keeps "1 in N" drop rates honest.
--
-- Source keys: c:<npcID> creature, o:<objectID> node or chest, f:<zone> fishing,
-- i container opened from bags, e:<encounterID> boss encounter, q rewards and other.

---@class LibsFarmAssistant.Sources : AceModule, AceEvent-3.0
local Sources = LibsFarmAssistant:NewModule('Sources')
LibsFarmAssistant.Sources = Sources

local Compat = LibsFarmAssistant.Compat
local Ledger = LibsFarmAssistant.Ledger

local CACHE_LIMIT = 4000
local RECENT_KILL_WINDOW = 20

local names = {} -- guid -> name
local nameCount = 0
local counted = {} -- guid -> true once the kill has been counted
local countedCount = 0
local recentEncounters = {} -- encounterID -> GetTime()

local NAME_UNITS = { 'target', 'mouseover', 'focus', 'softenemy', 'softinteract', 'pettarget' }

function Sources:OnEnable()
	self.lastKill = nil -- { key = sourceKey, at = GetTime() }

	Compat.RegisterEvent(self, 'PARTY_KILL', 'OnPartyKill')
	self:RegisterEvent('PLAYER_TARGET_CHANGED', 'OnUnitSeen', 'target')
	self:RegisterEvent('UPDATE_MOUSEOVER_UNIT', 'OnUnitSeen', 'mouseover')
	self:RegisterEvent('NAME_PLATE_UNIT_ADDED', 'OnNameplate')
	Compat.RegisterEvent(self, 'BOSS_KILL', 'OnBossKill')
	Compat.RegisterEvent(self, 'ENCOUNTER_END', 'OnEncounterEnd')
	if Compat.IsRetail then
		Compat.RegisterEvent(self, 'PLAYER_TARGET_DIED', 'OnTargetDied')
	end
	self:RegisterMessage('LIBSFA_SESSION_STARTED', 'OnSessionStarted')
end

function Sources:OnSessionStarted()
	self.lastKill = nil
end

----------------------------------------------------------------------------------------------------
-- Identity
----------------------------------------------------------------------------------------------------

---@param guid string|nil
---@return string|nil key
---@return string|nil kind
function Sources:KeyForGUID(guid)
	local kind, id = Compat.ParseGUID(guid)
	if not kind then
		return nil
	end
	if (kind == 'Creature' or kind == 'Vehicle') and id then
		return 'c:' .. id, 'creature'
	elseif kind == 'GameObject' and id then
		return 'o:' .. id, 'object'
	elseif kind == 'Item' then
		return 'i', 'container'
	end
	return nil
end

local function Remember(guid, name)
	if not guid or not name or name == '' or names[guid] then
		return
	end
	if nameCount >= CACHE_LIMIT then
		wipe(names)
		nameCount = 0
	end
	names[guid] = name
	nameCount = nameCount + 1
	local key, kind = Sources:KeyForGUID(guid)
	if key and key ~= 'i' then
		Ledger.RememberSource(key, name, kind)
	end
end

---@param unit string
function Sources:RememberUnit(unit)
	if not UnitExists(unit) then
		return
	end
	Remember(Compat.UnitGUID(unit), Compat.UnitName(unit))
end

function Sources:OnUnitSeen(unit)
	self:RememberUnit(unit)
end

function Sources:OnNameplate(_, unit)
	self:RememberUnit(unit)
end

---Best effort name for a GUID: seen units first, then the creature cache on modern clients.
---@param guid string
---@return string|nil
function Sources:NameForGUID(guid)
	if not guid or not Compat.CanAccess(guid) then
		return nil
	end
	if names[guid] then
		return names[guid]
	end
	for _, unit in ipairs(NAME_UNITS) do
		if Compat.UnitGUID(unit) == guid then
			self:RememberUnit(unit)
			return names[guid]
		end
	end
	if C_TooltipInfo and C_TooltipInfo.GetHyperlink then
		local ok, data = pcall(C_TooltipInfo.GetHyperlink, 'unit:' .. guid)
		local line = ok and data and data.lines and data.lines[1]
		local text = line and Compat.Readable(line.leftText)
		if text and text ~= '' then
			Remember(guid, text)
			return text
		end
	end
	local key = self:KeyForGUID(guid)
	local meta = key and LibsFarmAssistant.global.sourceMeta[key]
	return meta and meta.n
end

---Makes sure the source has a stored name before the ledger shows it.
---@param key string
---@param guid string|nil
function Sources:Name(key, guid)
	local meta = LibsFarmAssistant.global.sourceMeta[key]
	if meta and meta.n then
		return meta.n
	end
	local name = guid and self:NameForGUID(guid)
	if name then
		Ledger.RememberSource(key, name)
	end
	return name or Ledger.SourceName(key)
end

----------------------------------------------------------------------------------------------------
-- Kills
----------------------------------------------------------------------------------------------------

---@return boolean
local function Tracking()
	return LibsFarmAssistant:IsSessionActive() and LibsFarmAssistant.db.tracking.kills
end

---Counts a death once per GUID. Returns the source key when this call counted it.
---@param guid string|nil
---@return string|nil key
function Sources:CountKill(guid)
	if not guid or not Compat.CanAccess(guid) or counted[guid] then
		return nil
	end
	local key, kind = self:KeyForGUID(guid)
	if kind ~= 'creature' then
		return nil
	end
	if countedCount >= CACHE_LIMIT then
		wipe(counted)
		countedCount = 0
	end
	counted[guid] = true
	countedCount = countedCount + 1

	self:Name(key, guid)
	self.lastKill = { key = key, at = GetTime() }
	if Tracking() then
		Ledger:AddKill(key)
		LibsFarmAssistant:SendMessage('LIBSFA_ATTEMPT', key)
		LibsFarmAssistant:UpdateDisplay()
	end
	return key
end

---@param guid string
---@return boolean
function Sources:WasCounted(guid)
	return guid ~= nil and Compat.CanAccess(guid) and counted[guid] == true
end

function Sources:OnPartyKill(_, attackerGUID, targetGUID)
	if not Compat.CanAccess(targetGUID) then
		return
	end
	self:CountKill(targetGUID)
end

-- Retail fallback for kills whose PARTY_KILL payload was hidden: the player's own target died.
function Sources:OnTargetDied()
	if not UnitExists('target') or not UnitIsDead('target') then
		return
	end
	local tapDenied = UnitIsTapDenied and UnitIsTapDenied('target')
	if not Compat.CanAccess(tapDenied) or tapDenied then
		return
	end
	self:CountKill(Compat.UnitGUID('target'))
end

---@param encounterID number
---@param name string
function Sources:CountEncounter(encounterID, name)
	if not encounterID or not Compat.CanAccess(encounterID) then
		return
	end
	local now = GetTime()
	if recentEncounters[encounterID] and now - recentEncounters[encounterID] < 30 then
		return
	end
	recentEncounters[encounterID] = now
	local key = 'e:' .. encounterID
	Ledger.RememberSource(key, Compat.Readable(name), 'boss')
	self.lastKill = { key = key, at = now }
	if Tracking() then
		for _, bucket in ipairs(Ledger:Targets()) do
			local stats = Ledger.SourceIn(bucket, key)
			stats.kills = stats.kills + 1
		end
		Ledger.version = Ledger.version + 1
		LibsFarmAssistant:SendMessage('LIBSFA_ATTEMPT', key)
		LibsFarmAssistant:UpdateDisplay()
	end
end

function Sources:OnBossKill(_, encounterID, name)
	self:CountEncounter(encounterID, name)
end

function Sources:OnEncounterEnd(_, encounterID, name, _, _, success)
	if success == 1 then
		self:CountEncounter(encounterID, name)
	end
end

---The source that most likely produced loot arriving without a loot window (personal loot,
---items pushed into bags after a boss).
---@return string|nil key
function Sources:RecentKill()
	local last = self.lastKill
	if last and GetTime() - last.at <= RECENT_KILL_WINDOW then
		return last.key
	end
	return nil
end
