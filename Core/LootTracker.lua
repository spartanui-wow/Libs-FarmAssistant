---@class LibsFarmAssistant
local LibsFarmAssistant = LibStub('AceAddon-3.0'):GetAddon('Libs-FarmAssistant')

-- Two paths bring items in:
--   1. The loot window. When it opens, every slot is read together with the corpse, node or catch
--      it came from (GetLootSourceInfo). A slot is recorded only when it actually leaves the
--      window (LOOT_SLOT_CLEARED), so items left on a corpse never count.
--   2. Chat. Personal loot, bonus rolls, quest rewards and items pushed into bags arrive as
--      "You receive ..." lines. Those already recorded from the window are skipped; the rest
--      are credited to the last thing the player killed.

---@class LibsFarmAssistant.LootTracker : AceModule, AceEvent-3.0, AceTimer-3.0
local LootTracker = LibsFarmAssistant:NewModule('LootTracker')
LibsFarmAssistant.LootTracker = LootTracker

local Compat = LibsFarmAssistant.Compat
local Ledger = LibsFarmAssistant.Ledger

local SLOT_ITEM = (Enum and Enum.LootSlotType and Enum.LootSlotType.Item) or LOOT_SLOT_ITEM or 1
local SLOT_MONEY = (Enum and Enum.LootSlotType and Enum.LootSlotType.Money) or LOOT_SLOT_MONEY or 2

local EXPECT_WINDOW = 5
local PICK_POCKET = 921
local CAST_NAME_WINDOW = 10
local LOOTED_LIMIT = 4000

local looted = {} -- guid -> true once its loot was counted
local lootedCount = 0
local expected = {} -- itemID -> { count, at } items the window recorded, still to arrive in chat

-- Chat line formats, most specific first so "x5" is never read as part of the name.
local CHAT_FORMATS = {
	{ 'LOOT_ITEM_SELF_MULTIPLE', 'loot' },
	{ 'LOOT_ITEM_BONUS_ROLL_SELF_MULTIPLE', 'loot' },
	{ 'LOOT_ITEM_PUSHED_SELF_MULTIPLE', 'reward' },
	{ 'LOOT_ITEM_CREATED_SELF_MULTIPLE', 'created' },
	{ 'LOOT_ITEM_REFUND_MULTIPLE', 'refund' },
	{ 'LOOT_ITEM_SELF', 'loot' },
	{ 'LOOT_ITEM_BONUS_ROLL_SELF', 'loot' },
	{ 'LOOT_ITEM_PUSHED_SELF', 'reward' },
	{ 'LOOT_ITEM_CREATED_SELF', 'created' },
	{ 'LOOT_ITEM_REFUND', 'refund' },
}
local chatPatterns

