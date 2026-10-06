-- Headless client for Lib's Farm Assistant. Runs under the Lua language server binary:
--   lua-language-server.exe Tests/run.lua
-- It loads the real Ace3 core and the addon's files against a small fake client, so trackers can
-- be driven through kills, loot windows, chat, money and reputation without the game.

local H = {}
_G.H = H

H.root = (arg and arg[0] and arg[0]:match('^(.*)[/\\]Tests[/\\]')) or '.'

----------------------------------------------------------------------------------------------------
-- Lua 5.1 shims
----------------------------------------------------------------------------------------------------

unpack = unpack or table.unpack
getn = function(t)
	return #t
end
floor, ceil, max, min, abs = math.floor, math.ceil, math.max, math.min, math.abs
tinsert, tremove, sort, concat = table.insert, table.remove, table.sort, table.concat
strsub, strfind, strmatch, gsub, strlower, strupper, strlen, strrep = string.sub, string.find, string.match, string.gsub, string.lower, string.upper, string.len, string.rep
strbyte, strchar = string.byte, string.char
tostringall = function(...)
	local out = {}
	for i = 1, select('#', ...) do
		out[i] = tostring((select(i, ...)))
	end
	return unpack(out, 1, select('#', ...))
end

-- WoW's string.format truncates floats for %d; Lua 5.4 raises an error instead.
local rawFormat = string.format
string.format = function(fmt, ...)
	local ok, result = pcall(rawFormat, fmt, ...)
	if ok then
		return result
	end
	local args = { ... }
	for i = 1, select('#', ...) do
		if math.type and math.type(args[i]) == 'float' then
			args[i] = args[i] >= 0 and math.floor(args[i]) or math.ceil(args[i])
		end
	end
	return rawFormat(fmt, unpack(args, 1, select('#', ...)))
end
format = string.format

function wipe(t)
	for k in pairs(t) do
		t[k] = nil
	end
	return t
end
table.wipe = wipe

