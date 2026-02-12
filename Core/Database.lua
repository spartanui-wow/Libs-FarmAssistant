---@class LibsFarmAssistant
local LibsFarmAssistant = LibStub('AceAddon-3.0'):GetAddon('Libs-FarmAssistant')

local defaults = {
	char = {
		session = {
			active = true,
			startTime = 0, -- GetTime() value
			pausedDuration = 0, -- Accumulated paused seconds
			items = {}, -- [itemID] = { name, link, icon, quality, count, sellPrice }
			watchedItems = {}, -- [itemID] = { itemID, name, link, icon, quality }
			money = 0, -- Copper gained (delta tracking)
			currencies = {}, -- [currencyName] = { name, icon, count }
			reputation = {}, -- [factionName] = gained
			honor = 0, -- Total honor gained
		},
		history = {}, -- Array of session snapshots, newest first
		bestRates = {
			itemsPerHour = 0,
			goldPerHour = 0,
			honorPerHour = 0,
		},
	},
	profile = {
		qualityFilter = 0, -- Minimum quality to track (0=Poor, 1=Common, etc.)
		autoLoot = {
			enabled = true, -- Master toggle for auto-looting
			fastLoot = true, -- Use LOOT_READY (true) vs LOOT_OPENED (false)
			closeLoot = false, -- Close loot window after auto-looting
			lootAll = false, -- Loot everything (overrides all filters)
			printLooted = false, -- Chat output for looted items
			printIgnored = false, -- Chat output for ignored items
			printReason = true, -- Show reason in chat output
		},
		lootModules = {
			whitelist = {}, -- { [itemID_string] = itemName }
			blacklist = {}, -- { [itemID_string] = itemName }
			alertList = {}, -- { [itemID_string] = itemName }
			alertSound = SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959,
			lootQuest = true, -- Auto-loot quest items
			lootTokens = true, -- Loot items with no vendor price
			ignoreBOP = false, -- Skip Bind on Pickup items
			fishingMode = true, -- Loot everything while fishing
			minPrice = 0, -- Minimum vendor price in copper (0 = disabled)
			rarityTable = { -- Per-quality tier toggles
				[0] = false, -- Poor (grey)
				[1] = false, -- Common (white)
				[2] = true, -- Uncommon (green)
				[3] = true, -- Rare (blue)
				[4] = true, -- Epic (purple)
				[5] = true, -- Legendary (orange)
			},
		},
		tracking = {
			loot = true,
			money = true,
			currency = true,
			reputation = true,
			honor = true,
			itemValue = true,
		},
		goals = {}, -- Array of goal definitions
		goalSound = true, -- Play sound on goal completion
		sessionNotifications = {
			enabled = false,
			frequencyMinutes = 15,
		},
		display = {
			format = 'items', -- 'items', 'money', 'combined'
		},
		chatEcho = false, -- Echo loot/money/currency/rep/honor to chat
		smartSession = {
			enabled = false,
			autoStart = false,
			lootThreshold = 3,
			timeWindowSeconds = 30,
		},
		popup = {
			point = 'CENTER',
			x = 0,
			y = 0,
			width = 420,
			height = 350,
		},
		minimap = {
			hide = false,
		},
	},
}

function LibsFarmAssistant:InitializeDatabase()
	self.dbobj = LibStub('AceDB-3.0'):New('LibsFarmAssistantDB', defaults, true)
	self.db = self.dbobj.profile
	self.session = self.dbobj.char.session

	-- Profile callbacks
	self.dbobj.RegisterCallback(self, 'OnProfileChanged', 'OnProfileChanged')
	self.dbobj.RegisterCallback(self, 'OnProfileCopied', 'OnProfileChanged')
	self.dbobj.RegisterCallback(self, 'OnProfileReset', 'OnProfileChanged')
end

function LibsFarmAssistant:OnProfileChanged()
	self.db = self.dbobj.profile
	if self.InvalidateLootingModuleCache then
		self:InvalidateLootingModuleCache()
	end
	if self.UpdateDisplay then
		self:UpdateDisplay()
	end
end
