---@class LibsFarmAssistant
local LibsFarmAssistant = LibStub('AceAddon-3.0'):GetAddon('Libs-FarmAssistant')

----------------------------------------------------------------------------------------------------
-- Session Dashboard Popup Window
-- A standalone, draggable, resizable window showing real-time session data
----------------------------------------------------------------------------------------------------

local popupFrame
local updateTimer

---Create the popup window frame
---@return Frame
local function CreatePopupFrame()
	local f = CreateFrame('Frame', 'LibsFarmAssistantPopup', UIParent, 'BackdropTemplate')
	f:SetFrameStrata('DIALOG')
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:SetResizable(true)
	f:SetResizeBounds(300, 200, 800, 600)
	f:EnableMouse(true)

	-- Backdrop
	f:SetBackdrop({
		bgFile = 'Interface\\Tooltips\\UI-Tooltip-Background',
		edgeFile = 'Interface\\Tooltips\\UI-Tooltip-Border',
		edgeSize = 16,
		insets = { left = 4, right = 4, top = 4, bottom = 4 },
	})
	f:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
	f:SetBackdropBorderColor(0.6, 0.6, 0.6, 0.8)

	-- Title bar (draggable)
	local titleBar = CreateFrame('Frame', nil, f)
	titleBar:SetHeight(28)
	titleBar:SetPoint('TOPLEFT', 0, 0)
	titleBar:SetPoint('TOPRIGHT', 0, 0)
	titleBar:EnableMouse(true)
	titleBar:RegisterForDrag('LeftButton')
	titleBar:SetScript('OnDragStart', function()
		f:StartMoving()
	end)
	titleBar:SetScript('OnDragStop', function()
		f:StopMovingOrSizing()
		LibsFarmAssistant:SavePopupPosition()
	end)

	-- Title text
	local title = titleBar:CreateFontString(nil, 'OVERLAY', 'GameFontNormalLarge')
	title:SetPoint('LEFT', 10, 0)
	title:SetText("|cffffffffLib's|r |cffe21f1fFarm Assistant|r")
	f.title = title

	-- Close button
	local closeBtn = CreateFrame('Button', nil, titleBar, 'UIPanelCloseButton')
	closeBtn:SetPoint('TOPRIGHT', -2, -2)
	closeBtn:SetScript('OnClick', function()
		f:Hide()
	end)

	-- Status indicator
	local statusText = f:CreateFontString(nil, 'OVERLAY', 'GameFontNormal')
	statusText:SetPoint('TOPRIGHT', -40, -8)
	f.statusText = statusText

	-- Duration display (large, center top)
	local durationText = f:CreateFontString(nil, 'OVERLAY', 'GameFontNormalHuge')
	durationText:SetPoint('TOP', 0, -35)
	f.durationText = durationText

	-- Control buttons
	local controlFrame = CreateFrame('Frame', nil, f)
	controlFrame:SetHeight(30)
	controlFrame:SetPoint('TOPLEFT', 10, -60)
	controlFrame:SetPoint('TOPRIGHT', -10, -60)

	-- Pause/Resume button
	local pauseBtn = CreateFrame('Button', nil, controlFrame, 'UIPanelButtonTemplate')
	pauseBtn:SetSize(100, 24)
	pauseBtn:SetPoint('LEFT', 0, 0)
	pauseBtn:SetText('Pause')
	pauseBtn:SetScript('OnClick', function()
		LibsFarmAssistant:ToggleSession()
	end)
	f.pauseBtn = pauseBtn

	-- Reset button
	local resetBtn = CreateFrame('Button', nil, controlFrame, 'UIPanelButtonTemplate')
	resetBtn:SetSize(80, 24)
	resetBtn:SetPoint('LEFT', pauseBtn, 'RIGHT', 8, 0)
	resetBtn:SetText('Reset')
	resetBtn:SetScript('OnClick', function()
		StaticPopup_Show('LIBSFA_RESET_SESSION')
	end)
	f.resetBtn = resetBtn

	-- Static popup for reset confirmation
	StaticPopupDialogs['LIBSFA_RESET_SESSION'] = {
		text = 'Reset your farming session? This clears all tracked data.',
		button1 = 'Reset',
		button2 = 'Cancel',
		OnAccept = function()
			LibsFarmAssistant:ResetSession()
		end,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
	}

	-- Scrollable content area
	local scrollFrame = CreateFrame('ScrollFrame', nil, f, 'UIPanelScrollFrameTemplate')
	scrollFrame:SetPoint('TOPLEFT', 10, -95)
	scrollFrame:SetPoint('BOTTOMRIGHT', -30, 35)

	local content = CreateFrame('Frame', nil, scrollFrame)
	content:SetWidth(1) -- Will be set dynamically
	content:SetHeight(1)
	scrollFrame:SetScrollChild(content)
	f.scrollFrame = scrollFrame
	f.content = content

	-- Bottom summary line
	local summaryText = f:CreateFontString(nil, 'OVERLAY', 'GameFontNormal')
	summaryText:SetPoint('BOTTOM', 0, 12)
	f.summaryText = summaryText

	-- Resize grip
	local resizeGrip = CreateFrame('Button', nil, f)
	resizeGrip:SetSize(16, 16)
	resizeGrip:SetPoint('BOTTOMRIGHT', -4, 4)
	resizeGrip:SetNormalTexture('Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up')
	resizeGrip:SetHighlightTexture('Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight')
	resizeGrip:SetPushedTexture('Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down')
	resizeGrip:SetScript('OnMouseDown', function()
		f:StartSizing('BOTTOMRIGHT')
	end)
	resizeGrip:SetScript('OnMouseUp', function()
		f:StopMovingOrSizing()
		LibsFarmAssistant:SavePopupPosition()
	end)

	-- Hide handler to save position and stop updates
	f:SetScript('OnHide', function()
		LibsFarmAssistant:SavePopupPosition()
		if updateTimer then
			LibsFarmAssistant:CancelTimer(updateTimer)
			updateTimer = nil
		end
	end)

	return f
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

	-- Status
	popupFrame.statusText:SetText(isActive and '|cff00ff00Active|r' or '|cffff0000Paused|r')
	popupFrame.pauseBtn:SetText(isActive and 'Pause' or 'Resume')

	-- Duration
	popupFrame.durationText:SetText(self:FormatDuration(duration))

	-- Build content text
	local lines = {}

	-- Items
	local uniqueItems, totalItems = self:GetItemCounts()
	if totalItems > 0 then
		local rate = hours > 0 and string.format(' (%.0f/hr)', totalItems / hours) or ''
		table.insert(lines, { text = string.format('|cffffd100Items:|r %s looted%s', self:FormatNumber(totalItems), rate), indent = 0 })

		local sorted = {}
		for _, item in pairs(session.items) do
			table.insert(sorted, item)
		end
		table.sort(sorted, function(a, b)
			return a.count > b.count
		end)

		for _, item in ipairs(sorted) do
			local rate2 = hours > 0 and string.format(' (%.1f/hr)', item.count / hours) or ''
			table.insert(lines, { text = string.format('  %s x%s%s', item.link or item.name, self:FormatNumber(item.count), rate2), indent = 1 })
		end
	end

	-- Watched items not yet looted
	local watchedItems = self:GetWatchedItems()
	for key, watchInfo in pairs(watchedItems) do
		if not session.items[key] then
			table.insert(lines, { text = string.format('  |cff808080%s (watching)|r', watchInfo.link or watchInfo.name or '?'), indent = 1 })
		end
	end

	-- Money
	if session.money > 0 then
		local goldRate = hours > 0 and string.format(' (%s/hr)', self:FormatMoney(session.money / hours)) or ''
		table.insert(lines, { text = '' })
		table.insert(lines, { text = string.format('|cffffd100Money:|r %s%s', self:FormatMoney(session.money), goldRate), indent = 0 })
	end

	-- Currencies
	local hasCurrency = false
	for _ in pairs(session.currencies) do
		hasCurrency = true
		break
	end
	if hasCurrency then
		table.insert(lines, { text = '' })
		table.insert(lines, { text = '|cffffd100Currency:|r', indent = 0 })
		for name, data in pairs(session.currencies) do
			local rate2 = hours > 0 and string.format(' (%.1f/hr)', data.count / hours) or ''
			table.insert(lines, { text = string.format('  %s x%s%s', name, self:FormatNumber(data.count), rate2), indent = 1 })
		end
	end

	-- Reputation
	local hasRep = false
	for _ in pairs(session.reputation) do
		hasRep = true
		break
	end
	if hasRep then
		table.insert(lines, { text = '' })
		table.insert(lines, { text = '|cffffd100Reputation:|r', indent = 0 })
		for faction, gained in pairs(session.reputation) do
			local rate2 = hours > 0 and string.format(' (%.0f/hr)', gained / hours) or ''
			table.insert(lines, { text = string.format('  %s +%s%s', faction, self:FormatNumber(gained), rate2), indent = 1 })
		end
	end

	-- Honor
	local honor = session.honor or 0
	if honor > 0 then
		local honorRate = hours > 0 and string.format(' (%.0f/hr)', honor / hours) or ''
		table.insert(lines, { text = '' })
		table.insert(lines, { text = string.format('|cffffd100Honor:|r %s%s', self:FormatNumber(honor), honorRate), indent = 0 })
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
			table.insert(lines, { text = '' })
			table.insert(lines, { text = '|cffffd100Goals:|r', indent = 0 })
			for _, goal in ipairs(self.db.goals) do
				if goal.active then
					local current, target, progress = self:GetGoalProgress(goal)
					local pct = math.floor(progress * 100)
					local bar = self:BuildProgressBar(progress, 15)
					local goalName = goal.targetName or goal.type

					if progress >= 1 then
						table.insert(lines, { text = string.format('  |cff00ff00\226\156\147 %s: Complete!|r', goalName), indent = 1 })
					else
						table.insert(lines, { text = string.format('  [%s] %s: %d%%', bar, goalName, pct), indent = 1 })
					end
				end
			end
		end
	end

	-- Render content into the content frame
	local contentFrame = popupFrame.content
	-- Clear existing font strings
	if contentFrame.fontStrings then
		for _, fs in ipairs(contentFrame.fontStrings) do
			fs:Hide()
		end
	end
	contentFrame.fontStrings = contentFrame.fontStrings or {}

	local yOffset = 0
	local lineHeight = 16
	local contentWidth = popupFrame.scrollFrame:GetWidth() - 10

	contentFrame:SetWidth(contentWidth)

	for i, line in ipairs(lines) do
		local fs = contentFrame.fontStrings[i]
		if not fs then
			fs = contentFrame:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
			contentFrame.fontStrings[i] = fs
		end
		fs:Show()
		fs:ClearAllPoints()
		fs:SetPoint('TOPLEFT', 0, -yOffset)
		fs:SetWidth(contentWidth)
		fs:SetJustifyH('LEFT')
		fs:SetText(line.text or '')
		yOffset = yOffset + lineHeight
	end

	contentFrame:SetHeight(math.max(yOffset + 10, 1))

	-- Summary line
	local summaryParts = {}
	table.insert(summaryParts, 'Session: ' .. self:FormatDuration(duration))
	if totalItems > 0 and hours > 0 then
		table.insert(summaryParts, string.format('%s items/hr', self:FormatNumber(math.floor(totalItems / hours))))
	end
	popupFrame.summaryText:SetText('|cffb3b3b3' .. table.concat(summaryParts, '  |  ') .. '|r')
