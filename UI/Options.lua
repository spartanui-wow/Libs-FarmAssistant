---@class LibsFarmAssistant
local LibsFarmAssistant = LibStub('AceAddon-3.0'):GetAddon('Libs-FarmAssistant')

---@class LibsFarmAssistant.Options : AceModule, AceEvent-3.0, AceTimer-3.0
local Options = LibsFarmAssistant:NewModule('Options')
LibsFarmAssistant.Options = Options

local Compat = LibsFarmAssistant.Compat

-- Temporary state for new list item inputs
local newListItem = {
	itemID = '',
}

-- Temporary state for new goal inputs
local newGoal = {
	type = 'item',
	targetValue = 100,
	targetItemID = '',
	targetName = '',
}

local GOAL_TYPES = {
	item = 'Item',
	value = 'Total value (gold)',
	money = 'Gold looted and earned',
	kills = 'Kills',
	xp = 'Experience',
	honor = 'Honor',
	currency = 'Currency',
	reputation = 'Reputation',
}

local function Notify()
	LibStub('AceConfigRegistry-3.0'):NotifyChange('LibsFarmAssistant')
end

local function Changed()
	LibsFarmAssistant:SendMessage('LIBSFA_SETTINGS_CHANGED')
	LibsFarmAssistant:UpdateDisplay()
end

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
		local target = LibsFarmAssistant.GoalTracker:FormatValue(goal, goal.targetValue or 0)
		local goalName = string.format('%s: %s', LibsFarmAssistant.GoalTracker:Name(goal), target)

		args[goalKey .. 'toggle'] = {
			name = goalName,
			desc = goal.active and 'On. Click to turn this goal off.' or 'Off. Click to turn this goal on.',
			type = 'toggle',
			order = i * 10,
			width = 'double',
			get = function()
				return goal.active
			end,
			set = function(_, val)
				goal.active = val
				LibsFarmAssistant:UpdateDisplay()
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
				Options:RefreshGoalOptions()
				Notify()
			end,
		}
	end

	return args
end

local QUALITY_VALUES = {}
for q = 0, 7 do
	QUALITY_VALUES[q] = _G['ITEM_QUALITY' .. q .. '_DESC'] or tostring(q)
end

-- Reads and writes always go to the active profile, even after a profile switch.
local db = setmetatable({}, {
	__index = function(_, key)
		return LibsFarmAssistant.db[key]
	end,
	__newindex = function(_, key, value)
		LibsFarmAssistant.db[key] = value
	end,
})

