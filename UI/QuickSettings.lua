---@class LibsFarmAssistant
local LibsFarmAssistant = LibStub('AceAddon-3.0'):GetAddon('Libs-FarmAssistant')

-- The settings that decide when tracking runs, opened from the main window's header so they can be
-- changed without leaving it. The same settings are in /farm options > General.

---@class LibsFarmAssistant.Window
local Window = LibsFarmAssistant.Window

local T = LibsFarmAssistant.Theme
local W = LibsFarmAssistant.Widgets
local C = T.color

local WIDTH = 300

local START_ITEMS = {
	{ key = 'login', label = 'Log in', tooltip = 'Tracking starts as soon as you log in.' },
	{ key = 'kill', label = 'First kill', tooltip = 'Tracking waits after you log in and starts with your first kill.' },
	{ key = 'manual', label = 'Manually', tooltip = 'Tracking stays paused after you log in until you press resume.' },
}

local function SessionSettings()
	return LibsFarmAssistant.db.session
end

local function Changed()
	local registry = LibStub('AceConfigRegistry-3.0', true)
	if registry then
		registry:NotifyChange('LibsFarmAssistant')
	end
	LibsFarmAssistant:SendMessage('LIBSFA_SETTINGS_CHANGED')
	LibsFarmAssistant:UpdateDisplay()
end

---@param key string
---@param value boolean
local function SetAutoPause(key, value)
	SessionSettings()[key] = value
	LibsFarmAssistant.SessionManager:UpdateAutoPause()
	Changed()
end

function Window:CreateSettings()
	if self.settingsPanel then
		return self.settingsPanel
	end
	local panel = CreateFrame('Frame', 'LibsFarmAssistantQuickSettings', self.frame)
	panel:SetFrameStrata('DIALOG')
	panel:SetWidth(WIDTH)
	panel:EnableMouse(true)
	panel:SetClampedToScreen(true)
	T.Fill(panel, { 0.06, 0.065, 0.075, 0.97 })
	T.Border(panel, C.lineStrong, 'OVERLAY')
	self.settingsPanel = panel

	local title = T.Text(panel, 12, C.text)
	title:SetPoint('TOPLEFT', 12, -12)
	title:SetText('Tracking')

	local startLabel = T.Text(panel, 11, C.muted)
	startLabel:SetPoint('TOPLEFT', title, 'BOTTOMLEFT', 0, -12)
	startLabel:SetText('Start tracking')

	local start = W.Segmented(panel, START_ITEMS, function(key)
		SessionSettings().startMode = key
		Changed()
	end)
	start:SetPoint('TOPLEFT', startLabel, 'BOTTOMLEFT', 0, -6)
	panel.start = start

	local note = T.Text(panel, 10, C.faint)
	note:SetPoint('TOPLEFT', start, 'BOTTOMLEFT', 0, -5)
	note:SetPoint('RIGHT', panel, 'RIGHT', -12, 0)
	note:SetJustifyH('LEFT')
	note:SetText('Takes effect the next time you log in.')

	local resting = W.Check(panel, 'Pause while resting', function(checked)
		SetAutoPause('pauseWhenResting', checked)
	end, { 'Pause while resting', 'Stop the clock in cities and inns. It resumes when you leave.' })
	resting:SetPoint('TOPLEFT', note, 'BOTTOMLEFT', 0, -12)
	panel.resting = resting

	local away = W.Check(panel, 'Pause while away', function(checked)
		SetAutoPause('pauseWhenAFK', checked)
	end, { 'Pause while away', 'Stop the clock while you are flagged away. It resumes when you are back.' })
	away:SetPoint('TOPLEFT', resting, 'BOTTOMLEFT', 0, -4)
	panel.away = away

	local rule = T.Rule(panel)
	rule:SetPoint('TOPLEFT', away, 'BOTTOMLEFT', 0, -10)
	rule:SetPoint('RIGHT', panel, 'RIGHT', -12, 0)

	local all = W.Button(panel, 'All settings', {
		quiet = true,
		onClick = function()
			panel:Hide()
			self:Open('settings')
		end,
	})
	all:SetPoint('TOPRIGHT', rule, 'BOTTOMRIGHT', 0, -8)

	-- title, label, switch, note, two checks, rule and button, with their gaps
	panel:SetHeight(12 + 14 + 12 + 14 + 6 + 22 + 5 + 12 + 12 + 18 + 4 + 18 + 10 + 8 + 22 + 10)

	panel:SetScript('OnShow', function()
		self:RefreshSettings()
	end)
	panel:SetScript('OnEvent', function(p)
		if p:IsShown() and not p:IsMouseOver() and not (self.settingsButton and self.settingsButton:IsMouseOver()) then
			p:Hide()
		end
	end)
	if not C_EventUtils or not C_EventUtils.IsEventValid or C_EventUtils.IsEventValid('GLOBAL_MOUSE_DOWN') then
		panel:RegisterEvent('GLOBAL_MOUSE_DOWN')
	end
	tinsert(UISpecialFrames, 'LibsFarmAssistantQuickSettings')
	panel:Hide()
	return panel
end

---Shows the settings under the header button, or hides them when they are open.
function Window:ToggleSettings()
	local panel = self:CreateSettings()
	if panel:IsShown() then
		panel:Hide()
		return
	end
	W.CloseMenu()
	panel:ClearAllPoints()
	panel:SetPoint('TOPRIGHT', self.settingsButton, 'BOTTOMRIGHT', 0, -4)
	panel:Show()
end

function Window:RefreshSettings()
	local panel = self.settingsPanel
	if not panel or not panel:IsShown() then
		return
	end
	local settings = SessionSettings()
	panel.start:Select(settings.startMode or 'login')
	panel.resting:SetChecked(settings.pauseWhenResting)
	panel.away:SetChecked(settings.pauseWhenAFK)
end
