---@class LibsFarmAssistant
local LibsFarmAssistant = LibStub('AceAddon-3.0'):GetAddon('Libs-FarmAssistant')

-- One place for every API that differs between Retail and the Classic clients, and for the
-- Retail 12.x secret-value rules. Trackers and UI call these instead of the game directly, so
-- they never have to ask which game they are running in.

---@class LibsFarmAssistant.Compat
local Compat = {}
LibsFarmAssistant.Compat = Compat

local C_Item = C_Item
local C_CurrencyInfo = C_CurrencyInfo
local C_Reputation = C_Reputation
local C_MajorFactions = C_MajorFactions
local C_GossipInfo = C_GossipInfo
local C_MountJournal = C_MountJournal
local C_PetJournal = C_PetJournal
local C_ToyBox = C_ToyBox
local C_DateAndTime = C_DateAndTime
local C_Map = C_Map
local canaccessvalue = canaccessvalue
local issecretvalue = issecretvalue

local INTERFACE = select(4, GetBuildInfo()) or 0

-- WoW Forever reports a low WOW_PROJECT_ID but runs the modern interface, so rules follow the
-- interface number: 110000 and up plays by Retail rules.
Compat.IsRetail = INTERFACE >= 110000
Compat.Interface = INTERFACE

----------------------------------------------------------------------------------------------------
-- Secret values
----------------------------------------------------------------------------------------------------

---True when addon code may compare, index with, or do math on the value (always true before 12.0).
---@param value any
---@return boolean
function Compat.CanAccess(value)
	if value == nil then
		return true
	end
	if canaccessvalue then
		return canaccessvalue(value) and true or false
	end
	if issecretvalue then
		return not issecretvalue(value)
	end
	return true
end

---Returns the value only if it is readable, otherwise nil.
---@generic T
---@param value T
---@return T|nil
function Compat.Readable(value)
	if value ~= nil and Compat.CanAccess(value) then
		return value
	end
	return nil
end

----------------------------------------------------------------------------------------------------
-- GUIDs and units
----------------------------------------------------------------------------------------------------

---Splits a GUID into its kind and numeric ID ('Creature', 12345).
---@param guid string|nil
---@return string|nil kind
---@return number|nil id
function Compat.ParseGUID(guid)
	if type(guid) ~= 'string' or not Compat.CanAccess(guid) then
		return nil
	end
	local kind, _, _, _, _, id = strsplit('-', guid)
	return kind, tonumber(id)
end

---@param unit string
---@return string|nil guid
function Compat.UnitGUID(unit)
	return Compat.Readable(UnitGUID(unit))
end

---@param unit string
---@return string|nil name
function Compat.UnitName(unit)
	local name = UnitName(unit)
	return Compat.Readable(name)
end

---@return string zone
---@return number|nil mapID
function Compat.CurrentZone()
	local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit('player')
	local zone = GetRealZoneText and GetRealZoneText() or GetZoneText()
	return zone or '', mapID
end

----------------------------------------------------------------------------------------------------
-- Items
----------------------------------------------------------------------------------------------------

---@param item number|string ID or link
---@return string|nil name, string|nil link, number|nil quality, number|nil sellPrice, number|nil bindType, number|string|nil icon
function Compat.ItemInfo(item)
	local name, link, quality, icon, sellPrice, bindType, _
	if C_Item and C_Item.GetItemInfo then
		name, link, quality, _, _, _, _, _, _, icon, sellPrice, _, _, bindType = C_Item.GetItemInfo(item)
	elseif GetItemInfo then
		name, link, quality, _, _, _, _, _, _, icon, sellPrice, _, _, bindType = GetItemInfo(item)
	end
	return name, link, quality, sellPrice, bindType, icon
end

---Icon works for any item ID without waiting for item data.
---@param itemID number
---@return number|string|nil icon
function Compat.ItemIcon(itemID)
	if C_Item and C_Item.GetItemIconByID then
		return C_Item.GetItemIconByID(itemID)
	end
	if GetItemIcon then
		return GetItemIcon(itemID)
	end
	local _, _, _, _, icon = (C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant)(itemID)
	return icon
end

