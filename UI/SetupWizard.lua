---@class LibsFarmAssistant
local LibsFarmAssistant = LibStub('AceAddon-3.0'):GetAddon('Libs-FarmAssistant')

-- A first-run page for the Libs-AddonTools setup wizard, when that addon is installed.

function LibsFarmAssistant:RegisterSetupWizard()
	if not LibAT or not LibAT.SetupWizard or not LibAT.UI or not LibAT.UI.BuildWidgets then
		return
	end

	local db = setmetatable({}, {
		__index = function(_, key)
			return LibsFarmAssistant.db[key]
		end,
	})

	LibAT.SetupWizard:RegisterAddon('libs-farmassistant', {
		name = self.addonName,
		icon = self.icon,
		pages = {
			{
				id = 'tracking',
				name = 'Farm Assistant',
				builder = function(contentFrame)
					local _, totalHeight = LibAT.UI.BuildWidgets(contentFrame, {
						desc = {
							type = 'description',
							name = 'Farm Assistant counts everything you farm: loot and its value, gold, kills, reputation, currency, experience and honor, per hour and by day, week and month. Every drop is tied to the mob or node it came from.',
							order = 1,
						},
						header = {
							type = 'header',
							name = 'What to count',
							order = 10,
						},
						everything = {
							type = 'checkbox',
							name = 'Count every item I loot',
							desc = 'Off counts only the items you hunt or watch.',
							order = 11,
							get = function()
								return db.tracking.mode ~= 'selected'
							end,
							set = function(_, val)
								db.tracking.mode = val and 'all' or 'selected'
							end,
						},
						skipPoor = {
							type = 'checkbox',
							name = 'Skip gray items',
							order = 12,
							get = function()
								return db.tracking.qualities[0] == false
							end,
							set = function(_, val)
								db.tracking.qualities[0] = not val
							end,
						},
						tooltips = {
							type = 'checkbox',
							name = 'Add farming lines to item and creature tooltips',
							order = 13,
							get = function()
								return db.tooltips.items and db.tooltips.units
							end,
							set = function(_, val)
								db.tooltips.items = val
								db.tooltips.units = val
							end,
						},
						tracker = {
							type = 'checkbox',
							name = 'Show the compact tracker',
							order = 14,
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
					}, contentFrame:GetWidth())

					contentFrame.totalHeight = totalHeight
				end,
			},
		},
	})
end
