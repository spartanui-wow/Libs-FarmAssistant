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

---Get a colored trend arrow comparing current rate to historical average
---@param currentRate number
---@param historicalAvg number
---@return string arrow Colored UTF-8 arrow or empty string
local function GetTrendArrow(currentRate, historicalAvg)
	if historicalAvg <= 0 then
		return ''
	end
	if currentRate > historicalAvg * 1.05 then
		return ' |cff00ff00\226\150\178|r' -- green ▲
	elseif currentRate < historicalAvg * 0.95 then
		return ' |cffff0000\226\150\188|r' -- red ▼
	end
	return ''
end

function LibsFarmAssistant:BuildTooltip(tooltip)
	local session = self.session
	local hours = self:GetSessionHours()
	local duration = self:GetSessionDuration()
	local averages = self:GetHistoryAverages()

	-- Title
	tooltip:SetText("Lib's Farm Assistant")

	-- Session status
	local status = self:IsSessionActive() and '|cff00ff00Active|r' or '|cffff0000Paused|r'
	tooltip:AddDoubleLine('Session: ' .. status, self:FormatDuration(duration), 1, 1, 1, 0.7, 0.7, 0.7)

	-- Personal best indicator
	if hours > 0 then
		local bests = self.dbobj.char.bestRates
		local _, totalItems = self:GetItemCounts()
		local currentItemRate = totalItems / hours
		local currentGoldRate = self.session.money / hours
		local honor = self.session.honor or 0
		local currentHonorRate = honor / hours
		local bestParts = {}
		if bests.itemsPerHour > 0 and currentItemRate > bests.itemsPerHour then
			table.insert(bestParts, 'Items')
		end
		if bests.goldPerHour > 0 and currentGoldRate > bests.goldPerHour then
			table.insert(bestParts, 'Gold/hr')
		end
		if bests.honorPerHour > 0 and currentHonorRate > bests.honorPerHour then
			table.insert(bestParts, 'Honor/hr')
		end
		if #bestParts > 0 then
			tooltip:AddLine('* Personal Best: ' .. table.concat(bestParts, ', ') .. '!', 0, 1, 0)
		end
	end

	-- Items section
	local uniqueItems, totalItems = self:GetItemCounts()
	if totalItems > 0 then
		tooltip:AddLine(' ')
		local itemsPerHour = hours > 0 and (totalItems / hours) or 0
		local itemRate = hours > 0 and string.format(' (%.0f/hr)', itemsPerHour) or ''
		local itemArrow = GetTrendArrow(itemsPerHour, averages.itemsPerHour)
		tooltip:AddLine(string.format('Items: %s looted%s%s', self:FormatNumber(totalItems), itemRate, itemArrow), 1, 0.82, 0)

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
			tooltip:AddDoubleLine(string.format('  %s x%s', item.link or item.name, self:FormatNumber(item.count)), rate, color.r, color.g, color.b, 0.6, 0.6, 0.6)
		end

		-- Estimated vendor value
		if self.db.tracking.itemValue then
			local vendorValue = self:GetTotalVendorValue()
			if vendorValue > 0 then
				local vendorRate = hours > 0 and string.format('  (%s/hr)', self:FormatMoney(vendorValue / hours)) or ''
				tooltip:AddDoubleLine('  Est. Vendor Value: ' .. self:FormatMoney(vendorValue), vendorRate, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5)
			end
		end
	end

	-- Money section
	if session.money > 0 then
		tooltip:AddLine(' ')
		local goldPerHour = hours > 0 and (session.money / hours) or 0
		local moneyRate = hours > 0 and string.format(' (%s/hr)', self:FormatMoney(goldPerHour)) or ''
		local moneyArrow = GetTrendArrow(goldPerHour, averages.goldPerHour)
		tooltip:AddLine('Money: ' .. self:FormatMoney(session.money) .. moneyRate .. moneyArrow, 1, 0.82, 0)
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
			tooltip:AddDoubleLine(string.format('  %s x%s', name, self:FormatNumber(data.count)), rate, 0.8, 0.8, 0.8, 0.6, 0.6, 0.6)
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
			tooltip:AddDoubleLine(string.format('  %s +%s', faction, self:FormatNumber(gained)), rate, 0.5, 1, 0.5, 0.6, 0.6, 0.6)
		end
	end

	-- Honor section
	local honor = session.honor or 0
	if honor > 0 then
		tooltip:AddLine(' ')
		local honorPerHour = hours > 0 and (honor / hours) or 0
		local honorRate = hours > 0 and string.format(' (%s/hr)', self:FormatNumber(honorPerHour)) or ''
		local honorArrow = GetTrendArrow(honorPerHour, averages.honorPerHour)
		tooltip:AddLine(string.format('Honor: %s%s%s', self:FormatNumber(honor), honorRate, honorArrow), 1, 0.82, 0)
	end

	-- Goals section
	if self.db.goals and #self.db.goals > 0 then
		local hasActiveGoal = false
		for _, goal in ipairs(self.db.goals) do
			if goal.active then
				hasActiveGoal = true
				break
			end
		end
		if hasActiveGoal then
			tooltip:AddLine(' ')
			tooltip:AddLine('Goals:', 1, 0.82, 0)
			for _, goal in ipairs(self.db.goals) do
				if goal.active then
					local current, target, progress = self:GetGoalProgress(goal)
					local pct = math.floor(progress * 100)
					local bar = self:BuildProgressBar(progress, 10)

					-- Goal name
					local goalName = goal.targetName or goal.type
					if goal.type == 'item' then
						local item = self.session.items[tostring(goal.targetItemID)]
						goalName = (item and item.name) or goalName
					elseif goal.type == 'money' then
						goalName = 'Gold'
					elseif goal.type == 'honor' then
						goalName = 'Honor'
					end

					-- Progress text
					local currentStr = self:FormatGoalValue(goal, current)
					local targetStr = self:FormatGoalTarget(goal)

					if progress >= 1 then
						-- Completed
						tooltip:AddLine(string.format('  \226\156\147 %s  %s/%s (100%%)', goalName, currentStr, targetStr), 0, 1, 0)
					else
						-- In progress with ETA
						local eta = self:GetGoalETA(goal)
						local etaStr = eta and string.format('  ~%s', eta) or ''
						tooltip:AddDoubleLine(string.format('  [%s] %s', bar, goalName), string.format('%s/%s (%d%%)%s', currentStr, targetStr, pct, etaStr), 1, 1, 1, 0.7, 0.7, 0.7)
					end
				end
			end
		end
	end

	-- Click hints
	tooltip:AddLine(' ')
	tooltip:AddLine('|cffffff00Left Click:|r Toggle Pause | |cffffff00Middle:|r Reset')
	tooltip:AddLine('|cffffff00Shift+Left:|r Options | |cffffff00Right:|r Options')

	tooltip:Show()
end