function strsplit(sep, text, limit)
	local out = {}
	local pattern = '([^' .. sep:gsub('%p', '%%%0') .. ']*)'
	for piece in (text .. sep):gmatch(pattern .. sep:gsub('%p', '%%%0')) do
		out[#out + 1] = piece
	end
	return unpack(out)
end

function strtrim(s)
	return (s:gsub('^%s+', ''):gsub('%s+$', ''))
end
string.trim = strtrim

function strjoin(sep, ...)
	return table.concat({ ... }, sep)
end

function BreakUpLargeNumbers(n)
	local text = tostring(math.floor(n))
	local k
	repeat
		text, k = text:gsub('^(-?%d+)(%d%d%d)', '%1,%2')
	until k == 0
	return text
end

function hooksecurefunc() end
function issecurevariable()
	return true
end
function geterrorhandler()
	return function(err)
		error(err, 2)
	end
end
function securecallfunction(fn, ...)
	return fn(...)
end
function xpcall_err(err)
	print(debug.traceback(err))
end

----------------------------------------------------------------------------------------------------
-- Clock
----------------------------------------------------------------------------------------------------

H.now = 1000
H.epoch = os.time({ year = 2026, month = 9, day = 28, hour = 14 })

function GetTime()
	return H.now
end

function time(t)
	if t then
		return os.time(t)
	end
	return H.epoch + math.floor(H.now - 1000)
end

function date(fmt, t)
	return os.date(fmt, t or time())
end

H.timers = {}

C_Timer = {
	After = function(delay, callback)
		H.timers[#H.timers + 1] = { at = H.now + delay, fn = callback }
	end,
}
C_Timer.NewTimer = function(delay, callback)
	local timer = { cancelled = false }
	C_Timer.After(delay, function()
		if not timer.cancelled then
			callback(timer)
		end
	end)
	function timer:Cancel()
		self.cancelled = true
	end
	return timer
end

---Moves the clock forward, running due timers in order.
function H.advance(seconds)
	local target = H.now + seconds
	while true do
		local nextIndex, nextAt
		for i, timer in ipairs(H.timers) do
			if timer.at <= target and (not nextAt or timer.at < nextAt) then
				nextIndex, nextAt = i, timer.at
			end
		end
		if not nextIndex then
			break
		end
		local timer = table.remove(H.timers, nextIndex)
		H.now = math.max(H.now, timer.at)
		timer.fn()
	end
	H.now = target
end

----------------------------------------------------------------------------------------------------
-- Frames and events
----------------------------------------------------------------------------------------------------

H.eventFrames = {}
H.created = {}

local FrameMethods = {}
local frameMeta = {
	__index = function(self, key)
		local method = FrameMethods[key]
		if method then
			return method
		end
		-- Unknown widget methods (capitalized, like the real API) are harmless no-ops, so UI code
		-- can be smoke-tested. Lowercase keys are the addon's own fields and read as nil.
		if type(key) == 'string' and key:match('^%u') then
			return function()
				return nil
			end
		end
		return nil
	end,
}

function FrameMethods:RegisterEvent(event)
	H.eventFrames[event] = H.eventFrames[event] or {}
	H.eventFrames[event][self] = true
end
function FrameMethods:RegisterUnitEvent(event)
	FrameMethods.RegisterEvent(self, event)
end
function FrameMethods:UnregisterEvent(event)
	if H.eventFrames[event] then
		H.eventFrames[event][self] = nil
	end
end
function FrameMethods:UnregisterAllEvents()
	for _, frames in pairs(H.eventFrames) do
		frames[self] = nil
	end
end
function FrameMethods:IsEventRegistered(event)
	return H.eventFrames[event] and H.eventFrames[event][self] or false
end
function FrameMethods:SetScript(name, fn)
	self.scripts[name] = fn
end
function FrameMethods:GetScript(name)
	return self.scripts[name]
end
function FrameMethods:HookScript(name, fn)
	local old = self.scripts[name]
	self.scripts[name] = function(...)
		if old then
			old(...)
		end
		fn(...)
	end
end
function FrameMethods:Show()
	self.shown = true
	if self.scripts.OnShow then
		self.scripts.OnShow(self)
	end
end
function FrameMethods:Hide()
	local was = self.shown
	self.shown = false
	if was and self.scripts.OnHide then
		self.scripts.OnHide(self)
	end
end
function FrameMethods:IsShown()
	return self.shown
end
function FrameMethods:IsVisible()
	return self.shown
end
function FrameMethods:SetShown(show)
	if show then
		self:Show()
	else
		self:Hide()
	end
end
function FrameMethods:GetName()
	return self.name
end
function FrameMethods:GetWidth()
	return self.width or 100
end
function FrameMethods:GetHeight()
	return self.height or 20
end
function FrameMethods:GetSize()
	return self:GetWidth(), self:GetHeight()
end
function FrameMethods:SetWidth(w)
	self.width = w
end
function FrameMethods:SetHeight(h)
	self.height = h
end
function FrameMethods:SetSize(w, h)
	self.width, self.height = w, h
end
function FrameMethods:GetEffectiveScale()
	return 1
end
function FrameMethods:GetScale()
	return 1
end
function FrameMethods:GetParent()
	return self.parent
end
function FrameMethods:SetText(text)
	self.text = text
end
function FrameMethods:GetText()
	return self.text
end
function FrameMethods:GetStringWidth()
	return #(tostring(self.text or '')) * 6
end
function FrameMethods:GetStringHeight()
	return 12
end
function FrameMethods:GetFont()
	return 'Fonts\\FRIZQT__.TTF', 12, ''
end
function FrameMethods:GetFrameLevel()
	return 1
end
function FrameMethods:GetNumPoints()
	return 1
end
function FrameMethods:GetPoint()
	return 'CENTER', nil, 'CENTER', 0, 0
end
function FrameMethods:GetLeft()
	return 0
end
function FrameMethods:GetTop()
	return 0
end
function FrameMethods:GetRight()
	return 100
end
function FrameMethods:GetBottom()
	return 0
end
function FrameMethods:GetCenter()
	return 50, 50
end
function FrameMethods:IsMouseOver()
	return false
end
function FrameMethods:GetChecked()
	return self.checked
end
function FrameMethods:SetChecked(v)
	self.checked = v
end
function FrameMethods:GetValue()
	return self.value or 0
end
function FrameMethods:SetValue(v)
	self.value = v
end
function FrameMethods:GetMinMaxValues()
	return 0, self.maxValue or 1
end
function FrameMethods:SetMinMaxValues(_, maxValue)
	self.maxValue = maxValue
end
function FrameMethods:GetVerticalScroll()
	return 0
end
function FrameMethods:GetNumChildren()
	return 0
end
function FrameMethods:GetObjectType()
	return self.objectType
end
function FrameMethods:IsForbidden()
	return false
end
function FrameMethods:GetOwner()
	return self.owner
end
function FrameMethods:SetOwner(owner)
	self.owner = owner
end
function FrameMethods:NumLines()
	return 0
end
function FrameMethods:CreateFontString(name)
	return H.NewFrame('FontString', name, self)
end
function FrameMethods:CreateTexture(name)
	return H.NewFrame('Texture', name, self)
end
function FrameMethods:CreateMaskTexture(name)
	return H.NewFrame('MaskTexture', name, self)
end
function FrameMethods:CreateAnimationGroup()
	return H.NewFrame('AnimationGroup', nil, self)
end
function FrameMethods:CreateAnimation()
	return H.NewFrame('Animation', nil, self)
end
function FrameMethods:GetFontString()
	self.fontString = self.fontString or H.NewFrame('FontString', nil, self)
	return self.fontString
end
function FrameMethods:GetStatusBarTexture()
	self.barTexture = self.barTexture or H.NewFrame('Texture', nil, self)
	return self.barTexture
end
function FrameMethods:Click(button)
	if self.scripts.OnClick then
		self.scripts.OnClick(self, button or 'LeftButton')
	end
end

function H.NewFrame(objectType, name, parent)
	local frame = setmetatable({ objectType = objectType, name = name, parent = parent, scripts = {}, shown = true }, frameMeta)
	if name then
		_G[name] = frame
	end
	H.created[#H.created + 1] = frame
	return frame
end

function CreateFrame(objectType, name, parent)
	return H.NewFrame(objectType, name, parent)
end

UIParent = H.NewFrame('Frame', 'UIParent')
WorldFrame = H.NewFrame('Frame', 'WorldFrame')
GameTooltip = H.NewFrame('GameTooltip', 'GameTooltip')
ItemRefTooltip = H.NewFrame('GameTooltip', 'ItemRefTooltip')
RaidWarningFrame = H.NewFrame('Frame', 'RaidWarningFrame')
DEFAULT_CHAT_FRAME = H.NewFrame('Frame', 'ChatFrame1')
ChatFrame1 = DEFAULT_CHAT_FRAME
UISpecialFrames = {}
StaticPopupDialogs = {}
StaticPopup_Show = function(name)
	H.lastPopup = name
end

H.chat = {}
function DEFAULT_CHAT_FRAME:AddMessage(text)
	H.chat[#H.chat + 1] = text
end
function print(...)
	H.chat[#H.chat + 1] = table.concat({ tostringall(...) }, ' ')
end
H.stdout = _ENV and rawget(_ENV, 'io') and io.write or nil

---Fires a game event at every frame registered for it.
function H.fire(event, ...)
	local frames = H.eventFrames[event]
	if not frames then
		return
	end
	local list = {}
	for frame in pairs(frames) do
		list[#list + 1] = frame
	end
	for _, frame in ipairs(list) do
		local handler = frame.scripts.OnEvent
		if handler then
			handler(frame, event, ...)
		end
	end
end

----------------------------------------------------------------------------------------------------
-- Game state
----------------------------------------------------------------------------------------------------

H.interface = 120100
function GetBuildInfo()
	return '12.1.0', '99999', 'Sep 28 2026', H.interface
end
WOW_PROJECT_ID = 1
WOW_PROJECT_MAINLINE = 1

H.state = {
	money = 100000,
	level = 70,
	xp = 0,
	xpMax = 100000,
	units = {}, -- unit -> { guid, name, dead, tapDenied }
	loot = nil, -- { fishing, slots = { { type, link, quantity, quality, sources = { guid, qty, ... } } } }
	items = {}, -- itemID -> { name, quality, sellPrice, bindType }
	factions = {}, -- factionID -> { name, reaction, bottom, top, value }
	currencies = {}, -- currencyID -> { name, quantity }
	zone = 'Winterspring',
	afk = false,
	resting = false,
	inCombat = false,
}

function GetMoney()
	return H.state.money
end
function UnitLevel()
	return H.state.level
end
function UnitXP()
	return H.state.xp
end
function UnitXPMax()
	return H.state.xpMax
end
function GetXPExhaustion()
	return H.state.rested
end
function IsXPUserDisabled()
	return false
end
function IsPlayerAtEffectiveMaxLevel()
	return H.state.level >= 80
end
function UnitIsAFK()
	return H.state.afk
end
function IsResting()
	return H.state.resting
end
H.cvars = { autoLootDefault = '0' }
H.modifiedClicks = { AUTOLOOTTOGGLE = 'SHIFT' }
C_CVar = {
	GetCVarBool = function(name)
		return H.cvars[name] == '1'
	end,
	GetCVar = function(name)
		return H.cvars[name]
	end,
	SetCVar = function(name, value)
		H.cvars[name] = tostring(value)
		H.fire('CVAR_UPDATE', name, tostring(value))
		return true
	end,
}
function GetModifiedClick(action)
	return H.modifiedClicks[action]
end
function SetModifiedClick(action, key)
	H.modifiedClicks[action] = key
end
function GetCurrentBindingSet()
	return 1
end
function SaveBindings()
	H.fire('UPDATE_BINDINGS')
end
function IsEncounterInProgress()
	return false
end
function UnitSex()
	return 2
end
function UnitName(unit)
	local u = H.state.units[unit]
	if unit == 'player' then
		return 'Tester'
	end
	return u and u.name
end
function UnitGUID(unit)
	local u = H.state.units[unit]
	if unit == 'player' then
		return 'Player-1-00000001'
	end
	return u and u.guid
end
function UnitExists(unit)
	return unit == 'player' or H.state.units[unit] ~= nil
end
function UnitIsDead(unit)
	local u = H.state.units[unit]
	return u and u.dead or false
end
function UnitIsTapDenied(unit)
	local u = H.state.units[unit]
	return u and u.tapDenied or false
end
function UnitClass()
	return 'Mage', 'MAGE', 8
end
function UnitRace()
	return 'Human', 'Human', 1
end
function UnitFactionGroup()
	return 'Alliance', 'Alliance'
end
function GetRealmName()
	return 'Testrealm'
end
function GetNormalizedRealmName()
	return 'Testrealm'
end
function UnitNameUnmodified()
	return 'Tester'
end
function GetCurrentRegion()
	return 1
end
function GetCurrentRegionName()
	return 'US'
end
function GetLocale()
	return 'enUS'
end
H.loggedIn = false
function IsLoggedIn()
	return H.loggedIn
end
function UnitAffectingCombat()
	return H.state.inCombat
end
function InCombatLockdown()
	return H.state.inCombat
end
function IsInGroup()
	return H.inGroup
end
function GetRealZoneText()
	return H.state.zone
end
GetZoneText = GetRealZoneText
function IsShiftKeyDown()
	return false
end
IsControlKeyDown, IsAltKeyDown = IsShiftKeyDown, IsShiftKeyDown
function PlaySound(id)
	H.lastSound = id
end
function RaidNotice_AddMessage(_, text)
	H.lastRaidNotice = text
end
ChatTypeInfo = { RAID_WARNING = { r = 1, g = 1, b = 1 } }
SOUNDKIT = { RAID_WARNING = 8959, READY_CHECK = 8960 }
function GetCursorInfo() end
function ClearCursor() end
function IsFishingLoot()
	return H.state.loot and H.state.loot.fishing or false
end
function GetNumLootItems()
	return H.state.loot and #H.state.loot.slots or 0
end
function GetLootSlotType(slot)
	return H.state.loot.slots[slot].type or 1
end
function GetLootSlotInfo(slot)
	local s = H.state.loot.slots[slot]
	return 134400, 'Item', s.quantity or 1, nil, s.quality or 1, false, false, nil, true, s.type == 2
end
function GetLootSlotLink(slot)
	return H.state.loot.slots[slot].link
end
function GetLootSourceInfo(slot)
	return unpack(H.state.loot.slots[slot].sources or {})
end
function LootSlot(slot)
	H.fire('LOOT_SLOT_CLEARED', slot)
end
function CloseLoot()
	H.fire('LOOT_CLOSED')
end
function GetLootThreshold()
	return 2
end
H.lootMethod = 0
H.inGroup = false
C_PartyInfo = {
	GetLootMethod = function()
		return H.lootMethod
	end,
}

-- A stand-in for Retail's secret values: readable only through canaccessvalue.
H.SECRET = setmetatable({ secret = true }, {
	__eq = function()
		error('attempt to compare a secret value')
	end,
})
function canaccessvalue(value)
	return not (type(value) == 'table' and rawget(value, 'secret') == true)
end
function issecretvalue(value)
	return not canaccessvalue(value)
end

Enum = {
	LootSlotType = { None = 0, Item = 1, Money = 2, Currency = 3 },
	LootMethod = { Freeforall = 0, Roundrobin = 1, Masterlooter = 2, Group = 3, Needbeforegreed = 4, Personal = 5 },
}

C_Item = {
	GetItemInfo = function(item)
		local id = type(item) == 'number' and item or tonumber(tostring(item):match('item:(%d+)'))
		local info = id and H.state.items[id]
		if not info then
			return nil
		end
		return info.name, H.Link(id), info.quality, 1, 1, 'Trade Goods', 'Cloth', 20, '', 134400, info.sellPrice or 0, 7, 5, info.bindType or 0
	end,
	GetItemIconByID = function()
		return 134400
	end,
	RequestLoadItemDataByID = function(id)
		H.requested = H.requested or {}
		H.requested[id] = true
	end,
	GetItemQualityColor = function()
		return 1, 1, 1, 'ffffffff'
	end,
}

C_CurrencyInfo = {
	GetCurrencyInfo = function(id)
		local c = H.state.currencies[id]
		if not c then
			return nil
		end
		return { name = c.name, quantity = c.quantity, iconFileID = 1, quality = 1 }
	end,
}

C_Reputation = {
	GetFactionDataByID = function(id)
		local f = H.state.factions[id]
		if not f then
			return nil
		end
		return {
			factionID = id,
			name = f.name,
			reaction = f.reaction,
			currentReactionThreshold = f.bottom,
			nextReactionThreshold = f.top,
			currentStanding = f.value,
			isHeader = false,
			isHeaderWithRep = false,
		}
	end,
	GetNumFactions = function()
		local n = 0
		for _ in pairs(H.state.factions) do
			n = n + 1
		end
		return n
	end,
	GetFactionDataByIndex = function(i)
		local ids = {}
		for id in pairs(H.state.factions) do
			ids[#ids + 1] = id
		end
		table.sort(ids)
		return ids[i] and C_Reputation.GetFactionDataByID(ids[i])
	end,
	IsMajorFaction = function()
		return false
	end,
	IsFactionParagon = function()
		return false
	end,
}

C_Map = {
	GetBestMapForUnit = function()
		return 1452
	end,
}

C_DateAndTime = {
	GetSecondsUntilWeeklyReset = function()
		return 3 * 86400
	end,
}

C_EventUtils = {
	IsEventValid = function()
		return true
	end,
}

FACTION_STANDING_LABEL4 = 'Neutral'
FACTION_STANDING_LABEL5 = 'Friendly'
FACTION_STANDING_LABEL6 = 'Honored'
FACTION_STANDING_LABEL7 = 'Revered'
FACTION_STANDING_LABEL8 = 'Exalted'
FACTION_STANDING_INCREASED = 'Reputation with %s increased by %d.'
FACTION_STANDING_INCREASED_BONUS = 'Reputation with %s increased by %d. (+%.1f Recruit A Friend bonus)'
LOOT_ITEM_SELF = 'You receive loot: %s.'
LOOT_ITEM_SELF_MULTIPLE = 'You receive loot: %sx%d.'
LOOT_ITEM_PUSHED_SELF = 'You receive item: %s.'
LOOT_ITEM_PUSHED_SELF_MULTIPLE = 'You receive item: %sx%d.'
LOOT_ITEM_CREATED_SELF = 'You create: %s.'
LOOT_ITEM_CREATED_SELF_MULTIPLE = 'You create: %sx%d.'
COMBATLOG_HONORGAIN = '%s dies, honorable kill Rank: %s (%d Honor Points)'
COMBATLOG_HONORAWARD = 'You have been awarded %d honor points.'

---@param id number
---@return string
function H.Link(id)
	local info = H.state.items[id] or { name = 'Item ' .. id }
	return string.format('|cffffffff|Hitem:%d::::::::70:::::|h[%s]|h|r', id, info.name)
end

---@param npcID number
---@param spawn number
---@return string
function H.CreatureGUID(npcID, spawn)
	return string.format('Creature-0-3767-1-1234-%d-%010X', npcID, spawn)
end

function H.ObjectGUID(objectID, spawn)
	return string.format('GameObject-0-3767-1-1234-%d-%010X', objectID, spawn)
end

----------------------------------------------------------------------------------------------------
-- Loading
----------------------------------------------------------------------------------------------------

H.ns = {}

function H.load(path)
	local full = H.root .. '/' .. path
	local chunk, err = loadfile(full)
	if not chunk then
		error('load failed: ' .. tostring(err))
	end
	chunk('Libs-FarmAssistant', H.ns)
end

local ACE = {
	'libs/Ace3/LibStub/LibStub.lua',
	'libs/Ace3/CallbackHandler-1.0/CallbackHandler-1.0.lua',
	'libs/Ace3/AceAddon-3.0/AceAddon-3.0.lua',
	'libs/Ace3/AceEvent-3.0/AceEvent-3.0.lua',
	'libs/Ace3/AceTimer-3.0/AceTimer-3.0.lua',
	'libs/Ace3/AceDB-3.0/AceDB-3.0.lua',
	'libs/Ace3/AceConsole-3.0/AceConsole-3.0.lua',
}

---Reads the .toc and returns the addon's own files (no libraries), optionally only Core.
function H.tocFiles(coreOnly)
	local files = {}
	for rawLine in io.lines(H.root .. '/Libs-FarmAssistant.toc') do
		local line = rawLine:gsub('\r', '')
		if line ~= '' and not line:match('^#') and not line:match('^libs') and line:match('%.lua$') then
			local path = line:gsub('\\', '/')
			if not coreOnly or not path:match('^UI/') then
				files[#files + 1] = path
			end
		end
	end
	return files
end

-- Libraries the UI needs, loaded for real where they are self-contained and stubbed where they
-- would need the whole widget toolkit.
local function LoadUILibraries()
	H.load('libs/Ace3/AceConfig-3.0/AceConfigRegistry-3.0/AceConfigRegistry-3.0.lua')
	H.load('libs/LibDataBroker-1.1/LibDataBroker-1.1.lua')
	local registry = LibStub('AceConfigRegistry-3.0')
	local config = LibStub:NewLibrary('AceConfig-3.0', 1)
	function config:RegisterOptionsTable(name, options)
		registry:RegisterOptionsTable(name, options)
		registry:ValidateOptionsTable(options, name)
		H.options = options
	end
	local dialog = LibStub:NewLibrary('AceConfigDialog-3.0', 1)
	function dialog:AddToBlizOptions() end
	function dialog:Open(name)
		H.openedOptions = name
	end
	local icon = LibStub:NewLibrary('LibDBIcon-1.0', 1)
	local buttons = {}
	function icon:Register(name)
		buttons[name] = H.NewFrame('Button', 'LibDBIcon10_' .. name)
	end
	function icon:GetMinimapButton(name)
		return buttons[name]
	end
	function icon:Show() end
	function icon:Hide() end
end

---Loads everything and runs the login sequence.
function H.boot(opts)
	opts = opts or {}
	for _, path in ipairs(ACE) do
		H.load(path)
	end
	if not opts.coreOnly then
		LoadUILibraries()
	end
	for _, path in ipairs(H.tocFiles(opts.coreOnly)) do
		H.load(path)
	end
	H.fire('ADDON_LOADED', 'Libs-FarmAssistant')
	H.loggedIn = true
	H.fire('PLAYER_LOGIN')
	H.fire('PLAYER_ENTERING_WORLD', true, false)
	H.addon = LibStub('AceAddon-3.0'):GetAddon('Libs-FarmAssistant')
	return H.addon
end

----------------------------------------------------------------------------------------------------
-- Scenario helpers
----------------------------------------------------------------------------------------------------

---Kills a creature (PARTY_KILL) and returns its GUID.
function H.kill(npcID, name, spawn)
	local guid = H.CreatureGUID(npcID, spawn)
	H.state.units.target = { guid = guid, name = name, dead = true }
	H.fire('PLAYER_TARGET_CHANGED')
	H.fire('PARTY_KILL', 'Player-1-00000001', guid)
	return guid
end

H.chatLines = {}

function C_ChatInfo_GetChatLineText(lineID)
	return H.chatLines[lineID]
end
C_ChatInfo = {
	GetChatLineText = C_ChatInfo_GetChatLineText,
	InChatMessagingLockdown = function()
		return H.lockdown or false
	end,
}

-- Saved instances: { name, reset, difficulty, raid, locked, bosses = { { name, killed } } }
H.saved = {}
H.worldBosses = {}
function GetNumSavedInstances()
	return #H.saved
end
function GetSavedInstanceInfo(i)
	local l = H.saved[i]
	local killed = 0
	for _, b in ipairs(l.bosses) do
		if b.killed then
			killed = killed + 1
		end
	end
	return l.name, 1000 + i, l.reset, 3, l.locked ~= false, false, 0, l.raid ~= false, 40, l.difficulty or 'Normal', #l.bosses, killed, false, 249
end
function GetSavedInstanceEncounterInfo(i, j)
	local b = H.saved[i].bosses[j]
	return b.name, 0, b.killed, false
end
function GetNumSavedWorldBosses()
	return #H.worldBosses
end
function GetSavedWorldBossInfo(i)
	local w = H.worldBosses[i]
	return w.name, 100 + i, w.reset
end
function RequestRaidInfo()
	H.fire('UPDATE_INSTANCE_INFO')
end

---Opens a loot window, takes every slot, closes it.
---@param slots table[] { link or itemID, quantity, guid, type }
function H.loot(slots, opts)
	opts = opts or {}
	local list = {}
	for _, s in ipairs(slots) do
		local link = s.itemID and H.Link(s.itemID) or nil
		local info = s.itemID and H.state.items[s.itemID]
		local sources = {}
		for _, src in ipairs(s.sources or { { s.guid, s.quantity or 1 } }) do
			sources[#sources + 1] = src[1]
			sources[#sources + 1] = src[2]
		end
		list[#list + 1] = { type = s.type or 1, link = link, quantity = s.quantity or 1, quality = info and info.quality or 1, sources = sources, noChat = s.noChat }
	end
	H.state.loot = { fishing = opts.fishing, slots = list }
	H.fire('LOOT_READY', true)
	H.fire('LOOT_OPENED', true)
	for slot, s in ipairs(list) do
		if not opts.leave or not opts.leave[slot] then
			if s.type == 2 then
				H.state.money = H.state.money + s.quantity
				H.fire('PLAYER_MONEY')
			end
			H.fire('LOOT_SLOT_CLEARED', slot)
			if s.type == 1 and not s.noChat then
				local q = s.quantity
				local line = q > 1 and string.format(LOOT_ITEM_SELF_MULTIPLE, s.link, q) or string.format(LOOT_ITEM_SELF, s.link)
				H.fire('CHAT_MSG_LOOT', line, 'Tester')
			end
		end
	end
	H.fire('LOOT_CLOSED')
	H.state.loot = nil
end

----------------------------------------------------------------------------------------------------
-- Assertions
----------------------------------------------------------------------------------------------------

H.passed, H.failed = 0, 0

function H.eq(actual, expected, label)
	if actual == expected then
		H.passed = H.passed + 1
	else
		H.failed = H.failed + 1
		io.write(string.format('FAIL %s: expected %s, got %s\n', label, tostring(expected), tostring(actual)))
	end
end

function H.ok(value, label)
	H.eq(not not value, true, label)
end

function H.test(name, fn)
	local ok, err = xpcall(fn, debug.traceback)
	if not ok then
		H.failed = H.failed + 1
		io.write('ERROR in ' .. name .. ': ' .. tostring(err) .. '\n')
	end
end

return H
