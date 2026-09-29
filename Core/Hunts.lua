---@class LibsFarmAssistant
local LibsFarmAssistant = LibStub('AceAddon-3.0'):GetAddon('Libs-FarmAssistant')

-- A hunt counts attempts toward one item: every kill (or node, chest, catch) that could have
-- dropped it. Sources are learned from the drops themselves and can be added by hand; until a
-- hunt knows any source it counts every kill. When the item drops, the count and time are saved
-- to the hunt's history and start again.

---@class FarmHuntDrop
---@field at number epoch
---@field attempts number
---@field time number seconds
---@field source string|nil

---@class FarmHunt
---@field id number itemID
---@field added number epoch
---@field attempts number since the last drop
---@field totalAttempts number
---@field time number seconds since the last drop
---@field totalTime number
---@field found FarmHuntDrop[]
---@field sources table<string, boolean>
---@field mode string 'sources' or 'any'
---@field chance number|nil 0-1, set by the player
---@field paused boolean|nil

---@class LibsFarmAssistant.Hunts : AceModule, AceEvent-3.0
local Hunts = LibsFarmAssistant:NewModule('Hunts')
LibsFarmAssistant.Hunts = Hunts

local Compat = LibsFarmAssistant.Compat
local Ledger = LibsFarmAssistant.Ledger
local Format = LibsFarmAssistant.Format

local lastAttempt = {} -- hunt key -> { at, kind } of its last counted attempt
local lastFound = {} -- hunt key -> GetTime() of its last recorded drop

function Hunts:OnEnable()
	self:RegisterMessage('LIBSFA_ATTEMPT', 'OnAttempt')
	self:RegisterMessage('LIBSFA_ITEM_GAINED', 'OnItemGained')
	self:RegisterMessage('LIBSFA_TIME_ADDED', 'OnTimeAdded')
end

---@return table<string, FarmHunt>
local function All()
	return LibsFarmAssistant.char.hunts
end

---@param itemID number|string
---@return FarmHunt|nil
function Hunts:Get(itemID)
	return All()[tostring(itemID)]
end