---@param itemID number
function Compat.RequestItem(itemID)
	if C_Item and C_Item.RequestLoadItemDataByID then
		C_Item.RequestLoadItemDataByID(itemID)
	end
end

---@param link string|nil
---@return number|nil itemID
function Compat.ItemIDFromLink(link)
	if type(link) ~= 'string' or not Compat.CanAccess(link) then
		return nil
	end
	return tonumber(link:match('item:(%d+)'))
end

---@param quality number|nil
---@return number r, number g, number b, string hex
function Compat.QualityColor(quality)
	quality = quality or 1
	if C_Item and C_Item.GetItemQualityColor then
		local r, g, b, hex = C_Item.GetItemQualityColor(quality)
		if r then
			return r, g, b, hex
		end
	end
	if GetItemQualityColor then
		local r, g, b, hex = GetItemQualityColor(quality)
		if r then
			return r, g, b, hex
		end
	end
	return 1, 1, 1, 'ffffffff'
end

----------------------------------------------------------------------------------------------------
-- Collectibles (mounts, pets, toys)
----------------------------------------------------------------------------------------------------

---What kind of collectible the item teaches, and whether this account already has it.
---@param itemID number
---@return string|nil kind 'mount', 'pet' or 'toy'
---@return boolean collected
function Compat.Collectible(itemID)
	if C_MountJournal and C_MountJournal.GetMountFromItem then
		local mountID = C_MountJournal.GetMountFromItem(itemID)
		if mountID then
			local isCollected = select(11, C_MountJournal.GetMountInfoByID(mountID))
			return 'mount', isCollected and true or false
		end
	end
	if C_PetJournal and C_PetJournal.GetPetInfoByItemID then
		local speciesID = select(13, C_PetJournal.GetPetInfoByItemID(itemID))
		if speciesID then
			local owned = C_PetJournal.GetNumCollectedInfo and C_PetJournal.GetNumCollectedInfo(speciesID)
			return 'pet', (owned or 0) > 0
		end
	end
	if C_ToyBox and C_ToyBox.GetToyInfo and C_ToyBox.GetToyInfo(itemID) then
		return 'toy', PlayerHasToy and PlayerHasToy(itemID) and true or false
	end
	return nil, false
end

----------------------------------------------------------------------------------------------------
-- Currency
----------------------------------------------------------------------------------------------------

---@param currencyID number
---@return string|nil name, number|string|nil icon, number|nil quantity, number|nil quality
function Compat.CurrencyInfo(currencyID)
	if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
		local info = C_CurrencyInfo.GetCurrencyInfo(currencyID)
		if info then
			return info.name, info.iconFileID, info.quantity, info.quality
		end
	end
	if GetCurrencyInfo then
		local name, amount, icon, _, _, _, _, quality = GetCurrencyInfo(currencyID)
		return name, icon, amount, quality
	end
	return nil
end

----------------------------------------------------------------------------------------------------
-- Reputation
----------------------------------------------------------------------------------------------------

---@class FarmFactionProgress
---@field factionID number
---@field name string
---@field kind string 'standard'|'friendship'|'renown'|'paragon'
---@field label string Standing text
---@field level number Standing index, friendship rank or renown level
---@field min number
---@field max number
---@field value number Progress inside the current step
---@field total number Monotonic total used to measure gains
---@field capped boolean
---@field rewardPending boolean
---@field quality number 0-5 color ladder
---@field icon string|number|nil
---@field atlas string|nil

local function StandingLabel(reaction)
	local label = GetText and GetText('FACTION_STANDING_LABEL' .. reaction, UnitSex('player'))
	return label or _G['FACTION_STANDING_LABEL' .. reaction] or tostring(reaction)
end

-- Standing to color ladder: the same ladder as item quality, so the player reads it without a key.
local REACTION_QUALITY = { [4] = 1, [5] = 2, [6] = 3, [7] = 4, [8] = 5 }

