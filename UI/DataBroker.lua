---@class LibsFarmAssistant
local LibsFarmAssistant = LibStub('AceAddon-3.0'):GetAddon('Libs-FarmAssistant')

---@class LibsFarmAssistant.DataBroker : AceModule, AceEvent-3.0, AceTimer-3.0
local DataBroker = LibsFarmAssistant:NewModule('DataBroker')
LibsFarmAssistant.DataBroker = DataBroker

local LDB = LibStub('LibDataBroker-1.1')
local Ledger = LibsFarmAssistant.Ledger
local Format = LibsFarmAssistant.Format

local FORMATS = { 'value', 'gold', 'items', 'kills', 'hunt' }

local function CycleFormat(direction)
	local current = LibsFarmAssistant.db.display.format
	local index = 1
	for i, f in ipairs(FORMATS) do
		if f == current then
			index = i
		end
	end
	index = (index - 1 + direction) % #FORMATS + 1
	LibsFarmAssistant.db.display.format = FORMATS[index]
	DataBroker:UpdateDisplay()
end

function DataBroker:OnEnable()
	self.dataObj = LDB:NewDataObject("Lib's FarmAssistant", {
		type = 'data source',
		text = 'Farming',
		icon = 'Interface\\Icons\\INV_Misc_Coin_02',
		label = 'Farm',
		OnClick = function(_, button)
			if IsShiftKeyDown() then
				StaticPopup_Show('LIBSFA_NEW_SESSION')
			elseif button == 'RightButton' then
				LibsFarmAssistant:ToggleSession()
			elseif button == 'MiddleButton' then
				LibsFarmAssistant:ToggleTracker()
			else
				LibsFarmAssistant:ToggleWindow()
			end
		end,
		OnEnter = function(frame)
			LibsFarmAssistant.BrokerTooltip:Show(frame, LibsFarmAssistant.BrokerTooltip.HINTS.broker)
		end,
		OnMouseWheel = function(_, delta)
			CycleFormat(delta > 0 and -1 or 1)
		end,
	})
	self.dataObj.OnScrollWheel = self.dataObj.OnMouseWheel
	LibsFarmAssistant.dataObject = self.dataObj

	self:RegisterMessage('LIBSFA_UPDATE', 'UpdateDisplay')
	self:RegisterMessage('LIBSFA_SESSION_STATE', 'UpdateDisplay')
	self:RegisterMessage('LIBSFA_SESSION_STARTED', 'UpdateDisplay')
	self:RegisterMessage('LIBSFA_HUNTS_UPDATED', 'UpdateDisplay')
	self:UpdateDisplay()
end

---@return string
function DataBroker:Text()
	if not LibsFarmAssistant:IsSessionActive() then
		return '|cff9c9ca3' .. LibsFarmAssistant.SessionManager:StateText() .. '|r'
	end
	local bucket = Ledger:Session()
	local format = LibsFarmAssistant.db.display.format

	if format == 'gold' then
		local gold = Ledger.Money(bucket, 'loot')
		local rate = Ledger.PerHour(gold, bucket)
		return rate and (Format.Money(rate) .. '/hr') or Format.Money(gold)
	elseif format == 'items' then
		local total = Ledger.ItemCounts(bucket)
		local rate = Ledger.PerHour(total, bucket)
		return Format.Number(total) .. ' items' .. (rate and (' (' .. Format.Rate(rate) .. '/hr)') or '')
	elseif format == 'kills' then
		local rate = Ledger.PerHour(bucket.kills, bucket)
		return Format.Number(bucket.kills) .. ' kills' .. (rate and (' (' .. Format.Rate(rate) .. '/hr)') or '')
	elseif format == 'hunt' then
		for _, hunt in ipairs(LibsFarmAssistant.Hunts:List()) do
			if not hunt.paused and not LibsFarmAssistant.Hunts:IsCollected(hunt) then
				local name = LibsFarmAssistant.Pricing:Meta(hunt.id).n or 'Hunt'
				return string.format('%s: %s', name, Format.Number(hunt.attempts or 0))
			end
		end
		return 'No hunt'
	end

	local value = Ledger.TotalValue(bucket)
	local rate = Ledger.PerHour(value, bucket)
	if rate then
		return Format.Money(rate) .. '/hr'
	end
	return value > 0 and Format.Money(value) or 'Farming'
end

function DataBroker:UpdateDisplay()
	if self.dataObj then
		self.dataObj.text = self:Text()
	end
	LibsFarmAssistant.BrokerTooltip:Refresh()
end
