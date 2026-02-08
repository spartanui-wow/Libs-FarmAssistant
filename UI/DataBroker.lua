---@class LibsFarmAssistant
local LibsFarmAssistant = LibStub('AceAddon-3.0'):GetAddon('Libs-FarmAssistant')

local LDB = LibStub('LibDataBroker-1.1')

local dataObj

function LibsFarmAssistant:InitializeDataBroker()
	dataObj = LDB:NewDataObject("Lib's FarmAssistant", {
		type = 'data source',
		text = 'Ready',
		icon = 'Interface\\Icons\\INV_Misc_Coin_03',
		label = 'Farm Assistant',
		OnClick = function(frame, button)
			if button == 'LeftButton' then
				if IsShiftKeyDown() then
					LibsFarmAssistant:TogglePopup()
				else
					LibsFarmAssistant:ToggleSession()
				end
			elseif button == 'MiddleButton' then
				LibsFarmAssistant:ResetSession()
			elseif button == 'RightButton' then
				LibsFarmAssistant:OpenOptions()
			end
		end,
		OnTooltipShow = function(tooltip)
			LibsFarmAssistant:BuildTooltip(tooltip)
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
