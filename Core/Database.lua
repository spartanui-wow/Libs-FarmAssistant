---@class LibsFarmAssistant
local LibsFarmAssistant = LibStub('AceAddon-3.0'):GetAddon('Libs-FarmAssistant')

---@class LibsFarmAssistant.Database : AceModule
local Database = LibsFarmAssistant:NewModule('Database')
LibsFarmAssistant.Database = Database

local DATA_VERSION = 2

local defaults = {
	global = {
		-- Account-wide name caches so history stays readable offline and on other characters.
		itemMeta = {}, -- [itemID] = { n = name, q = quality, p = sellPrice, b = bindType }
		sourceMeta = {}, -- [sourceKey] = { n = name, k = kind, z = zone }
		characters = {}, -- [AceDB char key] = { name, realm, class, level, scanned, lockouts, hunts }
		sharedHunts = {}, -- [itemID string] = { sources, bosses, chance, mode } hunted on every character
	},
	char = {
		dataVersion = 0,
		session = nil, -- Ledger bucket plus session fields, created by SessionManager
		days = {}, -- ['2026-09-28'] = bucket
		months = {}, -- ['2026-09'] = bucket
		lifetime = nil, -- bucket
		sessions = {}, -- archived session summaries, newest first
		hunts = {}, -- [itemID string] = hunt
		watchedItems = {}, -- [itemID string] = { itemID, name, link, icon, quality }
		factionTotals = {}, -- [factionID] = last seen monotonic total
	},
	profile = {
		tracking = {
			loot = true,
			money = true,
			currency = true,
			reputation = true,
			experience = true,
			honor = true,
			kills = true,
			mode = 'all', -- 'all' = every item in the chosen qualities, 'selected' = watched and hunted items only
			qualities = { [0] = true, [1] = true, [2] = true, [3] = true, [4] = true, [5] = true, [6] = true, [7] = true },
			countCrafted = false,
			countQuestRewards = true,
		},
		pricing = {
			source = 'best', -- 'vendor', 'auction', 'best'
		},
		session = {
			newAfterMinutes = 30,
			pauseWhenAFK = true,
		},
		autoLoot = {
			enabled = true,
			fastLoot = true,
			closeLoot = false,
			lootAll = false,
			printLooted = false,
			printIgnored = false,
			printReason = true,
		},
		lootModules = {
			whitelist = {},
			blacklist = {},
			alertList = {},
			alertSound = SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959,
			lootQuest = true,
			lootTokens = true,
			ignoreBOP = false,
			fishingMode = true,
			minPrice = 0,
			rarityTable = {
				[0] = false,
				[1] = false,
				[2] = true,
				[3] = true,
				[4] = true,
				[5] = true,
			},
		},
		hunts = {
			sound = true,
			announce = true,
		},
		goals = {},
		goalSound = true,
		sessionNotifications = {
			enabled = false,
			frequencyMinutes = 15,
		},
		display = {
			format = 'value', -- broker text: 'value', 'gold', 'items', 'kills', 'hunt'
		},
		tooltips = {
			items = true,
			units = true,
		},
		chatEcho = false,
		smartSession = {
			enabled = false,
			autoStart = false,
			lootThreshold = 3,
			timeWindowSeconds = 30,
		},
		window = {
			point = 'CENTER',
			relativePoint = 'CENTER',
			x = 0,
			y = 0,
			width = 780,
			height = 500,
			scale = 1,
			page = 'overview',
			range = 'session',
		},
		tracker = {
			shown = false,
			locked = false,
			point = 'RIGHT',
			relativePoint = 'RIGHT',
			x = -180,
			y = 120,
			scale = 1,
			lines = { value = true, gold = false, kills = true, xp = true, hunts = true, rep = true },
		},
		minimap = {
			hide = false,
		},
	},
}

