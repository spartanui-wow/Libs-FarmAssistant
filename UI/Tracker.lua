---@class LibsFarmAssistant
local LibsFarmAssistant = LibStub('AceAddon-3.0'):GetAddon('Libs-FarmAssistant')

-- A small always-on panel for mid-pull glances: the clock, value per hour, kills, hunts and the
-- standing closest to its next step. Click opens the window; drag moves it unless locked.

---@class LibsFarmAssistant.Tracker : AceModule, AceEvent-3.0, AceTimer-3.0
local Tracker = LibsFarmAssistant:NewModule('Tracker')
LibsFarmAssistant.Tracker = Tracker

local T = LibsFarmAssistant.Theme
local C = T.color
local Ledger = LibsFarmAssistant.Ledger
local Format = LibsFarmAssistant.Format

local WIDTH = 230
local ROW = 16
local MAX_ROWS = 9

function Tracker:OnEnable()
	self:RegisterMessage('LIBSFA_UPDATE', 'Refresh')
	self:RegisterMessage('LIBSFA_SESSION_STATE', 'Refresh')
	self:RegisterMessage('LIBSFA_HUNTS_UPDATED', 'Refresh')
	self:RegisterMessage('LIBSFA_HUNTS_CHANGED', 'Refresh')
	self:RegisterMessage('LIBSFA_SETTINGS_CHANGED', 'ApplySettings')
	if LibsFarmAssistant.db.tracker.shown then
		self:Show()
	end
end

local function Settings()
	return LibsFarmAssistant.db.tracker
end

function Tracker:Create()
	if self.frame then
		return self.frame
	end
	local frame = _G.LibsFarmAssistantTracker or CreateFrame('Button', 'LibsFarmAssistantTracker', UIParent)
	self.frame = frame
	frame:SetWidth(WIDTH)
	frame:SetFrameStrata('LOW')
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag('LeftButton')
	frame:RegisterForClicks('AnyUp')
	if frame.SetDontSavePosition then
		frame:SetDontSavePosition(true)
	end
	T.Fill(frame, C.plate)
	T.Border(frame, C.line)

	local state = T.Text(frame, 11, C.muted)
	state:SetPoint('TOPLEFT', 8, -7)
	self.state = state
	local clock = T.Text(frame, 13, C.text, 'figures')
	clock:SetPoint('TOPRIGHT', -8, -6)
	self.clock = clock
	local rule = T.Rule(frame)
	rule:SetPoint('TOPLEFT', 6, -24)
	rule:SetPoint('TOPRIGHT', -6, -24)

	self.rows = {}
	for i = 1, MAX_ROWS do
		local label = T.Text(frame, 11, C.muted)
		local value = T.Text(frame, 12, C.text, 'figures')
		value:SetPoint('TOPRIGHT', -8, -28 - (i - 1) * ROW)
		value:SetJustifyH('RIGHT')
		label:SetPoint('TOPLEFT', 8, -28 - (i - 1) * ROW)
		label:SetPoint('RIGHT', value, 'LEFT', -6, 0)
		self.rows[i] = { label = label, value = value }
	end

	frame:SetScript('OnDragStart', function(f)
		if not Settings().locked then
			f:StartMoving()
		end
	end)
	frame:SetScript('OnDragStop', function(f)
		f:StopMovingOrSizing()
		local point, _, relativePoint, x, y = f:GetPoint(1)
		local s = Settings()
		s.point, s.relativePoint, s.x, s.y = point, relativePoint, x, y
	end)
	frame:SetScript('OnClick', function(_, button)
		if button == 'RightButton' then
			LibsFarmAssistant:ToggleSession()
		else
			LibsFarmAssistant:ToggleWindow()
		end
	end)
	frame:SetScript('OnEnter', function(f)
		GameTooltip:SetOwner(f, 'ANCHOR_LEFT')
		GameTooltip:SetText('Farm Assistant', 1, 1, 1)
		GameTooltip:AddLine('Click to open the window. Right-click to pause or resume.', C.muted[1], C.muted[2], C.muted[3], true)
		if not Settings().locked then
			GameTooltip:AddLine('Drag to move. Lock it in the settings.', C.muted[1], C.muted[2], C.muted[3], true)
		end
		GameTooltip:Show()
	end)
	frame:SetScript('OnLeave', function()
		GameTooltip:Hide()
	end)

	self:ApplySettings()
	return frame
end

function Tracker:ApplySettings()
	if not self.frame then
		return
	end
	local s = Settings()
	self.frame:SetScale(s.scale or 1)
	self.frame:ClearAllPoints()
	self.frame:SetPoint(s.point or 'RIGHT', UIParent, s.relativePoint or s.point or 'RIGHT', s.x or -180, s.y or 120)
	self:Refresh()
