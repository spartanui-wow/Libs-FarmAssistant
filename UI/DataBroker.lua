---@class LibsFarmAssistant
local LibsFarmAssistant = LibStub('AceAddon-3.0'):GetAddon('Libs-FarmAssistant')

---@class LibsFarmAssistant.DataBroker : AceModule, AceEvent-3.0, AceTimer-3.0
local DataBroker = LibsFarmAssistant:NewModule('DataBroker')
LibsFarmAssistant.DataBroker = DataBroker

local LDB = LibStub('LibDataBroker-1.1')

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

function DataBroker:OnEnable()
	self.dataObj = LDB:NewDataObject("Lib's FarmAssistant", {
		type = 'data source',
		text = 'Ready',
		icon = 'Interface\\Icons\\INV_Misc_Coin_03',
		label = 'Farm Assistant',
		OnClick = function(frame, button)
			if IsShiftKeyDown() then
				StaticPopup_Show('LIBSFA_RESET_SESSION')
			elseif button == 'LeftButton' then
				LibsFarmAssistant:TogglePopup()
			elseif button == 'RightButton' then
				LibsFarmAssistant:ToggleSession()
			end
		end,
		OnTooltipShow = function(tooltip)
			LibsFarmAssistant:BuildTooltip(tooltip)
		end,
		OnScrollWheel = function(_, delta)
			CycleDisplayFormat(delta > 0 and -1 or 1)
		end,
	})

	LibsFarmAssistant.dataObject = self.dataObj
	self:UpdateDisplay()
end

function DataBroker:UpdateDisplay()
	if not self.dataObj then
		return
	end

	-- Check for session notifications and goal completion
	LibsFarmAssistant:CheckSessionNotification()
	LibsFarmAssistant:CheckGoalCompletion()

	if not LibsFarmAssistant:IsSessionActive() then
		self.dataObj.text = '|cff808080Paused|r'
		return
	end

	local format = LibsFarmAssistant.db.display.format
	local hours = LibsFarmAssistant:GetSessionHours()

	if format == 'money' then
		if LibsFarmAssistant.session.money > 0 then
			self.dataObj.text = LibsFarmAssistant:FormatMoney(LibsFarmAssistant.session.money)
		else
			self.dataObj.text = '0g'
		end
	elseif format == 'combined' then
		local _, totalItems = LibsFarmAssistant:GetItemCounts()
		local parts = {}
		if totalItems > 0 then
			table.insert(parts, LibsFarmAssistant:FormatNumber(totalItems) .. ' items')
		end
		if LibsFarmAssistant.session.money > 0 then
			table.insert(parts, LibsFarmAssistant:FormatMoney(LibsFarmAssistant.session.money))
		end
		if #parts > 0 then
			self.dataObj.text = table.concat(parts, ' | ')
		else
			self.dataObj.text = 'Farming...'
		end
	else -- 'items'
		local _, totalItems = LibsFarmAssistant:GetItemCounts()
		if totalItems > 0 then
			local rate = hours > 0 and string.format(' (%.0f/hr)', totalItems / hours) or ''
			self.dataObj.text = LibsFarmAssistant:FormatNumber(totalItems) .. ' items' .. rate
		else
			self.dataObj.text = 'Farming...'
		end
	end
end