function Database:OnInitialize()
	-- Before AceDB fills in defaults, so a removed value gets its default back
	self:RepairSetupValues(_G.LibsFarmAssistantDB)

	local dbobj = LibStub('AceDB-3.0'):New('LibsFarmAssistantDB', defaults, true)
	LibsFarmAssistant.dbobj = dbobj
	LibsFarmAssistant.db = dbobj.profile
	LibsFarmAssistant.global = dbobj.global
	LibsFarmAssistant.char = dbobj.char

	self:Migrate()

	dbobj.RegisterCallback(LibsFarmAssistant, 'OnProfileChanged', 'OnProfileChanged')
	dbobj.RegisterCallback(LibsFarmAssistant, 'OnProfileCopied', 'OnProfileChanged')
	dbobj.RegisterCallback(LibsFarmAssistant, 'OnProfileReset', 'OnProfileChanged')
end

-- Version 1 stored one flat session and short history; carry the watched items and goals
-- forward and let the ledger start clean.
function Database:Migrate()
	local char = LibsFarmAssistant.char
	if (char.dataVersion or 0) >= DATA_VERSION then
		return
	end

	local old = char.session
	if old and old.items and not old.version then
		if old.watchedItems then
			for key, info in pairs(old.watchedItems) do
				char.watchedItems[key] = info
			end
		end
		char.session = nil
	end
	char.history = nil
	char.bestRates = nil

	local profile = LibsFarmAssistant.db
	if profile.qualityFilter then
		for q = 0, 7 do
			profile.tracking.qualities[q] = q >= profile.qualityFilter
		end
		profile.qualityFilter = nil
	end
	profile.popup = nil
	if profile.display and (profile.display.format == 'money' or profile.display.format == 'combined') then
		profile.display.format = 'value'
	end

	char.dataVersion = DATA_VERSION
end

-- An early first-run page saved an empty table instead of true or false. Settings it may have
-- touched go back to their default when they hold a table; keys nothing reads any more are dropped.
local SETUP_SETTINGS = {
	{ path = { 'tracking', 'mode' } },
	{ path = { 'tracking', 'qualities', 0 } },
	{ path = { 'tooltips', 'items' } },
	{ path = { 'tooltips', 'units' } },
	{ path = { 'tracker', 'shown' } },
	{ path = { 'trackMoney' }, unused = true },
	{ path = { 'trackCurrency' }, unused = true },
}

---Fix settings the old first-run page stored as tables, in every saved profile. Runs once per account.
---@param sv table|nil The saved variable, before AceDB has loaded it
function Database:RepairSetupValues(sv)
	if type(sv) ~= 'table' then
		return
	end
	if type(sv.global) ~= 'table' then
		sv.global = {}
	end
	if sv.global.setupValuesRepaired then
		return
	end
	local repaired = 0
	local profiles = type(sv.profiles) == 'table' and sv.profiles or {}
	for _, profile in pairs(profiles) do
		if type(profile) == 'table' then
			for _, setting in ipairs(SETUP_SETTINGS) do
				local parent = profile
				local path = setting.path
				for i = 1, #path - 1 do
					parent = type(parent) == 'table' and rawget(parent, path[i]) or nil
				end
				local key = path[#path]
				if type(parent) == 'table' then
					local value = rawget(parent, key)
					if value ~= nil and (setting.unused or type(value) == 'table') then
						parent[key] = nil
						repaired = repaired + 1
					end
				end
			end
		end
	end
	sv.global.setupValuesRepaired = true
	if repaired > 0 then
		LibsFarmAssistant:Log('Repaired ' .. repaired .. ' saved setting(s) from the old setup page', 'info')
	end
end

function LibsFarmAssistant:OnProfileChanged()
	self.db = self.dbobj.profile
	if self.InvalidateLootingModuleCache then
		self:InvalidateLootingModuleCache()
	end
	self:SendMessage('LIBSFA_SETTINGS_CHANGED')
	self:UpdateDisplay()
end
