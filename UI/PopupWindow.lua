---@class LibsFarmAssistant
local LibsFarmAssistant = LibStub('AceAddon-3.0'):GetAddon('Libs-FarmAssistant')

----------------------------------------------------------------------------------------------------
-- Session Dashboard Popup Window
-- Built with LibAT.UI (matching Libs-TimePlayed style)
----------------------------------------------------------------------------------------------------

local popupFrame
local updateTimer

---Create the popup window frame using LibAT.UI
---@return Frame|nil
function LibsFarmAssistant:CreatePopup()
	if popupFrame then
		return popupFrame
	end

	if not LibAT or not LibAT.UI or not LibAT.UI.CreateWindow then
		self:Log('LibAT.UI not available, cannot create popup window', 'error')
		return nil
	end

	local db = self.db.popup

	local window = LibAT.UI.CreateWindow({
		name = 'LibsFarmAssistantPopup',
		title = "|cffffffffLib's|r |cffe21f1fFarm Assistant|r",
		width = db.width or 500,
		height = db.height or 400,
		hidePortrait = true,
		resizable = true,
		minWidth = 350,
		minHeight = 250,
	})

	-- Control frame: buttons + status + duration
	local controlFrame = LibAT.UI.CreateControlFrame(window)

	local pauseBtn = LibAT.UI.CreateButton(controlFrame, 100, 22, 'Pause')
	pauseBtn:SetPoint('LEFT', controlFrame, 'LEFT', 8, 0)
	pauseBtn:SetScript('OnClick', function()
		LibsFarmAssistant:ToggleSession()
	end)
	window.pauseBtn = pauseBtn

	local resetBtn = LibAT.UI.CreateButton(controlFrame, 80, 22, 'Reset')
	resetBtn:SetPoint('LEFT', pauseBtn, 'RIGHT', 6, 0)
	resetBtn:SetScript('OnClick', function()
		StaticPopup_Show('LIBSFA_RESET_SESSION')
	end)

	local durationText = controlFrame:CreateFontString(nil, 'OVERLAY', 'GameFontHighlight')
	durationText:SetPoint('CENTER', controlFrame, 'CENTER', 0, 0)
	window.durationText = durationText

	local statusText = controlFrame:CreateFontString(nil, 'OVERLAY', 'GameFontNormal')
	statusText:SetPoint('RIGHT', controlFrame, 'RIGHT', -8, 0)
	window.statusText = statusText

	-- Scrollable content area
	local contentFrame = LibAT.UI.CreateContentFrame(window, controlFrame)

	local scrollFrame = LibAT.UI.CreateScrollFrame(contentFrame)
	scrollFrame:SetPoint('TOPLEFT', contentFrame, 'TOPLEFT', 4, 0)
	scrollFrame:SetPoint('BOTTOMRIGHT', contentFrame, 'BOTTOMRIGHT', -4, 20)
	window.scrollFrame = scrollFrame

	local scrollChild = CreateFrame('Frame', nil, scrollFrame)
	scrollChild:SetWidth(1)
	scrollChild:SetHeight(1)
	scrollFrame:SetScrollChild(scrollChild)
	window.scrollChild = scrollChild

	scrollChild.fontStrings = {}

	-- Bottom summary line
	local summaryText = window:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
	summaryText:SetPoint('BOTTOMLEFT', window, 'BOTTOMLEFT', 15, 7)
	summaryText:SetJustifyH('LEFT')
	window.summaryText = summaryText

	-- Save position/size on hide, stop update timer
	window:HookScript('OnHide', function()
		local point, _, _, x, y = window:GetPoint()
		self.db.popup.point = point or 'CENTER'
		self.db.popup.x = x or 0
		self.db.popup.y = y or 0
		self.db.popup.width = window:GetWidth()
		self.db.popup.height = window:GetHeight()
		if updateTimer then
			self:CancelTimer(updateTimer)
			updateTimer = nil
		end
	end)

	popupFrame = window
	return window
end

