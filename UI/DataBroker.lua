---@class LibsFarmAssistant
local LibsFarmAssistant = LibStub('AceAddon-3.0'):GetAddon('Libs-FarmAssistant')

local LDB = LibStub('LibDataBroker-1.1')

local dataObj

-- Reset confirmation dialog (shared with PopupWindow)
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

local DISPLAY_FORMATS = { 'items', 'money', 'combined' }

local function CycleDisplayFormat(direction)
	local current = LibsFarmAssistant.db.display.format
	local idx = 1
	for i, f in ipairs(DISPLAY_FORMATS) do
		if f == current then
			idx = i
			break
		end
	end
	idx = idx + direction
	if idx < 1 then
		idx = #DISPLAY_FORMATS
	elseif idx > #DISPLAY_FORMATS then
		idx = 1
	end
	LibsFarmAssistant.db.display.format = DISPLAY_FORMATS[idx]
	LibsFarmAssistant:UpdateDisplay()
end

function LibsFarmAssistant:InitializeDataBroker()
	dataObj = LDB:NewDataObject("Lib's FarmAssistant", {
		type = 'data source',
		text = 'Ready',
		icon = 'Interface\\Icons\\INV_Misc_Coin_03',
		label = 'Farm Assistant',
		OnClick = function(frame, button)
			if IsShiftKeyDown() then
				-- Shift+Click (either button): Reset with confirmation
				StaticPopup_Show('LIBSFA_RESET_SESSION')
			elseif button == 'LeftButton' then
				-- Left: Open Dashboard
				LibsFarmAssistant:TogglePopup()
			elseif button == 'RightButton' then
				-- Right: Pause/Resume
				LibsFarmAssistant:ToggleSession()
			end
		end,
		OnTooltipShow = function(tooltip)
			LibsFarmAssistant:BuildTooltip(tooltip)
		end,
		OnScrollWheel = function(_, delta)
			-- Scroll up (delta > 0) = previous format, scroll down = next format
			CycleDisplayFormat(delta > 0 and -1 or 1)
		end,
	})

	self.dataObject = dataObj
	self:UpdateDisplay()
end

function LibsFarmAssistant:UpdateDisplay()
	if not dataObj then
		return
	end

	-- Check for session notifications and goal completion
	if self.CheckSessionNotification then
		self:CheckSessionNotification()
	end
	if self.CheckGoalCompletion then
		self:CheckGoalCompletion()
	end

	if not self:IsSessionActive() then
		dataObj.text = '|cff808080Paused|r'
		return
	end

	local format = self.db.display.format
	local hours = self:GetSessionHours()

	if format == 'money' then
		if self.session.money > 0 then
			dataObj.text = self:FormatMoney(self.session.money)
		else
			dataObj.text = '0g'
		end
	elseif format == 'combined' then
		local _, totalItems = self:GetItemCounts()
		local parts = {}
		if totalItems > 0 then
			table.insert(parts, self:FormatNumber(totalItems) .. ' items')
		end
		if self.session.money > 0 then
			table.insert(parts, self:FormatMoney(self.session.money))
		end
		if #parts > 0 then
			dataObj.text = table.concat(parts, ' | ')
		else
			dataObj.text = 'Farming...'
		end
	else -- 'items'
		local _, totalItems = self:GetItemCounts()
		if totalItems > 0 then
			local rate = hours > 0 and string.format(' (%.0f/hr)', totalItems / hours) or ''
			dataObj.text = self:FormatNumber(totalItems) .. ' items' .. rate
		else
			dataObj.text = 'Farming...'
		end
	end
end
