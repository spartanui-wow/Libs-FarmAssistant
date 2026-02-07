---@class LibsFarmAssistant
local LibsFarmAssistant = LibStub('AceAddon-3.0'):GetAddon('Libs-FarmAssistant')

local defaults = {
	char = {
		session = {
			active = true,
			startTime = 0, -- GetTime() value
			pausedDuration = 0, -- Accumulated paused seconds
			items = {}, -- [itemID] = { name, link, icon, quality, count, sellPrice }
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
	if self.UpdateDisplay then
		self:UpdateDisplay()
	end
end