---Build the content display inside the popup
function LibsFarmAssistant:UpdatePopupContent()
	if not popupFrame or not popupFrame:IsShown() then
		return
	end

	local session = self.session
	local hours = self:GetSessionHours()
	local duration = self:GetSessionDuration()
	local isActive = self:IsSessionActive()

	-- Status and controls
	popupFrame.statusText:SetText(isActive and '|cff00ff00Active|r' or '|cffff0000Paused|r')
	popupFrame.pauseBtn:SetText(isActive and 'Pause' or 'Resume')
	popupFrame.durationText:SetText(self:FormatDuration(duration))

	-- Build content lines
	local lines = {}

	-- Items
	local uniqueItems, totalItems = self:GetItemCounts()
	if totalItems > 0 then
		local rate = hours > 0 and string.format(' (%.0f/hr)', totalItems / hours) or ''
		table.insert(lines, string.format('|cffffd100Items:|r %s looted%s', self:FormatNumber(totalItems), rate))

		local sorted = {}
		for _, item in pairs(session.items) do
			table.insert(sorted, item)
		end
		table.sort(sorted, function(a, b)
			return a.count > b.count
		end)

		for _, item in ipairs(sorted) do
			local rate2 = hours > 0 and string.format(' (%.1f/hr)', item.count / hours) or ''
			table.insert(lines, string.format('  %s x%s%s', item.link or item.name, self:FormatNumber(item.count), rate2))
		end
	end

	-- Watched items not yet looted
	local watchedItems = self:GetWatchedItems()
	for key, watchInfo in pairs(watchedItems) do
		if not session.items[key] then
			table.insert(lines, string.format('  |cff808080%s (watching)|r', watchInfo.link or watchInfo.name or '?'))
		end
	end

	-- Money
	if session.money > 0 then
		local goldRate = hours > 0 and string.format(' (%s/hr)', self:FormatMoney(session.money / hours)) or ''
		table.insert(lines, '')
		table.insert(lines, string.format('|cffffd100Money:|r %s%s', self:FormatMoney(session.money), goldRate))
	end

	-- Currencies
	local hasCurrency = false
	for _ in pairs(session.currencies) do
		hasCurrency = true
		break
	end
	if hasCurrency then
		table.insert(lines, '')
		table.insert(lines, '|cffffd100Currency:|r')
		for name, data in pairs(session.currencies) do
			local rate2 = hours > 0 and string.format(' (%.1f/hr)', data.count / hours) or ''
			table.insert(lines, string.format('  %s x%s%s', name, self:FormatNumber(data.count), rate2))
		end
	end

	-- Reputation
	local hasRep = false
	for _ in pairs(session.reputation) do
		hasRep = true
		break
	end
	if hasRep then
		table.insert(lines, '')
		table.insert(lines, '|cffffd100Reputation:|r')
		for faction, gained in pairs(session.reputation) do
			local rate2 = hours > 0 and string.format(' (%.0f/hr)', gained / hours) or ''
			table.insert(lines, string.format('  %s +%s%s', faction, self:FormatNumber(gained), rate2))
		end
	end

	-- Honor
	local honor = session.honor or 0
	if honor > 0 then
		local honorRate = hours > 0 and string.format(' (%.0f/hr)', honor / hours) or ''
		table.insert(lines, '')
		table.insert(lines, string.format('|cffffd100Honor:|r %s%s', self:FormatNumber(honor), honorRate))
	end

	-- Goals
	if self.db.goals and #self.db.goals > 0 then
		local hasActiveGoal = false
		for _, goal in ipairs(self.db.goals) do
			if goal.active then
				hasActiveGoal = true
				break
			end
		end
		if hasActiveGoal then
			table.insert(lines, '')
			table.insert(lines, '|cffffd100Goals:|r')
			for _, goal in ipairs(self.db.goals) do
				if goal.active then
					local _, _, progress = self:GetGoalProgress(goal)
					local pct = math.floor(progress * 100)
					local bar = self:BuildProgressBar(progress, 15)
					local goalName = goal.targetName or goal.type

					if progress >= 1 then
						table.insert(lines, string.format('  |cff00ff00[DONE] %s: Complete!|r', goalName))
					else
						table.insert(lines, string.format('  [%s] %s: %d%%', bar, goalName, pct))
					end
				end
			end
		end
	end

	-- Render lines into font string pool
	local scrollChild = popupFrame.scrollChild
	local fontStrings = scrollChild.fontStrings

	-- Hide all existing strings first
	for _, fs in ipairs(fontStrings) do
		fs:Hide()
	end

	local yOffset = 0
	local lineHeight = 16
	local contentWidth = popupFrame.scrollFrame:GetWidth() - 10

	scrollChild:SetWidth(contentWidth)

	for i, lineText in ipairs(lines) do
		local fs = fontStrings[i]
		if not fs then
			fs = scrollChild:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
			fontStrings[i] = fs
		end
		fs:Show()
		fs:ClearAllPoints()
		fs:SetPoint('TOPLEFT', 0, -yOffset)
		fs:SetWidth(contentWidth)
		fs:SetJustifyH('LEFT')
		fs:SetText(lineText)
		yOffset = yOffset + lineHeight
	end

	scrollChild:SetHeight(math.max(yOffset + 10, 1))

	-- Summary line
	local summaryParts = {}
	table.insert(summaryParts, 'Session: ' .. self:FormatDuration(duration))
	if totalItems > 0 and hours > 0 then
		table.insert(summaryParts, string.format('%s items/hr', self:FormatNumber(math.floor(totalItems / hours))))
	end
	popupFrame.summaryText:SetText('|cffb3b3b3' .. table.concat(summaryParts, '  |  ') .. '|r')
end

---Toggle the popup window visibility
function LibsFarmAssistant:TogglePopup()
	local frame = self:CreatePopup()
	if not frame then
		self:Print("Dashboard requires Libs-AddonTools. Install it from CurseForge.")
		return
	end

	if frame:IsShown() then
		frame:Hide()
	else
		-- Restore position and size
		local db = self.db.popup
		frame:ClearAllPoints()
		frame:SetPoint(db.point or 'CENTER', UIParent, db.point or 'CENTER', db.x or 0, db.y or 0)
		frame:SetSize(db.width or 500, db.height or 400)

		self:UpdatePopupContent()
		frame:Show()

		-- Start 1-second update timer
		if not updateTimer then
			updateTimer = self:ScheduleRepeatingTimer('UpdatePopupContent', 1)
		end
	end
end
