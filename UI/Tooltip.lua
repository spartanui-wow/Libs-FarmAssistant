---@class LibsFarmAssistant
local LibsFarmAssistant = LibStub('AceAddon-3.0'):GetAddon('Libs-FarmAssistant')

-- Quality colors
local QUALITY_COLORS = {
	[0] = { r = 0.62, g = 0.62, b = 0.62 }, -- Poor
	[1] = { r = 1, g = 1, b = 1 }, -- Common
	[2] = { r = 0.12, g = 1, b = 0 }, -- Uncommon
	[3] = { r = 0, g = 0.44, b = 0.87 }, -- Rare
	[4] = { r = 0.64, g = 0.21, b = 0.93 }, -- Epic
	[5] = { r = 1, g = 0.50, b = 0 }, -- Legendary
}

function LibsFarmAssistant:BuildTooltip(tooltip)
	local session = self.session
	local hours = self:GetSessionHours()
	local duration = self:GetSessionDuration()

	-- Title
	tooltip:SetText("Lib's Farm Assistant")

	-- Session status
	local status = self:IsSessionActive() and '|cff00ff00Active|r' or '|cffff0000Paused|r'
	tooltip:AddDoubleLine('Session: ' .. status, self:FormatDuration(duration), 1, 1, 1, 0.7, 0.7, 0.7)

	-- Items section
	local uniqueItems, totalItems = self:GetItemCounts()
	if totalItems > 0 then
		tooltip:AddLine(' ')
		local itemRate = hours > 0 and string.format(' (%.0f/hr)', totalItems / hours) or ''
		tooltip:AddLine(string.format('Items: %d looted%s', totalItems, itemRate), 1, 0.82, 0)

		-- Sort items by count descending
		local sorted = {}
		for _, item in pairs(session.items) do
			table.insert(sorted, item)
		end
		table.sort(sorted, function(a, b)
			return a.count > b.count
		end)

		for _, item in ipairs(sorted) do
			local rate = hours > 0 and string.format(' (%.1f/hr)', item.count / hours) or ''
			local color = QUALITY_COLORS[item.quality] or QUALITY_COLORS[1]
			tooltip:AddDoubleLine(
				string.format('  %s x%d', item.link or item.name, item.count),
				rate,
				color.r, color.g, color.b,
				0.6, 0.6, 0.6
			)
		end
	end

	-- Money section
	if session.money > 0 then
		tooltip:AddLine(' ')
		local moneyRate = hours > 0 and string.format(' (%s/hr)', self:FormatMoney(session.money / hours)) or ''
		tooltip:AddLine('Money: ' .. self:FormatMoney(session.money) .. moneyRate, 1, 0.82, 0)
	end

	-- Currency section
	local hasCurrency = false
	for _ in pairs(session.currencies) do
		hasCurrency = true
		break
	end
	if hasCurrency then
		tooltip:AddLine(' ')
		tooltip:AddLine('Currency:', 1, 0.82, 0)
		for name, data in pairs(session.currencies) do
			local rate = hours > 0 and string.format(' (%.1f/hr)', data.count / hours) or ''
			tooltip:AddDoubleLine(
				string.format('  %s x%d', name, data.count),
				rate,
				0.8, 0.8, 0.8,
				0.6, 0.6, 0.6
			)
		end
	end

	-- Reputation section
	local hasRep = false
	for _ in pairs(session.reputation) do
		hasRep = true
		break
	end
	if hasRep then
		tooltip:AddLine(' ')
		tooltip:AddLine('Reputation:', 1, 0.82, 0)
		for faction, gained in pairs(session.reputation) do
			local rate = hours > 0 and string.format(' (%.0f/hr)', gained / hours) or ''
			tooltip:AddDoubleLine(
				string.format('  %s +%d', faction, gained),
				rate,
				0.5, 1, 0.5,
				0.6, 0.6, 0.6
			)
		end
	end

	-- Click hints
	tooltip:AddLine(' ')
	tooltip:AddLine('|cffffff00Left Click:|r Toggle Pause | |cffffff00Middle:|r Reset')
	tooltip:AddLine('|cffffff00Shift+Left:|r Options | |cffffff00Right:|r Options')

	tooltip:Show()
end