---@param factionID number
---@return table|nil data { name, reaction, bottom, top, value, isHeader, hasRep }
local function StandardData(factionID)
	if C_Reputation and C_Reputation.GetFactionDataByID then
		local data = C_Reputation.GetFactionDataByID(factionID)
		if not data or not data.name or data.name == '' then
			return nil
		end
		return {
			name = data.name,
			reaction = data.reaction,
			bottom = data.currentReactionThreshold,
			top = data.nextReactionThreshold,
			value = data.currentStanding,
			isHeader = data.isHeader and not data.isHeaderWithRep,
		}
	end
	if GetFactionInfoByID then
		local name, _, standingID, barMin, barMax, barValue, _, _, isHeader, _, hasRep = GetFactionInfoByID(factionID)
		if not name or name == '' then
			return nil
		end
		return { name = name, reaction = standingID, bottom = barMin, top = barMax, value = barValue, isHeader = isHeader and not hasRep }
	end
	return nil
end

---Reads any faction as one progress shape, whatever kind it is.
---@param factionID number
---@return FarmFactionProgress|nil
function Compat.FactionProgress(factionID)
	local data = StandardData(factionID)
	if not data then
		return nil
	end

	---@type FarmFactionProgress
	local p = {
		factionID = factionID,
		name = data.name,
		kind = 'standard',
		label = StandingLabel(data.reaction or 4),
		level = data.reaction or 4,
		min = 0,
		max = math.max(1, (data.top or 1) - (data.bottom or 0)),
		value = (data.value or 0) - (data.bottom or 0),
		total = data.value or 0,
		capped = false,
		rewardPending = false,
		quality = REACTION_QUALITY[data.reaction or 4] or 0,
	}
	if (data.reaction or 0) >= 8 and (data.top or 0) <= (data.value or 0) then
		p.capped = true
		p.value = p.max
	end

	local isMajor = C_Reputation and C_Reputation.IsMajorFaction and C_Reputation.IsMajorFaction(factionID)
	if isMajor and C_MajorFactions and C_MajorFactions.GetMajorFactionData then
		local major = C_MajorFactions.GetMajorFactionData(factionID)
		if major then
			local threshold = major.renownLevelThreshold or 1
			p.kind = 'renown'
			p.level = major.renownLevel or 0
			p.label = (RENOWN_LEVEL_LABEL and RENOWN_LEVEL_LABEL:format(p.level)) or ('Renown ' .. p.level)
			p.max = math.max(1, threshold)
			p.value = major.renownReputationEarned or 0
			p.total = p.level * p.max + p.value
			p.capped = C_MajorFactions.HasMaximumRenown and C_MajorFactions.HasMaximumRenown(factionID) or false
			if p.capped then
				p.value = p.max
			end
			p.quality = math.max(1, math.min(5, math.ceil(p.level / math.max(1, major.maxLevel or 1) * 5)))
			if major.textureKit then
				p.atlas = ('majorFactions_icons_%s512'):format(major.textureKit)
			end
		end
	elseif C_GossipInfo and C_GossipInfo.GetFriendshipReputation then
		local friend = C_GossipInfo.GetFriendshipReputation(factionID)
		if friend and friend.friendshipFactionID and friend.friendshipFactionID > 0 then
			p.kind = 'friendship'
			p.label = friend.reaction or p.label
			p.total = friend.standing or 0
			if friend.nextThreshold then
				p.max = math.max(1, friend.nextThreshold - (friend.reactionThreshold or 0))
				p.value = (friend.standing or 0) - (friend.reactionThreshold or 0)
			else
				p.max, p.value, p.capped = 1, 1, true
			end
			local ranks = C_GossipInfo.GetFriendshipReputationRanks and C_GossipInfo.GetFriendshipReputationRanks(factionID)
			if ranks and ranks.maxLevel and ranks.maxLevel > 0 then
				p.level = ranks.currentLevel or 1
				p.quality = p.capped and 5 or math.max(1, math.min(5, math.floor((p.level / ranks.maxLevel) * 4) + 1))
			end
			p.icon = friend.texture
		end
	end

	local isParagon = C_Reputation and C_Reputation.IsFactionParagon and C_Reputation.IsFactionParagon(factionID)
	if isParagon and C_Reputation.GetFactionParagonInfo then
		local current, threshold, _, pending = C_Reputation.GetFactionParagonInfo(factionID)
		if current and threshold and threshold > 0 then
			p.kind = 'paragon'
			p.rewardPending = pending and true or false
			p.max = threshold
			p.value = pending and threshold or (current % threshold)
			p.total = p.total + current
			p.capped = false
			p.quality = 5
		end
	end

	return p