end

---Save the popup window position
function LibsFarmAssistant:SavePopupPosition()
	if not popupFrame then
		return
	end

	local db = self.db.popup
	if not db then
		return
	end

	local point, _, _, x, y = popupFrame:GetPoint()
	db.point = point or 'CENTER'
	db.x = x or 0
	db.y = y or 0
	db.width = popupFrame:GetWidth()
	db.height = popupFrame:GetHeight()
end

---Toggle the popup window visibility
function LibsFarmAssistant:TogglePopup()
	if not popupFrame then
		popupFrame = CreatePopupFrame()
	end

	if popupFrame:IsShown() then
		popupFrame:Hide()
	else
		-- Restore position
		local db = self.db.popup
		if db then
			popupFrame:ClearAllPoints()
			popupFrame:SetPoint(db.point or 'CENTER', UIParent, db.point or 'CENTER', db.x or 0, db.y or 0)
			popupFrame:SetSize(db.width or 420, db.height or 350)
		else
			popupFrame:ClearAllPoints()
			popupFrame:SetPoint('CENTER', UIParent, 'CENTER', 0, 0)
			popupFrame:SetSize(420, 350)
		end

		popupFrame:Show()
		self:UpdatePopupContent()

		-- Start 1-second update timer
		if not updateTimer then
			updateTimer = self:ScheduleRepeatingTimer('UpdatePopupContent', 1)
		end
	end
end
