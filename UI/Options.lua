---@class LibsFarmAssistant
local LibsFarmAssistant = LibStub('AceAddon-3.0'):GetAddon('Libs-FarmAssistant')

-- Temporary state for new goal inputs
local newGoal = {
	type = 'item',
	targetValue = 100,
	targetItemID = '',
	targetName = '',
}

---Build dynamic options for existing goals
---@return table args AceConfig args table
local function BuildGoalListArgs()
	local args = {}
	local goals = LibsFarmAssistant.db.goals
	if not goals then
		return args
	end

	for i, goal in ipairs(goals) do
		local goalKey = 'goal' .. i

		-- Goal name/description
		local goalName
		if goal.type == 'item' then
			goalName = string.format('#%d: Item %s (target: %s)', i, goal.targetName or tostring(goal.targetItemID), BreakUpLargeNumbers(goal.targetValue))
		elseif goal.type == 'money' then
			goalName = string.format('#%d: Gold (target: %sg)', i, BreakUpLargeNumbers(math.floor(goal.targetValue / 10000)))
		else
			goalName = string.format('#%d: %s %s (target: %s)', i, goal.type:sub(1, 1):upper() .. goal.type:sub(2), goal.targetName or '', BreakUpLargeNumbers(goal.targetValue))
		end

		args[goalKey .. 'toggle'] = {
			name = goalName,
			desc = goal.active and 'Currently active - click to disable' or 'Currently disabled - click to enable',
			type = 'toggle',
			order = i * 10,
			width = 'double',
			get = function()
				return goal.active
			end,
			set = function(_, val)
				goal.active = val
			end,
		}

		args[goalKey .. 'remove'] = {
			name = 'Remove',
			type = 'execute',
			order = i * 10 + 1,
			width = 'half',
			confirm = true,
			confirmText = 'Remove this goal?',
			func = function()
				table.remove(goals, i)
				LibsFarmAssistant:RefreshGoalOptions()
				LibStub('AceConfigRegistry-3.0'):NotifyChange('LibsFarmAssistant')
			end,
		}
	end

	return args