end

---@return table[] lines { label, value, color }
function Tracker:Lines()
	local lines = {}
	local s = Settings().lines
	local bucket = Ledger:Session()

	if s.value then
		local value = Ledger.TotalValue(bucket)
		local rate = Ledger.PerHour(value, bucket)
		lines[#lines + 1] = { 'Value', rate and (Format.Money(rate) .. ' /hr') or Format.Money(value), C.gold }
	end
	if s.gold then
		local gold = Ledger.Money(bucket, 'loot')
		local rate = Ledger.PerHour(gold, bucket)
		lines[#lines + 1] = { 'Gold looted', rate and (Format.Money(rate) .. ' /hr') or Format.Money(gold), C.gold }
	end
	if s.kills and bucket.kills > 0 then
		local rate = Ledger.PerHour(bucket.kills, bucket)
		lines[#lines + 1] = { 'Kills', Format.Number(bucket.kills) .. (rate and ('  ' .. Format.Rate(rate) .. ' /hr') or '') }
	end
	if s.xp and bucket.xp > 0 and LibsFarmAssistant.Compat.CanGainXP() then
		local seconds, kills = LibsFarmAssistant.ExperienceTracker:TimeToLevel(bucket)
		local value = seconds and (Format.Duration(seconds) .. ' to go') or ('+' .. Format.Short(bucket.xp))
		if kills then
			value = Format.Number(kills) .. (kills == 1 and ' kill' or ' kills') .. (seconds and ('  ' .. Format.Duration(seconds)) or '')
		end
		lines[#lines + 1] = { 'Level ' .. UnitLevel('player'), value }
	end
	if s.hunts then
		for _, hunt in ipairs(LibsFarmAssistant.Hunts:List()) do
			if not hunt.paused and not LibsFarmAssistant.Hunts:IsCollected(hunt) then
				local meta = LibsFarmAssistant.Pricing:Meta(hunt.id)
				local r, g, b = T.QualityRGB(meta.q)
				local saved = LibsFarmAssistant.Lockouts:MyStatus(hunt) == 'done'
				lines[#lines + 1] = { meta.n or ('Item ' .. hunt.id), Format.Number(hunt.attempts or 0) .. (saved and '  saved' or ''), saved and C.muted or nil, { r, g, b } }
			end
		end
	end
	if s.rep then
		local gains = LibsFarmAssistant.ReputationTracker:Gains(bucket)
		if gains[1] then
			lines[#lines + 1] = { gains[1].progress.name, LibsFarmAssistant.Widgets.RepPace(gains[1]) }
		end
	end
	return lines
end

function Tracker:UpdateClock()
	if self.frame and self.frame:IsShown() then
		self.clock:SetText(Format.Clock(LibsFarmAssistant:GetSessionDuration()))
	end
end

function Tracker:Refresh()
	if not self.frame or not self.frame:IsShown() then
		return
	end
	local active = LibsFarmAssistant:IsSessionActive()
	self.state:SetText(active and 'Farming' or (LibsFarmAssistant.SessionManager.autoPaused and 'Away' or 'Paused'))
	T.Color(self.state, active and C.muted or C.warn)
	self:UpdateClock()

	local lines = self:Lines()
	local count = math.min(#lines, MAX_ROWS)
	for i, row in ipairs(self.rows) do
		local line = lines[i]
		if line and i <= count then
			row.label:SetText(line[1])
			T.Color(row.label, line[4] or C.muted)
			row.value:SetText(line[2])
			T.Color(row.value, line[3] or C.text)
			row.label:Show()
			row.value:Show()
		else
			row.label:Hide()
			row.value:Hide()
		end
	end
	if count == 0 then
		self.rows[1].label:SetText('Nothing counted yet')
		self.rows[1].label:Show()
		count = 1
	end
	self.frame:SetHeight(32 + count * ROW)
end

function Tracker:Show()
	local frame = self:Create()
	frame:Show()
	Settings().shown = true
	if not self.ticker then
		self.ticker = self:ScheduleRepeatingTimer('UpdateClock', 1)
	end
	self:Refresh()
end

function Tracker:Hide()
	if self.frame then
		self.frame:Hide()
	end
	Settings().shown = false
	if self.ticker then
		self:CancelTimer(self.ticker)
		self.ticker = nil
	end
end

function Tracker:Toggle()
	if self.frame and self.frame:IsShown() then
		self:Hide()
	else
		self:Show()
	end
end
