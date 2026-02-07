---@class LibsFarmAssistant
local LibsFarmAssistant = LibStub('AceAddon-3.0'):GetAddon('Libs-FarmAssistant')

function LibsFarmAssistant:InitializeOptions()
	local options = {
		name = "Lib's Farm Assistant",
		type = 'group',
		args = {
			session = {
				name = 'Session',
				type = 'group',
				order = 1,
				inline = true,
				args = {
					toggle = {
						name = 'Toggle Pause',
						desc = 'Pause or resume the current tracking session',
						type = 'execute',
						order = 1,
						func = function()
							LibsFarmAssistant:ToggleSession()
						end,
					},
					reset = {
						name = 'Reset Session',
						desc = 'Clear all tracked data and start a new session',
						type = 'execute',
						order = 2,
						confirm = true,
						confirmText = 'Reset all session data?',
						func = function()
							LibsFarmAssistant:ResetSession()
						end,
					},
				},
			},
			tracking = {
				name = 'Tracking',
				type = 'group',
				order = 2,
				inline = true,
				args = {
					loot = {
						name = 'Track Loot',
						desc = 'Track items looted during the session',
						type = 'toggle',
						order = 1,
						get = function()
							return LibsFarmAssistant.db.tracking.loot
						end,
						set = function(_, val)
							LibsFarmAssistant.db.tracking.loot = val
						end,
					},
					money = {
						name = 'Track Money',
						desc = 'Track gold gained during the session',
						type = 'toggle',
						order = 2,
						get = function()
							return LibsFarmAssistant.db.tracking.money
						end,
						set = function(_, val)
							LibsFarmAssistant.db.tracking.money = val
						end,
					},
					currency = {
						name = 'Track Currency',
						desc = 'Track currencies gained during the session',
						type = 'toggle',
						order = 3,
						get = function()
							return LibsFarmAssistant.db.tracking.currency
						end,
						set = function(_, val)
							LibsFarmAssistant.db.tracking.currency = val
						end,
					},
					reputation = {
						name = 'Track Reputation',
						desc = 'Track reputation gains during the session',
						type = 'toggle',
						order = 4,
						get = function()
							return LibsFarmAssistant.db.tracking.reputation
						end,
						set = function(_, val)
							LibsFarmAssistant.db.tracking.reputation = val
						end,
					},
					qualityFilter = {
						name = 'Minimum Item Quality',
						desc = 'Minimum quality of items to track',
						type = 'select',
						order = 5,
						values = {
							[0] = '|cff9d9d9dPoor|r',
							[1] = '|cffffffffCommon|r',
							[2] = '|cff1eff00Uncommon|r',
							[3] = '|cff0070ddRare|r',
							[4] = '|cffa335eeEpic|r',
						},
						get = function()
							return LibsFarmAssistant.db.qualityFilter
						end,
						set = function(_, val)
							LibsFarmAssistant.db.qualityFilter = val
						end,
					},
				},
			},
			display = {
				name = 'Display',
				type = 'group',
				order = 3,
				inline = true,
				args = {
					format = {
						name = 'Broker Text',
						desc = 'What to show on the data broker text',
						type = 'select',
						order = 1,
						values = {
							items = 'Item Count',
							money = 'Money Gained',
							combined = 'Items + Money',
						},
						get = function()
							return LibsFarmAssistant.db.display.format
						end,
						set = function(_, val)
							LibsFarmAssistant.db.display.format = val
							LibsFarmAssistant:UpdateDisplay()
						end,
					},
				},
			},
		},
	}

	LibStub('AceConfig-3.0'):RegisterOptionsTable('LibsFarmAssistant', options)
	LibStub('AceConfigDialog-3.0'):AddToBlizOptions('LibsFarmAssistant', "Lib's Farm Assistant")
end

function LibsFarmAssistant:OpenOptions()
	LibStub('AceConfigDialog-3.0'):Open('LibsFarmAssistant')
end
