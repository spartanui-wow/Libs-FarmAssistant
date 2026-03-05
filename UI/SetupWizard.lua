local FarmAssistant = LibStub('AceAddon-3.0'):GetAddon('Libs-FarmAssistant')

function FarmAssistant:RegisterSetupWizard()
	if not LibAT or not LibAT.SetupWizard then
		return
	end

	local DB = FarmAssistant.db and FarmAssistant.db.profile

	LibAT.SetupWizard:RegisterAddon('libs-farmassistant', {
		name = "Lib's Farm Assistant",
		icon = 'Interface/Addons/Libs-FarmAssistant/Logo-Icon',
		pages = {
			{
				id = 'tracking',
				name = 'Tracking Setup',
				builder = function(contentFrame)
					local widgets, totalHeight = LibAT.UI.BuildWidgets(contentFrame, {
						desc = {
							type = 'description',
							name = "Lib's Farm Assistant tracks your loot, money, currency, reputation, and honor during farming sessions. Configure basic tracking options below.",
							order = 1,
						},
						header = {
							type = 'header',
							name = 'Loot Tracking',
							order = 10,
						},
						trackMoney = {
							type = 'checkbox',
							name = 'Track money gains',
							desc = 'Track gold earned during farming sessions',
							order = 11,
							get = function()
								return DB and DB.trackMoney ~= false
							end,
							set = function(val)
								if DB then
									DB.trackMoney = val
								end
							end,
						},
						trackCurrency = {
							type = 'checkbox',
							name = 'Track currency gains',
							desc = 'Track currencies earned during farming sessions',
							order = 12,
							get = function()
								return DB and DB.trackCurrency ~= false
							end,
							set = function(val)
								if DB then
									DB.trackCurrency = val
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