function Options:OnEnable()
	local options = {
		name = "Lib's Farm Assistant",
		type = 'group',
		childGroups = 'tab',
		args = {
			general = {
				name = 'General',
				type = 'group',
				order = 1,
				args = {
					open = {
						name = 'Open the window',
						type = 'execute',
						order = 1,
						func = function()
							LibsFarmAssistant:ToggleWindow()
						end,
					},
					toggle = {
						name = 'Pause or resume',
						desc = 'Stop the clock and stop counting, or start again.',
						type = 'execute',
						order = 2,
						func = function()
							LibsFarmAssistant:ToggleSession()
						end,
					},
					reset = {
						name = 'New session',
						desc = 'Save this session to your history and start counting again.',
						type = 'execute',
						order = 3,
						confirm = true,
						confirmText = 'Start a new session? This one is saved to your history.',
						func = function()
							LibsFarmAssistant:ResetSession()
						end,
					},
					sessionHeader = { name = 'Sessions', type = 'header', order = 10 },
					startMode = {
						name = 'Start tracking',
						desc = 'What happens when you log in. Takes effect the next time you log in.',
						type = 'select',
						order = 11,
						width = 'double',
						values = LibsFarmAssistant.SessionManager.START_MODES,
						sorting = LibsFarmAssistant.SessionManager.START_MODE_ORDER,
						get = function()
							return db.session.startMode
						end,
						set = function(_, val)
							db.session.startMode = val
							Changed()
						end,
					},
					newAfter = {
						name = 'New session after a break of',
						desc = 'When you log back in after this many minutes, a fresh session starts and the old one goes to your history. 0 keeps one session until you start a new one yourself.',
						type = 'range',
						order = 12,
						min = 0,
						max = 240,
						step = 5,
						width = 'double',
						get = function()
							return db.session.newAfterMinutes
						end,
						set = function(_, val)
							db.session.newAfterMinutes = val
						end,
					},
					pauseWhenAFK = {
						name = 'Pause while away',
						desc = 'Stop the clock while you are flagged away from keyboard, so breaks do not lower your per hour rates. It resumes when you are back.',
						type = 'toggle',
						order = 13,
						width = 'full',
						get = function()
							return db.session.pauseWhenAFK
						end,
						set = function(_, val)
							db.session.pauseWhenAFK = val
							LibsFarmAssistant.SessionManager:UpdateAutoPause()
							Changed()
						end,
					},
					pauseWhenResting = {
						name = 'Pause while resting',
						desc = 'Stop the clock in cities and inns, so shopping and chatting do not lower your per hour rates. It resumes when you leave.',
						type = 'toggle',
						order = 14,
						width = 'full',
						get = function()
							return db.session.pauseWhenResting
						end,
						set = function(_, val)
							db.session.pauseWhenResting = val
							LibsFarmAssistant.SessionManager:UpdateAutoPause()
							Changed()
						end,
					},
					smartHeader = { name = 'Notice when you start farming', type = 'header', order = 20 },
					smartEnabled = {
						name = 'Offer to resume when you loot while paused',
						desc = 'If you loot several times in a short time while tracking is paused, the addon asks whether to resume.',
						type = 'toggle',
						order = 21,
						width = 'full',
						get = function()
							return db.smartSession.enabled
						end,
						set = function(_, val)
							db.smartSession.enabled = val
						end,
					},
					smartAuto = {
						name = 'Resume without asking',
						type = 'toggle',
						order = 22,
						disabled = function()
							return not db.smartSession.enabled
						end,
						get = function()
							return db.smartSession.autoStart
						end,
						set = function(_, val)
							db.smartSession.autoStart = val
						end,
					},
					smartThreshold = {
						name = 'Loots needed',
						type = 'range',
						order = 23,
						min = 2,
						max = 10,
						step = 1,
						disabled = function()
							return not db.smartSession.enabled
						end,
						get = function()
							return db.smartSession.lootThreshold
						end,
						set = function(_, val)
							db.smartSession.lootThreshold = val
						end,
					},
					smartWindow = {
						name = 'Within seconds',
						type = 'range',
						order = 24,
						min = 10,
						max = 120,
						step = 5,
						disabled = function()
							return not db.smartSession.enabled
						end,
						get = function()
							return db.smartSession.timeWindowSeconds
						end,
						set = function(_, val)
							db.smartSession.timeWindowSeconds = val
						end,
					},
					notifyHeader = { name = 'Reminders', type = 'header', order = 30 },
					notifyEnabled = {
						name = 'Post a session summary in chat every',
						type = 'toggle',
						order = 31,
						width = 'double',
						get = function()
							return db.sessionNotifications.enabled
						end,
						set = function(_, val)
							db.sessionNotifications.enabled = val
						end,
					},
					notifyFrequency = {
						name = 'Minutes',
						type = 'range',
						order = 32,
						min = 5,
						max = 120,
						step = 5,
						disabled = function()
							return not db.sessionNotifications.enabled
						end,
						get = function()
							return db.sessionNotifications.frequencyMinutes
						end,
						set = function(_, val)
							db.sessionNotifications.frequencyMinutes = val
						end,
					},
					chatEcho = {
						name = 'Print every gain in chat',
						desc = 'A chat line for each item and each bit of coin you loot.',
						type = 'toggle',
						order = 33,
						width = 'full',
						get = function()
							return db.chatEcho
						end,
						set = function(_, val)
							db.chatEcho = val
						end,
					},
				},
			},
			tracking = {
				name = 'Tracking',
				type = 'group',
				order = 2,
				args = {
					mode = {
						name = 'Which items to count',
						type = 'select',
						order = 1,
						width = 'double',
						values = {
							all = 'Everything, in the qualities below',
							selected = 'Only items I hunt or watch',
						},
						get = function()
							return db.tracking.mode
						end,
						set = function(_, val)
							db.tracking.mode = val
							Changed()
						end,
					},
					qualities = {
						name = 'Qualities to count',
						desc = 'Items of an unticked quality are not counted. Items you hunt or watch always are.',
						type = 'multiselect',
						order = 2,
						values = QUALITY_VALUES,
						disabled = function()
							return db.tracking.mode == 'selected'
						end,
						get = function(_, q)
							return db.tracking.qualities[q] ~= false
						end,
						set = function(_, q, val)
							db.tracking.qualities[q] = val
							Changed()
						end,
					},
					whatHeader = { name = 'What to measure', type = 'header', order = 10 },
					loot = {
						name = 'Loot',
						type = 'toggle',
						order = 11,
						get = function()
							return db.tracking.loot
						end,
						set = function(_, val)
							db.tracking.loot = val
						end,
					},
					money = {
						name = 'Gold',
						type = 'toggle',
						order = 12,
						get = function()
							return db.tracking.money
						end,
						set = function(_, val)
							db.tracking.money = val
						end,
					},
					kills = {
						name = 'Kills',
						type = 'toggle',
						order = 13,
						get = function()
							return db.tracking.kills
						end,
						set = function(_, val)
							db.tracking.kills = val
						end,
					},
					currency = {
						name = 'Currency',
						type = 'toggle',
						order = 14,
						get = function()
							return db.tracking.currency
						end,
						set = function(_, val)
							db.tracking.currency = val
						end,
					},
					reputation = {
						name = 'Reputation',
						type = 'toggle',
						order = 15,
						get = function()
							return db.tracking.reputation
						end,
						set = function(_, val)
							db.tracking.reputation = val
						end,
					},
					experience = {
						name = 'Experience',
						type = 'toggle',
						order = 16,
						get = function()
							return db.tracking.experience
						end,
						set = function(_, val)
							db.tracking.experience = val
						end,
					},
					honor = {
						name = 'Honor',
						type = 'toggle',
						order = 17,
						get = function()
							return db.tracking.honor
						end,
						set = function(_, val)
							db.tracking.honor = val
						end,
					},
					extraHeader = { name = 'Items that are not loot', type = 'header', order = 20 },
					countQuestRewards = {
						name = 'Count quest rewards and items put in your bags',
						desc = 'Items given to you directly, such as quest rewards and containers that open into your bags.',
						type = 'toggle',
						order = 21,
						width = 'full',
						get = function()
							return db.tracking.countQuestRewards
						end,
						set = function(_, val)
							db.tracking.countQuestRewards = val
						end,
					},
					countCrafted = {
						name = 'Count items you craft',
						type = 'toggle',
						order = 22,
						width = 'full',
						get = function()
							return db.tracking.countCrafted
						end,
						set = function(_, val)
							db.tracking.countCrafted = val
						end,
					},
					priceHeader = { name = 'Item value', type = 'header', order = 30 },
					priceSource = {
						name = 'Value items at',
						desc = 'Auction prices need an auction pricing addon. Items that bind when picked up always use the vendor price.',
						type = 'select',
						order = 31,
						width = 'double',
						values = {
							best = 'Auction or vendor price, whichever is higher',
							auction = 'Auction price',
							vendor = 'Vendor price',
						},
						get = function()
							return db.pricing.source
						end,
						set = function(_, val)
							db.pricing.source = val
							Changed()
						end,
					},
					priceNote = {
						name = function()
							return LibsFarmAssistant.Pricing:HasAuctionSource() and 'Auction prices found.' or 'No auction prices found, so vendor prices are used.'
						end,
						type = 'description',
						order = 32,
					},
				},
			},
			autoLooting = {
				name = 'Auto-Loot',
				type = 'group',
				order = 5,
				childGroups = 'tab',
				args = {
					general = {
						name = 'General',
						type = 'group',
						order = 1,
						inline = true,
						args = {
							enabled = {
								name = 'Enable Auto-Looting',
								desc = 'Automatically loot items from corpses and containers based on your filter rules',
								type = 'toggle',
								order = 1,
								width = 'full',
								get = function()
									return LibsFarmAssistant.db.autoLoot.enabled
								end,
								set = function(_, val)
									LibsFarmAssistant.db.autoLoot.enabled = val
									LibsFarmAssistant:InvalidateLootingModuleCache()
									-- Re-register or unregister loot events on LootingCore module
									local lootingCore = LibsFarmAssistant.LootingCore
									if lootingCore then
										lootingCore:UnregisterEvent('LOOT_READY')
										lootingCore:UnregisterEvent('LOOT_OPENED')
										if val then
											local event = LibsFarmAssistant.db.autoLoot.fastLoot and 'LOOT_READY' or 'LOOT_OPENED'
											lootingCore:RegisterEvent(event, 'OnLootWindowReady')
										end
									end
								end,
							},
							fastLoot = {
								name = 'Fast Loot',
								desc = 'Loot items as fast as possible (uses LOOT_READY event). Disable if you experience issues with loot animations.',
								type = 'toggle',
								order = 2,
								disabled = function()
									return not LibsFarmAssistant.db.autoLoot.enabled
								end,
								get = function()
									return LibsFarmAssistant.db.autoLoot.fastLoot
								end,
								set = function(_, val)
									LibsFarmAssistant.db.autoLoot.fastLoot = val
									local lootingCore = LibsFarmAssistant.LootingCore
									if lootingCore and LibsFarmAssistant.db.autoLoot.enabled then
										lootingCore:UnregisterEvent('LOOT_READY')
										lootingCore:UnregisterEvent('LOOT_OPENED')
										local event = val and 'LOOT_READY' or 'LOOT_OPENED'
										lootingCore:RegisterEvent(event, 'OnLootWindowReady')
									end
								end,
							},
							closeLoot = {
								name = 'Close Loot Window',
								desc = 'Automatically close the loot window after all items are looted',
								type = 'toggle',
								order = 3,
								disabled = function()
									return not LibsFarmAssistant.db.autoLoot.enabled
								end,
								get = function()
									return LibsFarmAssistant.db.autoLoot.closeLoot
								end,
								set = function(_, val)
									LibsFarmAssistant.db.autoLoot.closeLoot = val
								end,
							},
							lootAll = {
								name = 'Loot Everything',
								desc = 'Override all filters and loot every item (useful for general farming)',
								type = 'toggle',
								order = 4,
								disabled = function()
									return not LibsFarmAssistant.db.autoLoot.enabled
								end,
								get = function()
									return LibsFarmAssistant.db.autoLoot.lootAll
								end,
								set = function(_, val)
									LibsFarmAssistant.db.autoLoot.lootAll = val
									LibsFarmAssistant:InvalidateLootingModuleCache()
								end,
							},
						},
					},
					filters = {
						name = 'Filters',
						type = 'group',
						order = 2,
						inline = true,
						args = {
							filterDesc = {
								name = 'Items are looted if they pass ANY enabled filter (quality, quest, price, etc.). Blacklisted items are never looted.',
								type = 'description',
								order = 0,
							},
							qualityFilter = {
								name = 'Quality Filter',
								desc = 'Select which item qualities to auto-loot',
								type = 'multiselect',
								order = 1,
								width = 'full',
								disabled = function()
									return not LibsFarmAssistant.db.autoLoot.enabled
								end,
								values = {
									[0] = '|cff9d9d9dPoor|r',
									[1] = '|cffffffffCommon|r',
									[2] = '|cff1eff00Uncommon|r',
									[3] = '|cff0070ddRare|r',
									[4] = '|cffa335eeEpic|r',
									[5] = '|cffff8000Legendary|r',
								},
								get = function(_, key)
									return LibsFarmAssistant.db.lootModules.rarityTable[key]
								end,
								set = function(_, key, val)
									LibsFarmAssistant.db.lootModules.rarityTable[key] = val
									LibsFarmAssistant:InvalidateLootingModuleCache()
								end,
							},
							lootQuest = {
								name = 'Loot Quest Items',
								desc = 'Always auto-loot items needed for active quests',
								type = 'toggle',
								order = 2,
								disabled = function()
									return not LibsFarmAssistant.db.autoLoot.enabled
								end,
								get = function()
									return LibsFarmAssistant.db.lootModules.lootQuest
								end,
								set = function(_, val)
									LibsFarmAssistant.db.lootModules.lootQuest = val
									LibsFarmAssistant:InvalidateLootingModuleCache()
								end,
							},
							lootTokens = {
								name = 'Loot Tokens',
								desc = 'Auto-loot items with no vendor value (tokens, emblems, etc.)',
								type = 'toggle',
								order = 3,
								disabled = function()
									return not LibsFarmAssistant.db.autoLoot.enabled
								end,
								get = function()
									return LibsFarmAssistant.db.lootModules.lootTokens
								end,
								set = function(_, val)
									LibsFarmAssistant.db.lootModules.lootTokens = val
									LibsFarmAssistant:InvalidateLootingModuleCache()
								end,
							},
							ignoreBOP = {
								name = 'Ignore Bind on Pickup',
								desc = 'Skip Bind on Pickup items (leave them on the corpse)',
								type = 'toggle',
								order = 4,
								disabled = function()
									return not LibsFarmAssistant.db.autoLoot.enabled
								end,
								get = function()
									return LibsFarmAssistant.db.lootModules.ignoreBOP
								end,
								set = function(_, val)
									LibsFarmAssistant.db.lootModules.ignoreBOP = val
									LibsFarmAssistant:InvalidateLootingModuleCache()
								end,
							},
							fishingMode = {
								name = 'Fishing Mode',
								desc = 'Automatically loot everything while fishing',
								type = 'toggle',
								order = 5,
								disabled = function()
									return not LibsFarmAssistant.db.autoLoot.enabled
								end,
								get = function()
									return LibsFarmAssistant.db.lootModules.fishingMode
								end,
								set = function(_, val)
									LibsFarmAssistant.db.lootModules.fishingMode = val
									LibsFarmAssistant:InvalidateLootingModuleCache()
								end,
							},
							minPrice = {
								name = 'Minimum Vendor Price',
								desc = 'Loot items worth at least this much (in gold). Set to 0 to disable.',
								type = 'range',
								order = 6,
								min = 0,
								max = 100,
								step = 1,
								bigStep = 5,
								disabled = function()
									return not LibsFarmAssistant.db.autoLoot.enabled
								end,
								get = function()
									return (LibsFarmAssistant.db.lootModules.minPrice or 0) / 10000
								end,
								set = function(_, val)
									LibsFarmAssistant.db.lootModules.minPrice = val * 10000
									LibsFarmAssistant:InvalidateLootingModuleCache()
								end,
							},
						},
					},
					whitelist = {
						name = 'Whitelist',
						type = 'group',
						order = 3,
						args = {
							desc = {
								name = 'Items on the whitelist are always looted, regardless of quality or price filters. Shift+drag items onto the minimap button to add them.',
								type = 'description',
								order = 0,
							},
							list = {
								name = 'Current Whitelist',
								type = 'multiselect',
								order = 1,
								width = 'full',
								values = function()
									local values = {}
									for key, name in pairs(LibsFarmAssistant.db.lootModules.whitelist) do
										values[key] = name
									end
									return values
								end,
								get = function(_, key)
									return LibsFarmAssistant._whitelistSelection and LibsFarmAssistant._whitelistSelection[key]
								end,
								set = function(_, key, val)
									if not LibsFarmAssistant._whitelistSelection then
										LibsFarmAssistant._whitelistSelection = {}
									end
									LibsFarmAssistant._whitelistSelection[key] = val or nil
								end,
							},
							removeSelected = {
								name = 'Remove Selected',
								type = 'execute',
								order = 2,
								func = function()
									if not LibsFarmAssistant._whitelistSelection then
										return
									end
									for key in pairs(LibsFarmAssistant._whitelistSelection) do
										LibsFarmAssistant.db.lootModules.whitelist[key] = nil
									end
									LibsFarmAssistant._whitelistSelection = nil
									LibsFarmAssistant:InvalidateLootingModuleCache()
									LibStub('AceConfigRegistry-3.0'):NotifyChange('LibsFarmAssistant')
								end,
							},
							addHeader = {
								name = 'Add Item',
								type = 'header',
								order = 10,
							},
							addItemID = {
								name = 'Item ID',
								desc = 'Enter an Item ID to add to the whitelist',
								type = 'input',
								order = 11,
								get = function()
									return newListItem.itemID
								end,
								set = function(_, val)
									newListItem.itemID = val
								end,
							},
							addButton = {
								name = 'Add to Whitelist',
								type = 'execute',
								order = 12,
								func = function()
									local itemID = tonumber(newListItem.itemID)
									if not itemID then
										LibsFarmAssistant:Print('Invalid Item ID')
										return
									end
									local itemName = LibsFarmAssistant.Compat.ItemInfo(itemID)
									LibsFarmAssistant.db.lootModules.whitelist[tostring(itemID)] = itemName or ('Item ' .. itemID)
									if not itemName then
										LibsFarmAssistant.Compat.RequestItem(itemID)
									end
									newListItem.itemID = ''
									LibsFarmAssistant:InvalidateLootingModuleCache()
									LibStub('AceConfigRegistry-3.0'):NotifyChange('LibsFarmAssistant')
								end,
							},
						},
					},
					blacklist = {
						name = 'Blacklist',
						type = 'group',
						order = 4,
						args = {
							desc = {
								name = 'Items on the blacklist are never auto-looted, even if they match other filters. Ctrl+drag items onto the minimap button to add them.',
								type = 'description',
								order = 0,
							},
							list = {
								name = 'Current Blacklist',
								type = 'multiselect',
								order = 1,
								width = 'full',
								values = function()
									local values = {}
									for key, name in pairs(LibsFarmAssistant.db.lootModules.blacklist) do
										values[key] = name
									end
									return values
								end,
								get = function(_, key)
									return LibsFarmAssistant._blacklistSelection and LibsFarmAssistant._blacklistSelection[key]
								end,
								set = function(_, key, val)
									if not LibsFarmAssistant._blacklistSelection then
										LibsFarmAssistant._blacklistSelection = {}
									end
									LibsFarmAssistant._blacklistSelection[key] = val or nil
								end,
							},
							removeSelected = {
								name = 'Remove Selected',
								type = 'execute',
								order = 2,
								func = function()
									if not LibsFarmAssistant._blacklistSelection then
										return
									end
									for key in pairs(LibsFarmAssistant._blacklistSelection) do
										LibsFarmAssistant.db.lootModules.blacklist[key] = nil
									end
									LibsFarmAssistant._blacklistSelection = nil
									LibsFarmAssistant:InvalidateLootingModuleCache()
									LibStub('AceConfigRegistry-3.0'):NotifyChange('LibsFarmAssistant')
								end,
							},
							addHeader = {
								name = 'Add Item',
								type = 'header',
								order = 10,
							},
							addItemID = {
								name = 'Item ID',
								desc = 'Enter an Item ID to add to the blacklist',
								type = 'input',
								order = 11,
								get = function()
									return newListItem.itemID
								end,
								set = function(_, val)
									newListItem.itemID = val
								end,
							},
							addButton = {
								name = 'Add to Blacklist',
								type = 'execute',
								order = 12,
								func = function()
									local itemID = tonumber(newListItem.itemID)
									if not itemID then
										LibsFarmAssistant:Print('Invalid Item ID')
										return
									end
									local itemName = LibsFarmAssistant.Compat.ItemInfo(itemID)
									LibsFarmAssistant.db.lootModules.blacklist[tostring(itemID)] = itemName or ('Item ' .. itemID)
									if not itemName then
										LibsFarmAssistant.Compat.RequestItem(itemID)
									end
									newListItem.itemID = ''
									LibsFarmAssistant:InvalidateLootingModuleCache()
									LibStub('AceConfigRegistry-3.0'):NotifyChange('LibsFarmAssistant')
								end,
							},
						},
					},
					alertList = {
						name = 'Alert List',
						type = 'group',
						order = 5,
						args = {
							desc = {
								name = 'Items on the alert list trigger a sound and raid warning when they drop. Alt+drag items onto the minimap button to add them.',
								type = 'description',
								order = 0,
							},
							list = {
								name = 'Current Alert List',
								type = 'multiselect',
								order = 1,
								width = 'full',
								values = function()
									local values = {}
									for key, name in pairs(LibsFarmAssistant.db.lootModules.alertList) do
										values[key] = name
									end
									return values
								end,
								get = function(_, key)
									return LibsFarmAssistant._alertSelection and LibsFarmAssistant._alertSelection[key]
								end,
								set = function(_, key, val)
									if not LibsFarmAssistant._alertSelection then
										LibsFarmAssistant._alertSelection = {}
									end
									LibsFarmAssistant._alertSelection[key] = val or nil
								end,
							},
							removeSelected = {
								name = 'Remove Selected',
								type = 'execute',
								order = 2,
								func = function()
									if not LibsFarmAssistant._alertSelection then
										return
									end
									for key in pairs(LibsFarmAssistant._alertSelection) do
										LibsFarmAssistant.db.lootModules.alertList[key] = nil
									end
									LibsFarmAssistant._alertSelection = nil
									LibsFarmAssistant:InvalidateLootingModuleCache()
									LibStub('AceConfigRegistry-3.0'):NotifyChange('LibsFarmAssistant')
								end,
							},
							addHeader = {
								name = 'Add Item',
								type = 'header',
								order = 10,
							},
							addItemID = {
								name = 'Item ID',
								desc = 'Enter an Item ID to add to the alert list',
								type = 'input',
								order = 11,
								get = function()
									return newListItem.itemID
								end,
								set = function(_, val)
									newListItem.itemID = val
								end,
							},
							addButton = {
								name = 'Add to Alert List',
								type = 'execute',
								order = 12,
								func = function()
									local itemID = tonumber(newListItem.itemID)
									if not itemID then
										LibsFarmAssistant:Print('Invalid Item ID')
										return
									end
									local itemName = LibsFarmAssistant.Compat.ItemInfo(itemID)
									LibsFarmAssistant.db.lootModules.alertList[tostring(itemID)] = itemName or ('Item ' .. itemID)
									if not itemName then
										LibsFarmAssistant.Compat.RequestItem(itemID)
									end
									newListItem.itemID = ''
									LibsFarmAssistant:InvalidateLootingModuleCache()
									LibStub('AceConfigRegistry-3.0'):NotifyChange('LibsFarmAssistant')
								end,
							},
						},
					},
					chatOutput = {
						name = 'Chat Output',
						type = 'group',
						order = 6,
						inline = true,
						args = {
							printLooted = {
								name = 'Print Looted Items',
								desc = 'Show a chat message for each item auto-looted',
								type = 'toggle',
								order = 1,
								get = function()
									return LibsFarmAssistant.db.autoLoot.printLooted
								end,
								set = function(_, val)
									LibsFarmAssistant.db.autoLoot.printLooted = val
								end,
							},
							printIgnored = {
								name = 'Print Ignored Items',
								desc = 'Show a chat message for items that were skipped by filters',
								type = 'toggle',
								order = 2,
								get = function()
									return LibsFarmAssistant.db.autoLoot.printIgnored
								end,
								set = function(_, val)
									LibsFarmAssistant.db.autoLoot.printIgnored = val
								end,
							},
							printReason = {
								name = 'Show Reason',
								desc = 'Include the reason (Quality, Whitelist, etc.) in chat output',
								type = 'toggle',
								order = 3,
								get = function()
									return LibsFarmAssistant.db.autoLoot.printReason
								end,
								set = function(_, val)
									LibsFarmAssistant.db.autoLoot.printReason = val
								end,
							},
						},
					},
				},
			},
			hunts = {
				name = 'Hunts and Goals',
				type = 'group',
				order = 3,
				args = {
					huntDesc = {
						name = 'Hunts count your attempts at a rare drop. Add them in the window on the Hunts page, or type /farm hunt followed by an item link.',
						type = 'description',
						order = 1,
					},
					huntAnnounce = {
						name = 'Announce drops on screen and in chat',
						type = 'toggle',
						order = 2,
						width = 'full',
						get = function()
							return db.hunts.announce
						end,
						set = function(_, val)
							db.hunts.announce = val
						end,
					},
					huntSound = {
						name = 'Play a sound when a hunted item drops',
						type = 'toggle',
						order = 3,
						width = 'full',
						get = function()
							return db.hunts.sound
						end,
						set = function(_, val)
							db.hunts.sound = val
						end,
					},
					openHunts = {
						name = 'Open Hunts',
						type = 'execute',
						order = 4,
						func = function()
							LibsFarmAssistant.Window:Open('hunts')
						end,
					},
					goalsHeader = { name = 'Session goals', type = 'header', order = 10 },
					goalsDesc = {
						name = 'Goals measure this session: "200 Runecloth" or "500 gold". Progress shows in the tooltip with the time left at your pace.',
						type = 'description',
						order = 11,
					},
					goalSound = {
						name = 'Play a sound when a goal is reached',
						type = 'toggle',
						order = 12,
						width = 'full',
						get = function()
							return db.goalSound
						end,
						set = function(_, val)
							db.goalSound = val
						end,
					},
					goalType = {
						name = 'Goal',
						type = 'select',
						order = 13,
						values = GOAL_TYPES,
						get = function()
							return newGoal.type
						end,
						set = function(_, val)
							newGoal.type = val
						end,
					},
					targetValue = {
						name = 'Amount',
						desc = 'For gold goals, the amount in gold.',
						type = 'input',
						order = 14,
						get = function()
							return tostring(newGoal.targetValue)
						end,
						set = function(_, val)
							newGoal.targetValue = tonumber(val) or 100
						end,
					},
					targetItemID = {
						name = 'Item ID or link',
						type = 'input',
						order = 15,
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
						desc = 'The currency or faction name, exactly as the game shows it.',
						type = 'input',
						order = 16,
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
						name = 'Add goal',
						type = 'execute',
						order = 17,
						func = function()
							local goal = { type = newGoal.type, targetValue = newGoal.targetValue, active = true }
							if newGoal.type == 'money' or newGoal.type == 'value' then
								goal.targetValue = newGoal.targetValue * 10000
							elseif newGoal.type == 'item' then
								local itemID = Compat.ItemIDFromLink(newGoal.targetItemID) or tonumber(newGoal.targetItemID)
								if not itemID then
									LibsFarmAssistant:Print('Enter an item ID or Shift-click an item into the box.')
									return
								end
								goal.targetItemID = itemID
								goal.targetName = Compat.ItemInfo(itemID) or ('Item ' .. itemID)
								LibsFarmAssistant.Pricing:Remember(itemID)
							elseif newGoal.type == 'currency' or newGoal.type == 'reputation' then
								if newGoal.targetName == '' then
									LibsFarmAssistant:Print('Enter the currency or faction name.')
									return
								end
								goal.targetName = newGoal.targetName
							end
							table.insert(db.goals, goal)
							LibsFarmAssistant:Print('Goal added: ' .. LibsFarmAssistant.GoalTracker:Name(goal))
							Options:RefreshGoalOptions()
							Notify()
						end,
					},
					currentHeader = { name = 'Current goals', type = 'header', order = 20 },
				},
			},
			display = {
				name = 'Display',
				type = 'group',
				order = 4,
				args = {
					format = {
						name = 'Data broker text',
						desc = 'What the text on your data bar shows. You can also scroll over it to change this.',
						type = 'select',
						order = 1,
						width = 'double',
						values = {
							value = 'Value per hour',
							gold = 'Gold looted per hour',
							items = 'Items looted',
							kills = 'Kills',
							hunt = 'Attempts on your first hunt',
						},
						get = function()
							return db.display.format
						end,
						set = function(_, val)
							db.display.format = val
							Changed()
						end,
					},
					tooltipHeader = { name = 'Tooltips', type = 'header', order = 10 },
					tooltipItems = {
						name = 'Add farming lines to item tooltips',
						desc = 'How many you farmed and which source drops it most often.',
						type = 'toggle',
						order = 11,
						width = 'full',
						get = function()
							return db.tooltips.items
						end,
						set = function(_, val)
							db.tooltips.items = val
						end,
					},
					tooltipUnits = {
						name = 'Add farming lines to creature tooltips',
						desc = 'How many you killed and what they dropped for you.',
						type = 'toggle',
						order = 12,
						width = 'full',
						get = function()
							return db.tooltips.units
						end,
						set = function(_, val)
							db.tooltips.units = val
						end,
					},
					trackerHeader = { name = 'Compact tracker', type = 'header', order = 20 },
					trackerShown = {
						name = 'Show the compact tracker',
						type = 'toggle',
						order = 21,
						get = function()
							return db.tracker.shown
						end,
						set = function(_, val)
							if val then
								LibsFarmAssistant.Tracker:Show()
							else
								LibsFarmAssistant.Tracker:Hide()
							end
						end,
					},
					trackerLocked = {
						name = 'Lock its position',
						type = 'toggle',
						order = 22,
						get = function()
							return db.tracker.locked
						end,
						set = function(_, val)
							db.tracker.locked = val
						end,
					},
					trackerScale = {
						name = 'Tracker size',
						type = 'range',
						order = 23,
						min = 0.6,
						max = 1.6,
						step = 0.05,
						isPercent = true,
						get = function()
							return db.tracker.scale or 1
						end,
						set = function(_, val)
							db.tracker.scale = val
							Changed()
						end,
					},
					trackerLines = {
						name = 'Tracker lines',
						type = 'multiselect',
						order = 24,
						values = {
							value = 'Value per hour',
							gold = 'Gold looted',
							kills = 'Kills',
							xp = 'Time to level',
							hunts = 'Hunts',
							rep = 'Top standing',
						},
						get = function(_, key)
							return db.tracker.lines[key]
						end,
						set = function(_, key, val)
							db.tracker.lines[key] = val
							Changed()
						end,
					},
					windowHeader = { name = 'Window', type = 'header', order = 30 },
					windowScale = {
						name = 'Window size',
						type = 'range',
						order = 31,
						min = 0.6,
						max = 1.6,
						step = 0.05,
						isPercent = true,
						get = function()
							return db.window.scale or 1
						end,
						set = function(_, val)
							db.window.scale = val
							if LibsFarmAssistant.Window.frame then
								LibsFarmAssistant.Window.frame:SetScale(val)
							end
						end,
					},
					minimap = {
						name = 'Show the minimap button',
						type = 'toggle',
						order = 32,
						get = function()
							return not db.minimap.hide
						end,
						set = function(_, val)
							db.minimap.hide = not val
							local icon = LibStub('LibDBIcon-1.0', true)
							if icon then
								if val then
									icon:Show("Lib's FarmAssistant")
								else
									icon:Hide("Lib's FarmAssistant")
								end
							end
						end,
					},
				},
			},
			watchedItems = {
				name = 'Watched Items',
				type = 'group',
				order = 6,
				args = {
					desc = {
						name = 'Watched items are always counted and always auto-looted. Drag an item from your bags onto the minimap button to watch it.',
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
							for key, info in pairs(LibsFarmAssistant.char.watchedItems) do
								values[key] = (info.link or info.name or key)
							end
							return values
						end,
						get = function(_, key)
							return Options.watchedSelection and Options.watchedSelection[key]
						end,
						set = function(_, key, val)
							Options.watchedSelection = Options.watchedSelection or {}
							Options.watchedSelection[key] = val or nil
						end,
					},
					removeSelected = {
						name = 'Stop watching selected',
						type = 'execute',
						order = 2,
						func = function()
							for key in pairs(Options.watchedSelection or {}) do
								LibsFarmAssistant:UnwatchItem(key)
							end
							Options.watchedSelection = nil
							Notify()
						end,
					},
				},
			},
		},
	}

	self.optionsTable = options
	self:RefreshGoalOptions()

	LibStub('AceConfig-3.0'):RegisterOptionsTable('LibsFarmAssistant', options)
	LibStub('AceConfigDialog-3.0'):AddToBlizOptions('LibsFarmAssistant', "Lib's Farm Assistant")
end

---Rebuild the dynamic goal list entries in the options table
function Options:RefreshGoalOptions()
	if not self.optionsTable then
		return
	end

	local goalsArgs = self.optionsTable.args.hunts.args
	for key in pairs(goalsArgs) do
		if key:match('^goal%d') then
			goalsArgs[key] = nil
		end
	end

	for key, val in pairs(BuildGoalListArgs()) do
		val.order = val.order + 100
		goalsArgs[key] = val
	end
end

function Options:OpenOptions()
	self:RefreshGoalOptions()
	LibStub('AceConfigDialog-3.0'):Open('LibsFarmAssistant')
end

function LibsFarmAssistant:RefreshGoalOptions()
	if self.Options then
		self.Options:RefreshGoalOptions()
	end
end