local function BuildPatterns()
	chatPatterns = {}
	for _, entry in ipairs(CHAT_FORMATS) do
		local pattern = Compat.FormatToPattern(_G[entry[1]])
		if pattern then
			chatPatterns[#chatPatterns + 1] = { pattern = pattern, kind = entry[2] }
		end
	end
end

function LootTracker:OnEnable()
	BuildPatterns()
	self.window = nil
	self.lastCast = nil -- { name, at } object name from the last cast on a node or chest

	self:RegisterEvent('LOOT_READY', 'Snapshot')
	self:RegisterEvent('LOOT_OPENED', 'Snapshot')
	self:RegisterEvent('LOOT_SLOT_CLEARED', 'OnSlotCleared')
	self:RegisterEvent('LOOT_CLOSED', 'OnLootClosed')
	self:RegisterEvent('CHAT_MSG_LOOT', 'OnChatLoot')
	self:RegisterEvent('UNIT_SPELLCAST_SENT', 'OnSpellcastSent')
	self:RegisterEvent('PLAYER_REGEN_ENABLED', 'RetryHidden')
	Compat.RegisterEvent(self, 'ADDON_RESTRICTION_STATE_CHANGED', 'RetryHidden')
	self.hidden = {} -- lineID -> { key, at } loot lines that were hidden during combat lockdown
end

---@return boolean
function LootTracker:IsWindowOpen()
	return self.window ~= nil and not self.window.closed
end

---@return boolean True while the loot window is open or closed less than a second ago
function LootTracker:RecentlyLooting()
	local w = self.window
	if not w then
		return false
	end
	return not w.closed or (GetTime() - (w.closedAt or 0)) < 1.5
end

function LootTracker:OnSpellcastSent(_, unit, target, _, spellID)
	if unit ~= 'player' then
		return
	end
	target = Compat.Readable(target)
	self.lastCast = { name = target ~= '' and target or nil, spellID = Compat.Readable(spellID), at = GetTime() }
end

----------------------------------------------------------------------------------------------------
-- Filters
----------------------------------------------------------------------------------------------------

---Whether an item belongs in the totals under the player's tracking mode.
---@param itemID number
---@param quality number|nil
---@return boolean
function LootTracker:ShouldTrack(itemID, quality)
	local key = tostring(itemID)
	if LibsFarmAssistant.char.hunts[key] or LibsFarmAssistant.char.watchedItems[key] then
		return true
	end
	local tracking = LibsFarmAssistant.db.tracking
	if tracking.mode == 'selected' then
		return false
	end
	if quality == nil then
		return true
	end
	return tracking.qualities[quality] ~= false
end

---Writes an item gain to the ledger and tells hunts and goals.
---@param itemID number
---@param quantity number
---@param link string|nil
---@param sourceKey string|nil
---@param isDrop boolean|nil
---@param quality number|nil
---@param fromLoot boolean|nil True for real loot (window or loot chat), false for rewards and crafts
function LootTracker:Record(itemID, quantity, link, sourceKey, isDrop, quality, fromLoot)
	if not itemID or not quantity or quantity <= 0 then
		return
	end
	if not LibsFarmAssistant:IsSessionActive() or not LibsFarmAssistant.db.tracking.loot then
		return
	end
	local meta = LibsFarmAssistant.Pricing:Remember(itemID, link)
	if quality == nil and meta then
		quality = meta.q
	end

	LibsFarmAssistant:SendMessage('LIBSFA_ITEM_GAINED', itemID, quantity, sourceKey, link, fromLoot and true or false)

	if not self:ShouldTrack(itemID, quality) then
		return
	end
	Ledger:AddItem(itemID, quantity, sourceKey, isDrop)
	LibsFarmAssistant:Log(string.format('Item %d x%d from %s', itemID, quantity, sourceKey or '?'), 'debug')

	if LibsFarmAssistant.db.chatEcho then
		LibsFarmAssistant:Print(string.format('%s x%d', link or ('item:' .. itemID), quantity))
	end
	LibsFarmAssistant:UpdateDisplay()
end

----------------------------------------------------------------------------------------------------
-- Loot window
----------------------------------------------------------------------------------------------------

---A GUID for clients without GetLootSourceInfo: the dead unit the player just opened.
---@return string|nil
local function FallbackGUID()
	for _, unit in ipairs({ 'mouseover', 'target' }) do
		if UnitExists(unit) and UnitIsDead(unit) then
			local guid = Compat.UnitGUID(unit)
			if guid then
				return guid
			end
		end
	end
	return nil
end

---@param slot number
---@return table[] list of { guid, quantity }
local function SlotSources(slot)
	local list = {}
	if GetLootSourceInfo then
		local info = { GetLootSourceInfo(slot) }
		for i = 1, #info, 2 do
			local guid, quantity = info[i], info[i + 1]
			if guid and Compat.CanAccess(guid) then
				list[#list + 1] = { guid = guid, quantity = Compat.Readable(quantity) or 1 }
			end
		end
	end
	if #list == 0 then
		local guid = FallbackGUID()
		if guid then
			list[1] = { guid = guid }
		end
	end
	return list
end

---@param guid string
---@param fishingKey string|nil
---@return string|nil key
function LootTracker:KeyFor(guid, fishingKey)
	if fishingKey then
		return fishingKey
	end
	local Sources = LibsFarmAssistant.Sources
	local key, kind = Sources:KeyForGUID(guid)
	if kind == 'object' and not LibsFarmAssistant.global.sourceMeta[key] then
		local cast = self.lastCast
		if cast and cast.name and GetTime() - cast.at < CAST_NAME_WINDOW then
			Ledger.RememberSource(key, cast.name, 'object')
		end
	elseif key and key ~= 'i' then
		Sources:Name(key, guid)
	elseif key == 'i' then
		Ledger.RememberSource('i', 'Containers', 'container')
	end
	return key
end

---Counts the corpse, node or catch as looted once, and the creature as killed if no kill event
---already did.
---@param guid string
---@param key string
function LootTracker:CountOpen(guid, key)
	if looted[guid] then
		return
	end
	if lootedCount >= LOOTED_LIMIT then
		wipe(looted)
		lootedCount = 0
	end
	looted[guid] = true
	lootedCount = lootedCount + 1

	if key:sub(1, 2) == 'c:' and not LibsFarmAssistant.Sources:WasCounted(guid) then
		LibsFarmAssistant.SessionManager:StartOnKill()
	end
	if not LibsFarmAssistant:IsSessionActive() then
		return
	end
	if key:sub(1, 2) == 'c:' then
		LibsFarmAssistant.Sources:CountKill(guid)
	elseif key:sub(1, 1) == 'o' or key:sub(1, 1) == 'f' then
		LibsFarmAssistant:SendMessage('LIBSFA_ATTEMPT', key)
	end
	Ledger:AddLoot(key)
end

---Picks the source key for one GUID in this window and counts the open once. A creature that
---was already looted is being skinned, mined or gathered; one still alive is being pickpocketed.
---Those get their own sources so they never inflate the creature's drop table or kill count.
---@param guid string
---@param fishingKey string|nil
---@param pickpocket boolean|nil
---@return string|nil key
function LootTracker:DecideKey(guid, fishingKey, pickpocket)
	local key = self:KeyFor(guid, fishingKey)
	if not key then
		return nil
	end
	if key:sub(1, 2) == 'c:' then
		local npcID = key:sub(3)
		local base = LibsFarmAssistant.Sources:Name(key, guid)
		if pickpocket then
			key = 'p:' .. npcID
			Ledger.RememberSource(key, base .. ' (pickpocketed)', 'pickpocket')
			if LibsFarmAssistant:IsSessionActive() then
				Ledger:AddLoot(key)
			end
			return key
		elseif looted[guid] then
			key = 'g:' .. npcID
			Ledger.RememberSource(key, base .. ' (gathered)', 'gathering')
			self:CountOpen('g-' .. guid, key)
			return key
		end
	end
	self:CountOpen(fishingKey and ('fish-' .. guid) or guid, key)
	return key
end

---Reads the open loot window. Safe to call more than once per window.
function LootTracker:Snapshot()
	if self.window and not self.window.closed then
		return
	end
	local count = GetNumLootItems and GetNumLootItems() or 0

	local fishingKey
	if IsFishingLoot and IsFishingLoot() then
		local zone = Compat.CurrentZone()
		fishingKey = 'f:' .. (zone ~= '' and zone or 'unknown')
		Ledger.RememberSource(fishingKey, zone ~= '' and ('Fishing: ' .. zone) or 'Fishing', 'fishing')
	end

	local window = { slots = {}, fishing = fishingKey ~= nil }
	self.window = window

	local cast = self.lastCast
	local pickpocket = cast and cast.spellID == PICK_POCKET and GetTime() - cast.at < 5
	local decided = {} -- guid -> source key for this window (false when unknown)

	for slot = 1, count do
		local slotType = GetLootSlotType(slot)
		local _, _, quantity, currencyID, quality, locked = GetLootSlotInfo(slot)
		local link = slotType == SLOT_ITEM and GetLootSlotLink(slot) or nil
		local entry = {
			type = slotType,
			link = link,
			itemID = Compat.ItemIDFromLink(link),
			quantity = quantity or 1,
			quality = quality,
			currencyID = currencyID,
			locked = locked,
			sources = {},
		}
		for _, src in ipairs(SlotSources(slot)) do
			local key = decided[src.guid]
			if key == nil then
				key = self:DecideKey(src.guid, fishingKey, pickpocket) or false
				decided[src.guid] = key
			end
			if key then
				entry.sources[#entry.sources + 1] = { key = key, guid = src.guid, quantity = src.quantity }
			end
		end
		if fishingKey and #entry.sources == 0 then
			entry.sources[1] = { key = fishingKey }
		end
		window.slots[slot] = entry
	end

	if fishingKey and count > 0 and not window.countedCatch then
		window.countedCatch = true
		-- Bobbers carry no stable GUID on every client, so each fishing window is one catch.
		local anyGuid = false
		for _, entry in pairs(window.slots) do
			for _, src in ipairs(entry.sources) do
				if src.guid then
					anyGuid = true
				end
			end
		end
		if not anyGuid and LibsFarmAssistant:IsSessionActive() then
			Ledger:AddLoot(fishingKey)
			LibsFarmAssistant:SendMessage('LIBSFA_ATTEMPT', fishingKey)
		end
	end
end

---Group loot at or above the threshold goes to a roll or the master looter, so only the chat
---line of the player who gets it should count.
---@param quality number|nil
---@return boolean
local function GoesToRoll(quality)
	if not IsInGroup or not IsInGroup() or not GetLootThreshold then
		return false
	end
	local getMethod = C_PartyInfo and C_PartyInfo.GetLootMethod
	local method = getMethod and getMethod()
	local methods = Enum and Enum.LootMethod
	if method == nil or not methods or method == methods.Freeforall or method == methods.Personal then
		return false
	end
	return (quality or 0) >= (GetLootThreshold() or 99)
end

function LootTracker:OnSlotCleared(_, slot)
	local window = self.window
	local entry = window and window.slots[slot]
	if not entry or entry.done then
		return
	end
	entry.done = true

	if entry.type == SLOT_MONEY then
		if LibsFarmAssistant:IsSessionActive() and LibsFarmAssistant.db.tracking.money then
			for _, src in ipairs(entry.sources) do
				if src.quantity and src.key then
					Ledger:AddSourceMoney(src.key, src.quantity)
				end
			end
		end
		return
	end

	if entry.type ~= SLOT_ITEM or not entry.itemID or entry.locked or GoesToRoll(entry.quality) then
		return
	end

	-- The chat line normally follows the slot; when it came first, there is nothing left to expect.
	if not entry.chatSeen then
		local now = GetTime()
		local expect = expected[entry.itemID]
		if expect and now - expect.at < EXPECT_WINDOW then
			expect.count = expect.count + entry.quantity
			expect.at = now
		else
			expected[entry.itemID] = { count = entry.quantity, at = now }
		end
	end

	local sources = entry.sources
	if #sources == 0 then
		self:Record(entry.itemID, entry.quantity, entry.link, nil, false, entry.quality, true)
		return
	end
	-- A slot shared by several corpses (area loot) is split by what each one contributed.
	local assigned = 0
	for i, src in ipairs(sources) do
		local quantity = src.quantity or 0
		if #sources == 1 or i == #sources then
			quantity = math.max(entry.quantity - assigned, 0)
		end
		assigned = assigned + quantity
		if quantity > 0 then
			self:Record(entry.itemID, quantity, entry.link, src.key, true, entry.quality, true)
		end
	end
end

function LootTracker:OnLootClosed()
	if self.window then
		self.window.closed = true
		self.window.closedAt = GetTime()
	end
end

----------------------------------------------------------------------------------------------------
-- Chat
----------------------------------------------------------------------------------------------------

---@param text string
---@return string|nil kind, string|nil link, number quantity
function LootTracker:ParseChat(text)
	if not chatPatterns then
		BuildPatterns()
	end
	for _, entry in ipairs(chatPatterns) do
		local link, quantity = text:match(entry.pattern)
		if link then
			return entry.kind, link, Compat.ParseNumber(quantity) or 1
		end
	end
	return nil, nil, 0
end

---Loot lines hidden during combat lockdown are re-read by their line ID once it lifts.
function LootTracker:RetryHidden()
	if not next(self.hidden) or not C_ChatInfo or not C_ChatInfo.GetChatLineText then
		return
	end
	if C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() then
		return
	end
	local pending = self.hidden
	self.hidden = {}
	for lineID, info in pairs(pending) do
		local ok, text = pcall(C_ChatInfo.GetChatLineText, lineID)
		if ok and type(text) == 'string' and Compat.CanAccess(text) then
			self:HandleChatLoot(text, info.key)
		end
	end
end

function LootTracker:OnChatLoot(_, text, ...)
	if not Compat.CanAccess(text) then
		local lineID = Compat.Readable((select(10, ...)))
		if lineID and LibsFarmAssistant:IsSessionActive() then
			self.hidden[lineID] = { key = LibsFarmAssistant.Sources:RecentKill(), at = GetTime() }
		end
		return
	end
	if type(text) ~= 'string' then
		return
	end
	self:HandleChatLoot(text)
end

---@param text string
---@param key? string source captured when the line arrived (for delayed lines)
function LootTracker:HandleChatLoot(text, key)
	local kind, link, quantity = self:ParseChat(text)
	if not kind or kind == 'refund' then
		return
	end
	local itemID = Compat.ItemIDFromLink(link)
	if not itemID then
		return
	end

	-- A chat line for an item still sitting in the open loot window: the slot will record it.
	local window = self.window
	if window and not window.closed then
		for _, entry in pairs(window.slots) do
			if entry.itemID == itemID and not entry.done and not entry.chatSeen then
				entry.chatSeen = true
				return
			end
		end
	end

	local expect = expected[itemID]
	if expect and GetTime() - expect.at < EXPECT_WINDOW then
		local used = math.min(expect.count, quantity)
		expect.count = expect.count - used
		quantity = quantity - used
		if expect.count <= 0 then
			expected[itemID] = nil
		end
	end
	if quantity <= 0 then
		return
	end

	local tracking = LibsFarmAssistant.db.tracking
	if kind == 'loot' then
		key = key or LibsFarmAssistant.Sources:RecentKill()
		self:Record(itemID, quantity, link, key, key ~= nil, nil, true)
	elseif kind == 'reward' and tracking.countQuestRewards and not LibsFarmAssistant.MoneyTracker:IsShoppingOrTrading() then
		Ledger.RememberSource('q', 'Rewards and other', 'reward')
		self:Record(itemID, quantity, link, 'q', false)
	elseif kind == 'created' and tracking.countCrafted then
		self:Record(itemID, quantity, link, nil, false)
	end
end
