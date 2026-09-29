---@class LibsFarmAssistant
local LibsFarmAssistant = LibStub('AceAddon-3.0'):GetAddon('Libs-FarmAssistant')

-- First-run steps for the shared Libs-AddonTools setup window (LibAT.Setup).
-- Without LibAT.Setup nothing is registered: every setting is in /farm options.

local SETUP_ID = 'libs-farmassistant'

local function Changed()
	LibsFarmAssistant:SendMessage('LIBSFA_SETTINGS_CHANGED')
	LibsFarmAssistant:UpdateDisplay()
end

---Current value of an extras toggle
---@param key string
---@return boolean
local function GetExtra(key)
	local db = LibsFarmAssistant.db
	if key == 'skipPoor' then
		return db.tracking.qualities[0] == false
	elseif key == 'tooltips' then
		return (db.tooltips.items and db.tooltips.units) and true or false
	elseif key == 'tracker' then
		return db.tracker.shown and true or false
	end
	return false
end

---Change an extras toggle
---@param key string
---@param value boolean
local function SetExtra(key, value)
	local db = LibsFarmAssistant.db
	value = value and true or false
	if key == 'skipPoor' then
		db.tracking.qualities[0] = not value
		Changed()
	elseif key == 'tooltips' then
		db.tooltips.items = value
		db.tooltips.units = value
	elseif key == 'tracker' then
		local tracker = LibsFarmAssistant.Tracker
		if tracker then
			if value then
				tracker:Show()
			else
				tracker:Hide()
			end
		else
			db.tracker.shown = value
		end
	end
end

---Register with the setup window. Called from OnInitialize, before the Database module creates the
---saved settings, so a new install can still be told apart from an existing one.
function LibsFarmAssistant:RegisterSetup()
	if self.setupRegistration or not LibAT or not LibAT.Setup or type(LibAT.Setup.Register) ~= 'function' then
		return
	end
	local reg = LibAT.Setup:Register(SETUP_ID, {
		name = self.addonName,
		icon = self.icon,
		summary = 'Counts your loot, gold, kills and reputation while you farm.',
		priority = 60,
		isExistingUser = function()
			return type(LibsFarmAssistantDB) == 'table' and next(LibsFarmAssistantDB) ~= nil
		end,
		optionsCommand = '/farm options',
	})
	if not reg then
		return
	end
	self.setupRegistration = reg

	reg:AddStep({
		id = 'counting',
		kind = 'choice',
		name = 'What to count',
		title = 'Which items should it count?',
		text = 'Gold, kills and reputation are counted either way.',
		order = 10,
		choices = {
			{ value = 'all', title = 'Everything I loot', caption = 'Every item you pick up, and what it is worth.', recommended = true },
			{ value = 'selected', title = 'Only items I hunt', caption = 'Only the items you hunt or watch. Less to read.' },
		},
		get = function()
			return LibsFarmAssistant.db.tracking.mode == 'selected' and 'selected' or 'all'
		end,
		set = function(value)
			LibsFarmAssistant.db.tracking.mode = value == 'selected' and 'selected' or 'all'
			Changed()
		end,
	})

	reg:AddStep({
		id = 'extras',
		kind = 'toggles',
		name = 'Extras',
		title = 'A few extras',
		text = 'You can change these later with /farm options.',
		order = 20,
		items = {
			{ key = 'skipPoor', title = 'Skip gray items', caption = 'Gray junk items are not counted.', recommended = false },
			{ key = 'tooltips', title = 'Farming lines on tooltips', caption = 'Item and creature tooltips show what you farmed.', recommended = true },
			{ key = 'tracker', title = 'Small tracker window', caption = 'A small window with what you earned and your kills.', recommended = false },
		},
		get = function(key)
			return GetExtra(key)
		end,
		set = function(key, value)
			SetExtra(key, value)
		end,
	})
end