end

---Calls fn(factionID) for every faction the reputation list currently shows.
---@param fn fun(factionID: number)
function Compat.ForEachListedFaction(fn)
	if C_Reputation and C_Reputation.GetNumFactions and C_Reputation.GetFactionDataByIndex then
		for i = 1, C_Reputation.GetNumFactions() do
			local data = C_Reputation.GetFactionDataByIndex(i)
			if data and data.factionID and data.factionID > 0 and (not data.isHeader or data.isHeaderWithRep) then
				fn(data.factionID)
			end
		end
		return
	end
	if GetNumFactions and GetFactionInfo then
		for i = 1, GetNumFactions() do
			local _, _, _, _, _, _, _, _, isHeader, _, hasRep, _, _, factionID = GetFactionInfo(i)
			if factionID and (not isHeader or hasRep) then
				fn(factionID)
			end
		end
	end
end

---@param factionID number
---@return string|nil name
function Compat.FactionName(factionID)
	local data = StandardData(factionID)
	return data and data.name
end

---Faction IDs known to exist are well below this on every client.
Compat.MAX_FACTION_ID = 3200

----------------------------------------------------------------------------------------------------
-- Experience
----------------------------------------------------------------------------------------------------

---@return boolean
function Compat.CanGainXP()
	if IsXPUserDisabled and IsXPUserDisabled() then
		return false
	end
	if IsPlayerAtEffectiveMaxLevel then
		return not IsPlayerAtEffectiveMaxLevel()
	end
	local maxLevel = (GetMaxLevelForPlayerExpansion and GetMaxLevelForPlayerExpansion()) or (GetMaxPlayerLevel and GetMaxPlayerLevel()) or MAX_PLAYER_LEVEL or 60
	return UnitLevel('player') < maxLevel
end

----------------------------------------------------------------------------------------------------
-- Calendar
----------------------------------------------------------------------------------------------------

---Epoch of the most recent weekly reset, or nil when the client has no reset timer.
---@return number|nil
function Compat.LastWeeklyReset()
	if C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset then
		local seconds = C_DateAndTime.GetSecondsUntilWeeklyReset()
		if seconds and seconds > 0 then
			return time() + seconds - 7 * 86400
		end
	end
	return nil
end

----------------------------------------------------------------------------------------------------
-- Localized chat patterns
----------------------------------------------------------------------------------------------------

---Turns a GlobalStrings format ("Reputation with %s increased by %d.") into a Lua pattern with
---captures, so chat can be read in every client language.
---@param format string|nil
---@return string|nil
function Compat.FormatToPattern(format)
	if type(format) ~= 'string' or format == '' then
		return nil
	end
	local pattern = format:gsub('[%%%(%)%.%+%-%*%?%[%]%^%$]', '%%%0')
	pattern = pattern:gsub('%%%%%d%%%$', '%%%%') -- positional args ("%1$s") read like plain ones
	pattern = pattern:gsub('%%%%s', '(.+)')
	pattern = pattern:gsub('%%%%d', '([%%d,%%.]+)')
	pattern = pattern:gsub('%%%%%%%.%d+f', '([%%d,%%.]+)')
	return '^' .. pattern
end

---@param text string
---@return number|nil
function Compat.ParseNumber(text)
	if not text then
		return nil
	end
	local digits = tostring(text):gsub('[^%d]', '')
	return tonumber(digits)
end

----------------------------------------------------------------------------------------------------
-- Events
----------------------------------------------------------------------------------------------------

---Registers an AceEvent handler only when this client knows the event, since registering an
---unknown event is an error on modern clients.
---@param module table AceEvent-embedded object
---@param event string
---@param handler string|function
---@param arg any
---@return boolean registered
function Compat.RegisterEvent(module, event, handler, arg)
	if C_EventUtils and C_EventUtils.IsEventValid and not C_EventUtils.IsEventValid(event) then
		return false
	end
	if arg ~= nil then
		module:RegisterEvent(event, handler, arg)
	else
		module:RegisterEvent(event, handler)
	end
	return true
end