end

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
					honor = {
						name = 'Track Honor',
						desc = 'Track honor gained during the session (PvP)',
						type = 'toggle',
						order = 5,
						get = function()
							return LibsFarmAssistant.db.tracking.honor
						end,
						set = function(_, val)
							LibsFarmAssistant.db.tracking.honor = val
						end,
					},
					itemValue = {
						name = 'Estimate Vendor Value',
						desc = 'Show estimated vendor sell value for looted items',
						type = 'toggle',
						order = 6,
						get = function()
							return LibsFarmAssistant.db.tracking.itemValue
						end,
						set = function(_, val)
							LibsFarmAssistant.db.tracking.itemValue = val
							LibsFarmAssistant:UpdateDisplay()
						end,
					},
					qualityFilter = {
						name = 'Minimum Item Quality',
						desc = 'Minimum quality of items to track',
						type = 'select',
						order = 10,
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
			watchedItems = {
				name = 'Watched Items',
				type = 'group',
				order = 3,
				inline = true,
				args = {
					desc = {
						name = 'Drag items from your bags onto the minimap button to watch them. Watched items appear in the tooltip even before they drop.',
						type = 'description',
						order = 0,
					},
					list = {
						name = '',
						type = 'multiselect',
						order = 1,
						width = 'full',
						values = function()
							local values = {}
							local watched = LibsFarmAssistant:GetWatchedItems()
							for key, info in pairs(watched) do
								values[key] = (info.link or info.name or key)
							end
							return values
						end,
						get = function(_, key)
							return LibsFarmAssistant._watchedSelection and LibsFarmAssistant._watchedSelection[key]
						end,
						set = function(_, key, val)
							if not LibsFarmAssistant._watchedSelection then
								LibsFarmAssistant._watchedSelection = {}
							end
							LibsFarmAssistant._watchedSelection[key] = val or nil
						end,
					},
					removeSelected = {
						name = 'Remove Selected',
						desc = 'Stop watching the selected items',
						type = 'execute',
						order = 2,
						func = function()
							if not LibsFarmAssistant._watchedSelection then
								return
							end
							for key in pairs(LibsFarmAssistant._watchedSelection) do
								LibsFarmAssistant:UnwatchItem(key)
							end
							LibsFarmAssistant._watchedSelection = nil
							LibStub('AceConfigRegistry-3.0'):NotifyChange('LibsFarmAssistant')
						end,
					},
				},
			},
			notifications = {
				name = 'Session Notifications',
				type = 'group',
				order = 4,
				inline = true,
				args = {
					enabled = {
						name = 'Enable Notifications',
						desc = 'Show periodic reminders in chat during farming sessions',
						type = 'toggle',
						order = 1,
						get = function()
							return LibsFarmAssistant.db.sessionNotifications.enabled
						end,
						set = function(_, val)
							LibsFarmAssistant.db.sessionNotifications.enabled = val
						end,
					},
					frequency = {
						name = 'Reminder Frequency (minutes)',
						desc = 'How often to show session reminders',
						type = 'range',
						order = 2,
						min = 5,
						max = 120,
						step = 5,
						get = function()
							return LibsFarmAssistant.db.sessionNotifications.frequencyMinutes
						end,
						set = function(_, val)
							LibsFarmAssistant.db.sessionNotifications.frequencyMinutes = val
						end,
					},
				},
			},
			display = {
				name = 'Display',
				type = 'group',
				order = 5,
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
			goals = {
				name = 'Goals',
				type = 'group',
				order = 6,
				inline = true,
				args = {
					desc = {
						name = 'Set farming goals to track progress in the tooltip. Item goals require an Item ID.',
						type = 'description',
						order = 1,
					},
					goalSound = {
						name = 'Play Sound on Completion',
						desc = 'Play a sound when a goal is completed',
						type = 'toggle',
						order = 2,
						get = function()
							return LibsFarmAssistant.db.goalSound
						end,
						set = function(_, val)
							LibsFarmAssistant.db.goalSound = val
						end,
					},
					addHeader = {
						name = 'Add New Goal',
						type = 'header',
						order = 10,
					},
					goalType = {
						name = 'Goal Type',
						type = 'select',
						order = 11,
						values = {
							item = 'Item',
							money = 'Money (Gold)',
							honor = 'Honor',
							currency = 'Currency',
							reputation = 'Reputation',
						},
						get = function()
							return newGoal.type
						end,
						set = function(_, val)
							newGoal.type = val
						end,
					},
					targetValue = {
						name = 'Target Amount',
						desc = 'For money goals, enter the amount in gold',
						type = 'input',
						order = 12,
						get = function()
							return tostring(newGoal.targetValue)
						end,
						set = function(_, val)
							newGoal.targetValue = tonumber(val) or 100
						end,
					},
					targetItemID = {
						name = 'Item ID',
						desc = 'The numeric Item ID (e.g., 2589 for Linen Cloth)',
						type = 'input',
						order = 13,
						hidden = function()
							return newGoal.type ~= 'item'
						end,
						get = function()
							return newGoal.targetItemID
						end,
						set = function(_, val)
							newGoal.targetItemID = val
						end,
					},
					targetName = {
						name = 'Name',
						desc = 'Currency or faction name (must match exactly)',
						type = 'input',
						order = 14,
						hidden = function()
							return newGoal.type ~= 'currency' and newGoal.type ~= 'reputation'
						end,
						get = function()
							return newGoal.targetName
						end,
						set = function(_, val)
							newGoal.targetName = val
						end,
					},
					addGoal = {
						name = 'Add Goal',
						type = 'execute',
						order = 15,
						func = function()
							local goal = {
								type = newGoal.type,
								targetValue = newGoal.targetValue,
								active = true,
							}

							if newGoal.type == 'money' then
								-- Convert gold input to copper
								goal.targetValue = newGoal.targetValue * 10000
							elseif newGoal.type == 'item' then
								local itemID = tonumber(newGoal.targetItemID)
								if not itemID then
									LibsFarmAssistant:Print('Invalid Item ID')
									return
								end
								goal.targetItemID = itemID
								-- Try to resolve name
								local itemName = C_Item.GetItemInfo(itemID)
								goal.targetName = itemName or ('Item ' .. itemID)
								if not itemName then
									C_Item.RequestLoadItemDataByID(itemID)
								end
							elseif newGoal.type == 'currency' or newGoal.type == 'reputation' then
								if newGoal.targetName == '' then
									LibsFarmAssistant:Print('Please enter a name')
									return
								end
								goal.targetName = newGoal.targetName
							end

							table.insert(LibsFarmAssistant.db.goals, goal)
							LibsFarmAssistant:Print(string.format('Goal added: %s', goal.targetName or goal.type))
							LibsFarmAssistant:RefreshGoalOptions()
							LibStub('AceConfigRegistry-3.0'):NotifyChange('LibsFarmAssistant')
						end,
					},
					currentHeader = {
						name = 'Current Goals',
						type = 'header',
						order = 20,
					},
				},
			},
		},
	}

	-- Store reference for dynamic goal list injection
	self.optionsTable = options
	self:RefreshGoalOptions()

	LibStub('AceConfig-3.0'):RegisterOptionsTable('LibsFarmAssistant', options)
	LibStub('AceConfigDialog-3.0'):AddToBlizOptions('LibsFarmAssistant', "Lib's Farm Assistant")
end

---Rebuild the dynamic goal list entries in the options table
function LibsFarmAssistant:RefreshGoalOptions()
	if not self.optionsTable then
		return
	end

	local goalsArgs = self.optionsTable.args.goals.args

	-- Remove old dynamic entries
	for key in pairs(goalsArgs) do
		if key:match('^goal%d') then
			goalsArgs[key] = nil
		end
	end

	-- Add current goals
	local dynamicArgs = BuildGoalListArgs()
	for key, val in pairs(dynamicArgs) do
		-- Offset orders by 100 to be after the static entries
		val.order = val.order + 100
		goalsArgs[key] = val
	end
end

function LibsFarmAssistant:OpenOptions()
	self:RefreshGoalOptions()
	LibStub('AceConfigDialog-3.0'):Open('LibsFarmAssistant')
end