---Active hunts first (most attempts first), finished collectibles last.
---@return FarmHunt[]
function Hunts:List()
	local list = {}
	for _, hunt in pairs(All()) do
		list[#list + 1] = hunt
	end
	table.sort(list, function(a, b)
		local aDone, bDone = self:IsCollected(a), self:IsCollected(b)
		if aDone ~= bDone then
			return not aDone
		end
		if (a.paused and 1 or 0) ~= (b.paused and 1 or 0) then
			return not a.paused
		end
		return (a.attempts or 0) > (b.attempts or 0)
	end)
	return list
end

---@return number
function Hunts:Count()
	local n = 0
	for _ in pairs(All()) do
		n = n + 1
	end
	return n
end

---@param itemID number
---@return FarmHunt|nil hunt
---@return boolean added False when the hunt already existed
function Hunts:Add(itemID)
	if not itemID then
		return nil, false
	end
	local key = tostring(itemID)
	local hunts = All()
	if hunts[key] then
		return hunts[key], false
	end
	---@type FarmHunt
	local hunt = {
		id = itemID,
		added = time(),
		attempts = 0,
		totalAttempts = 0,
		time = 0,
		totalTime = 0,
		found = {},
		sources = {},
		mode = 'sources',
	}
	-- Anything that already dropped it counts from the start.
	for _, src in ipairs(Ledger.ItemSources(Ledger:Lifetime(), itemID)) do
		if src.key ~= 'q' then
			hunt.sources[src.key] = true
		end
	end
	hunts[key] = hunt
	LibsFarmAssistant.Pricing:Remember(itemID)
	LibsFarmAssistant:SendMessage('LIBSFA_HUNTS_CHANGED')
	LibsFarmAssistant:UpdateDisplay()
	return hunt, true
end

---@param itemID number
function Hunts:Remove(itemID)
	All()[tostring(itemID)] = nil
	LibsFarmAssistant:SendMessage('LIBSFA_HUNTS_CHANGED')
	LibsFarmAssistant:UpdateDisplay()
end

---@param hunt FarmHunt
---@return boolean
function Hunts:HasSources(hunt)
	return next(hunt.sources) ~= nil
end

---@param hunt FarmHunt
---@param key string
---@return boolean
function Hunts:Counts(hunt, key)
	if hunt.paused or self:IsCollected(hunt) then
		return false
	end
	if hunt.mode == 'any' or not self:HasSources(hunt) then
		-- Kills, nodes and catches are chances at a drop. Rewards, containers, gathering and
		-- pickpocketing are not, and a boss already counts through its creature kill.
		local prefix = key:sub(1, 1)
		return prefix == 'c' or prefix == 'o' or prefix == 'f'
	end
	return hunt.sources[key] == true
end

function Hunts:OnAttempt(_, key)
	if not LibsFarmAssistant:IsSessionActive() then
		return
	end
	local changed = false
	local now = GetTime()
	local kind = key:sub(1, 1)
	for id, hunt in pairs(All()) do
		if self:Counts(hunt, key) then
			-- A boss death arrives twice (the creature and the encounter): count it once.
			local last = lastAttempt[id]
			local duplicate = last and now - last.at < 15 and last.kind ~= kind and (kind == 'e' or last.kind == 'e')
			if not duplicate then
				hunt.attempts = (hunt.attempts or 0) + 1
				hunt.totalAttempts = (hunt.totalAttempts or 0) + 1
				lastAttempt[id] = { at = now, kind = kind }
				changed = true
			end
		end
	end
	if changed then
		LibsFarmAssistant:SendMessage('LIBSFA_HUNTS_UPDATED')
	end
end

function Hunts:OnTimeAdded(_, seconds)
	for _, hunt in pairs(All()) do
		if not hunt.paused and not self:IsCollected(hunt) then
			hunt.time = (hunt.time or 0) + seconds
			hunt.totalTime = (hunt.totalTime or 0) + seconds
		end
	end
end

function Hunts:OnItemGained(_, itemID, quantity, sourceKey, link, fromLoot)
	local hunt = self:Get(itemID)
	-- Only real drops end a count; rewards, purchases and crafts do not.
	if not hunt or not fromLoot then
		return
	end
	-- One loot shared by several corpses arrives once per corpse: that is still one drop.
	local key = tostring(itemID)
	if lastFound[key] and GetTime() - lastFound[key] < 3 then
		return
	end
	lastFound[key] = GetTime()
	---@type FarmHuntDrop
	local drop = { at = time(), attempts = hunt.attempts or 0, time = hunt.time or 0, source = sourceKey }
	table.insert(hunt.found, drop)
	if sourceKey and sourceKey ~= 'q' and sourceKey ~= 'i' then
		hunt.sources[sourceKey] = true
	end
	hunt.attempts = 0
	hunt.time = 0

	self:Celebrate(hunt, drop, link)
	LibsFarmAssistant:SendMessage('LIBSFA_HUNTS_UPDATED')
	LibsFarmAssistant:UpdateDisplay()
end

---@param hunt FarmHunt
---@param drop FarmHuntDrop
---@param link string|nil
function Hunts:Celebrate(hunt, drop, link)
	local settings = LibsFarmAssistant.db.hunts
	local name = link or self:Name(hunt)
	local line = string.format('%s after %s %s (%s).', name, Format.Number(drop.attempts), drop.attempts == 1 and 'attempt' or 'attempts', Format.Duration(drop.time))
	if settings.announce then
		LibsFarmAssistant:Print('Found ' .. line)
		if RaidNotice_AddMessage and RaidWarningFrame and ChatTypeInfo then
			RaidNotice_AddMessage(RaidWarningFrame, 'Found ' .. line, ChatTypeInfo['RAID_WARNING'])
		end
	end
	if settings.sound then
		PlaySound(SOUNDKIT and SOUNDKIT.UI_GARRISON_MISSION_COMPLETE_ENCOUNTER_CHANCE or 8959)
	end
end

---@param hunt FarmHunt
---@return string
function Hunts:Name(hunt)
	local meta = LibsFarmAssistant.Pricing:Meta(hunt.id)
	return meta.n or ('Item ' .. hunt.id)
end

---@param hunt FarmHunt
---@return string|nil kind 'mount', 'pet' or 'toy'
---@return boolean collected
function Hunts:Collectible(hunt)
	return Compat.Collectible(hunt.id)
end

---A collectible hunt finishes once the account owns it.
---@param hunt FarmHunt
---@return boolean
function Hunts:IsCollected(hunt)
	local kind, collected = Compat.Collectible(hunt.id)
	return kind ~= nil and collected
end

---@param itemID number
---@param key string
function Hunts:AddSource(itemID, key)
	local hunt = self:Get(itemID)
	if hunt and key then
		hunt.sources[key] = true
		LibsFarmAssistant:SendMessage('LIBSFA_HUNTS_UPDATED')
	end
end

---@param itemID number
---@param key string
function Hunts:RemoveSource(itemID, key)
	local hunt = self:Get(itemID)
	if hunt then
		hunt.sources[key] = nil
		LibsFarmAssistant:SendMessage('LIBSFA_HUNTS_UPDATED')
	end
end

---Adds the player's current target (a creature) as a source.
---@param itemID number
---@return string|nil key
function Hunts:AddTargetAsSource(itemID)
	local guid = Compat.UnitGUID('target')
	local key = guid and LibsFarmAssistant.Sources:KeyForGUID(guid)
	if not key or key:sub(1, 2) ~= 'c:' then
		return nil
	end
	LibsFarmAssistant.Sources:RememberUnit('target')
	self:AddSource(itemID, key)
	return key
end

---@param itemID number
---@param percent number|nil 0-100, nil clears it
function Hunts:SetChance(itemID, percent)
	local hunt = self:Get(itemID)
	if not hunt then
		return
	end
	if percent and percent > 0 and percent <= 100 then
		hunt.chance = percent / 100
	else
		hunt.chance = nil
	end
	LibsFarmAssistant:SendMessage('LIBSFA_HUNTS_UPDATED')
end

---@param itemID number
function Hunts:ResetCount(itemID)
	local hunt = self:Get(itemID)
	if hunt then
		hunt.attempts = 0
		hunt.time = 0
		LibsFarmAssistant:SendMessage('LIBSFA_HUNTS_UPDATED')
	end
end

---@param itemID number
function Hunts:TogglePaused(itemID)
	local hunt = self:Get(itemID)
	if hunt then
		hunt.paused = not hunt.paused or nil
		LibsFarmAssistant:SendMessage('LIBSFA_HUNTS_UPDATED')
	end
end

---Chance that a player with this many attempts would have the item by now.
---@param chance number 0-1
---@param attempts number
---@return number 0-1
function Hunts.ChanceByNow(chance, attempts)
	if not chance or chance <= 0 then
		return 0
	end
	if chance >= 1 then
		return attempts > 0 and 1 or 0
	end
	return 1 - (1 - chance) ^ attempts
end

---Plain words for how lucky the current count is.
---@param hunt FarmHunt
---@return string|nil sentence
---@return number|nil byNow 0-1
function Hunts:LuckText(hunt)
	if not hunt.chance then
		return nil
	end
	local attempts = hunt.attempts or 0
	local byNow = Hunts.ChanceByNow(hunt.chance, attempts)
	local expected = 1 / hunt.chance
	if attempts == 0 then
		return string.format('At %s you can expect it in about %s attempts.', Format.Percent(hunt.chance), Format.Number(expected)), 0
	end
	if byNow < 0.5 then
		return string.format('%s of players would have it by now. Keep going, you are on pace.', Format.Percent(byNow)), byNow
	end
	local oneIn = 1 / math.max(1 - byNow, 0.0001)
	return string.format('%s of players would have it by now. About 1 in %s people wait this long.', Format.Percent(byNow), Format.Number(oneIn)), byNow
end

---Sources for the hunt's item seen in all-time data, best rate first.
---@param hunt FarmHunt
---@return FarmItemSource[]
function Hunts:ObservedSources(hunt)
	return Ledger.ItemSources(Ledger:Lifetime(), hunt.id)
end
