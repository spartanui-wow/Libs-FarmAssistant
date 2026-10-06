---@class LibsFarmAssistant
local LibsFarmAssistant = LibStub('AceAddon-3.0'):GetAddon('Libs-FarmAssistant')

-- The main window: a header with the running clock and one time switch (Session, Today, Week,
-- Month, All) that every page reads, a left navigation, and the page area.

---@class LibsFarmAssistant.Window : AceModule, AceEvent-3.0, AceTimer-3.0
local Window = LibsFarmAssistant:NewModule('Window')
LibsFarmAssistant.Window = Window

---@class FarmPage
---@field key string
---@field title string
---@field icon string
---@field Create fun(self: FarmPage, parent: Frame, window: table)
---@field Refresh fun(self: FarmPage, bucket: FarmBucket, range: string)
---@field Count fun(self: FarmPage, bucket: FarmBucket): number|nil

---@type table<string, FarmPage>
LibsFarmAssistant.Pages = LibsFarmAssistant.Pages or {}

local T = LibsFarmAssistant.Theme
local W = LibsFarmAssistant.Widgets
local C = T.color
local Ledger = LibsFarmAssistant.Ledger
local Format = LibsFarmAssistant.Format

local PAGE_ORDER = { 'overview', 'loot', 'hunts', 'sources', 'progress', 'history', 'settings' }
local RANGES = {
	{ key = 'session', label = 'Session', tooltip = 'Since this session started.' },
	{ key = 'today', label = 'Today' },
	{ key = 'week', label = 'Week', tooltip = 'Since the weekly reset.' },
	{ key = 'month', label = 'Month' },
	{ key = 'all', label = 'All', tooltip = 'Everything this character has farmed.' },
}
Window.RANGE_LABEL = {
	session = 'this session',
	today = 'today',
	week = 'this week',
	month = 'this month',
	all = 'all time',
}

StaticPopupDialogs['LIBSFA_NEW_SESSION'] = {
	text = 'Start a new session? This one is saved to your history.',
	button1 = 'New session',
	button2 = CANCEL or 'Cancel',
	OnAccept = function()
		LibsFarmAssistant:ResetSession()
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
}

function Window:OnEnable()
	self:RegisterMessage('LIBSFA_UPDATE', 'OnUpdateMessage')
	self:RegisterMessage('LIBSFA_SESSION_STATE', 'UpdateHeader')
	self:RegisterMessage('LIBSFA_SESSION_STARTED', 'OnUpdateMessage')
	self:RegisterMessage('LIBSFA_HUNTS_CHANGED', 'OnUpdateMessage')
	self:RegisterMessage('LIBSFA_HUNTS_UPDATED', 'OnUpdateMessage')
	self:RegisterMessage('LIBSFA_ITEM_LOADED', 'OnUpdateMessage')
	self:RegisterMessage('LIBSFA_SETTINGS_CHANGED', 'OnUpdateMessage')
end

---@return table settings
local function Settings()
	return LibsFarmAssistant.db.window
end

---@return FarmBucket
function Window:Bucket()
	return Ledger:Window(self.range or 'session')
end

----------------------------------------------------------------------------------------------------
-- Construction
----------------------------------------------------------------------------------------------------

function Window:Create()
	if self.frame then
		return self.frame
	end
	local settings = Settings()
	self.range = settings.range or 'session'

	local frame = _G.LibsFarmAssistantWindow or CreateFrame('Frame', 'LibsFarmAssistantWindow', UIParent)
	self.frame = frame
	frame:Hide()
	frame:SetFrameStrata('MEDIUM')
	frame:SetToplevel(true)
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:SetResizable(true)
	frame:EnableMouse(true)
	if frame.SetDontSavePosition then
		frame:SetDontSavePosition(true)
	end
	if frame.SetResizeBounds then
		frame:SetResizeBounds(760, 460, 1400, 1000)
	elseif frame.SetMinResize then
		frame:SetMinResize(760, 460)
	end
	frame:SetScale(settings.scale or 1)
	tinsert(UISpecialFrames, 'LibsFarmAssistantWindow')

	T.Fill(frame, C.plate)
	T.Border(frame, C.lineStrong, 'OVERLAY')

	self:CreateHeader()
	self:CreateNav()
	self:CreateFooter()

	local content = CreateFrame('Frame', nil, frame)
	content:SetPoint('TOPLEFT', self.nav, 'TOPRIGHT', T.size.pad, -10)
	content:SetPoint('BOTTOMRIGHT', self.footer, 'TOPRIGHT', -T.size.pad, 8)
	if content.SetClipsChildren then
		content:SetClipsChildren(true)
	end
	self.content = content
	self.pageFrames = {}

	local grip = CreateFrame('Button', nil, frame)
	grip:SetSize(14, 14)
	grip:SetPoint('BOTTOMRIGHT', -2, 2)
	grip:SetFrameLevel(frame:GetFrameLevel() + 10)
	for i, len in ipairs({ 10, 6 }) do
		local line = grip:CreateTexture(nil, 'OVERLAY')
		line:SetTexture(T.WHITE)
		T.Tint(line, C.faint)
		line:SetSize(len, 1)
		line:SetPoint('CENTER', grip, 'CENTER', 1 + i * 1.5, -1 - i * 1.5)
		if line.SetRotation then
			line:SetRotation(math.pi / 4)
		end
	end
	grip:SetScript('OnMouseDown', function()
		frame:StartSizing('BOTTOMRIGHT')
	end)
	grip:SetScript('OnMouseUp', function()
		frame:StopMovingOrSizing()
		self:SavePosition()
		self:Refresh()
	end)

	frame:SetScript('OnShow', function()
		self:UpdateHeader()
		self:Refresh()
		if not self.ticker then
			self.ticker = self:ScheduleRepeatingTimer('UpdateClock', 1)
		end
	end)
	frame:SetScript('OnHide', function()
		self:SavePosition()
		if self.ticker then
			self:CancelTimer(self.ticker)
			self.ticker = nil
		end
	end)
	frame:SetScript('OnSizeChanged', function()
		if frame:IsShown() then
			self:Refresh()
		end
	end)

	self:RestorePosition()
	self:ShowPage(settings.page or 'overview', true)
	return frame
end

function Window:CreateHeader()
	local frame = self.frame
	local header = CreateFrame('Frame', nil, frame)
	header:SetHeight(T.size.header)
	header:SetPoint('TOPLEFT')
	header:SetPoint('TOPRIGHT')
	T.Fill(header, C.plate2)
	local rule = T.Rule(header)
	rule:SetPoint('BOTTOMLEFT')
	rule:SetPoint('BOTTOMRIGHT')
	header:EnableMouse(true)
	header:RegisterForDrag('LeftButton')
	header:SetScript('OnDragStart', function()
		frame:StartMoving()
	end)
	header:SetScript('OnDragStop', function()
		frame:StopMovingOrSizing()
		self:SavePosition()
	end)
	self.header = header

	local title = T.Text(header, 12, C.text)
	title:SetPoint('LEFT', 12, 0)
	title:SetText('Farm Assistant')

	local dot = header:CreateTexture(nil, 'ARTWORK')
	dot:SetTexture(T.WHITE)
	dot:SetSize(7, 7)
	dot:SetPoint('LEFT', header, 'LEFT', T.size.nav_width + 4, 0)
	self.dot = dot

	local clock = T.Text(header, 13, C.text, 'figures')
	clock:SetPoint('LEFT', dot, 'RIGHT', 6, 0)
	self.clock = clock

	local state = T.Text(header, 11, C.muted)
	state:SetPoint('LEFT', clock, 'RIGHT', 6, 0)
	self.state = state

	local close = W.IconButton(header, 'close', { 'Close' })
	close:SetPoint('RIGHT', -6, 0)
	close:SetScript('OnClick', function()
		frame:Hide()
	end)

	local settings = W.IconButton(header, 'settings', { 'Tracking settings', 'When tracking starts, and pausing while resting or away.' })
	settings:SetPoint('RIGHT', close, 'LEFT', -4, 0)
	settings:SetScript('OnClick', function()
		self:ToggleSettings()
	end)
	self.settingsButton = settings

	local tracker = W.IconButton(header, 'tracker', { 'Compact tracker', 'Show or hide the small always-on tracker.' })
	tracker:SetPoint('RIGHT', settings, 'LEFT', -4, 0)
	tracker:SetScript('OnClick', function()
		LibsFarmAssistant:ToggleTracker()
	end)

	local new = W.IconButton(header, 'plus', { 'New session', 'Save this session to your history and start counting again.' })
	new:SetPoint('RIGHT', tracker, 'LEFT', -4, 0)
	new:SetScript('OnClick', function()
		StaticPopup_Show('LIBSFA_NEW_SESSION')
	end)

	local pause = W.IconButton(header, 'pause')
	pause:SetPoint('RIGHT', new, 'LEFT', -4, 0)
	pause:SetScript('OnClick', function()
		LibsFarmAssistant:ToggleSession()
	end)
	pause:HookScript('OnEnter', function(btn)
		local active = LibsFarmAssistant:IsSessionActive()
		W.ShowTooltip(btn, active and 'Pause' or 'Resume', active and 'Stop the clock and stop counting until you resume.' or 'Start counting again.')
	end)
	pause:HookScript('OnLeave', function()
		GameTooltip:Hide()
	end)
	self.pauseButton = pause

	local ranges = W.Segmented(header, RANGES, function(key)
		self:SetRange(key)
	end)
	ranges:SetPoint('RIGHT', pause, 'LEFT', -10, 0)
	ranges:Select(self.range)
	self.ranges = ranges
end

local NAV_ICONS = {
	overview = 'Interface\\Icons\\INV_Misc_Coin_02',
	loot = 'Interface\\Icons\\INV_Misc_Bag_10',
	hunts = 'Interface\\Icons\\Ability_Hunter_SniperShot',
	sources = 'Interface\\Icons\\INV_Misc_Bone_HumanSkull_01',
	progress = 'Interface\\Icons\\INV_Scroll_03',
	history = 'Interface\\Icons\\INV_Misc_PocketWatch_01',
}

function Window:CreateNav()
	local frame = self.frame
	local nav = CreateFrame('Frame', nil, frame)
	nav:SetWidth(T.size.nav_width)
	nav:SetPoint('TOPLEFT', self.header, 'BOTTOMLEFT')
	nav:SetPoint('BOTTOMLEFT', frame, 'BOTTOMLEFT', 0, T.size.footer)
	local edge = nav:CreateTexture(nil, 'BORDER')
	edge:SetTexture(T.WHITE)
	T.Tint(edge, C.line)
	edge:SetWidth(T.Pixel(nav))
	edge:SetPoint('TOPRIGHT')
	edge:SetPoint('BOTTOMRIGHT')
	self.nav = nav
	self.navButtons = {}

	for i, key in ipairs(PAGE_ORDER) do
		local page = LibsFarmAssistant.Pages[key]
		local btn = CreateFrame('Button', nil, nav)
		btn:SetHeight(26)
		btn:SetPoint('TOPLEFT', nav, 'TOPLEFT', 0, -6 - (i - 1) * 26)
		btn:SetPoint('RIGHT', nav, 'RIGHT', -1, 0)
		btn.bg = T.Fill(btn, { 0, 0, 0, 0 })
		btn.icon = T.Icon(btn, 16)
		btn.icon:SetPoint('LEFT', 10, 0)
		btn.icon:SetTexture(page and page.icon or NAV_ICONS[key])
		btn.label = T.Text(btn, T.size.nav, C.muted)
		btn.label:SetPoint('LEFT', btn.icon, 'RIGHT', 8, 0)
		btn.label:SetText(page and page.title or key)
		btn.count = T.Text(btn, 11, C.faint, 'figures')
		btn.count:SetPoint('RIGHT', -10, 0)
		btn.key = key
		btn:SetScript('OnClick', function()
			self:ShowPage(key)
		end)
		btn:SetScript('OnEnter', function(b)
			b.hover = true
			self:PaintNav()
		end)
		btn:SetScript('OnLeave', function(b)
			b.hover = false
			self:PaintNav()
		end)
		self.navButtons[key] = btn
	end

	local who = T.Text(nav, 11, C.muted)
	who:SetPoint('BOTTOMLEFT', 10, 24)
	who:SetPoint('RIGHT', -8, 0)
	self.who = who
	local zone = T.Text(nav, 10, C.faint)
	zone:SetPoint('TOPLEFT', who, 'BOTTOMLEFT', 0, -3)
	zone:SetPoint('RIGHT', -8, 0)
	self.zone = zone
	local rule = T.Rule(nav)
	rule:SetPoint('BOTTOMLEFT', nav, 'BOTTOMLEFT', 0, 46)
	rule:SetPoint('RIGHT', nav, 'RIGHT', -1, 0)
end

function Window:CreateFooter()
	local frame = self.frame
	local footer = CreateFrame('Frame', nil, frame)
	footer:SetHeight(T.size.footer)
	footer:SetPoint('BOTTOMLEFT')
	footer:SetPoint('BOTTOMRIGHT')
	local rule = T.Rule(footer)
	rule:SetPoint('TOPLEFT')
	rule:SetPoint('TOPRIGHT')
	self.footer = footer

	local right = T.Text(footer, 10, C.faint)
	right:SetPoint('RIGHT', -22, 0)
	right:SetJustifyH('RIGHT')
	self.footerRight = right
	local left = T.Text(footer, 10, C.faint)
	left:SetPoint('LEFT', 12, 0)
	left:SetPoint('RIGHT', right, 'LEFT', -12, 0)
	self.footerLeft = left
end

----------------------------------------------------------------------------------------------------
-- State
----------------------------------------------------------------------------------------------------

function Window:SavePosition()
	if not self.frame then
		return
	end
	local settings = Settings()
	local point, _, relativePoint, x, y = self.frame:GetPoint(1)
	if point then
		settings.point, settings.relativePoint, settings.x, settings.y = point, relativePoint, x, y
	end
	local width, height = self.frame:GetSize()
	if width and width > 0 then
		settings.width, settings.height = width, height
	end
end

function Window:RestorePosition()
	local settings = Settings()
	local frame = self.frame
	frame:ClearAllPoints()
	frame:SetPoint(settings.point or 'CENTER', UIParent, settings.relativePoint or settings.point or 'CENTER', settings.x or 0, settings.y or 0)
	frame:SetSize(settings.width or 780, settings.height or 500)
end

---@param key string
function Window:SetRange(key)
	self.range = key
	Settings().range = key
	if self.ranges then
		self.ranges:Select(key)
	end
	self:Refresh()
end

---@param key string
---@param skipRefresh? boolean
function Window:ShowPage(key, skipRefresh)
	if not LibsFarmAssistant.Pages[key] then
		key = 'overview'
	end
	self:Create()
	self.page = key
	Settings().page = key

	local page = LibsFarmAssistant.Pages[key]
	if not self.pageFrames[key] then
		local pageFrame = CreateFrame('Frame', nil, self.content)
		pageFrame:SetAllPoints(self.content)
		page.frame = pageFrame
		page:Create(pageFrame, self)
		self.pageFrames[key] = pageFrame
	end
	for name, pageFrame in pairs(self.pageFrames) do
		pageFrame:SetShown(name == key)
	end
	self:PaintNav()
	if not skipRefresh then
		self:Refresh()
	end
end

function Window:PaintNav()
	for key, btn in pairs(self.navButtons or {}) do
		local on = key == self.page
		T.Tint(btn.bg, on and C.selected or (btn.hover and C.hover or { 0, 0, 0, 0 }))
		T.Color(btn.label, (on or btn.hover) and C.text or C.muted)
	end
end

function Window:UpdateClock()
	if not self.frame or not self.frame:IsShown() then
		return
	end
	self.clock:SetText(Format.Clock(LibsFarmAssistant:GetSessionDuration()))
end

function Window:UpdateHeader()
	if not self.frame then
		return
	end
	local active = LibsFarmAssistant:IsSessionActive()
	T.Tint(self.dot, active and C.good or C.warn)
	self.state:SetText(LibsFarmAssistant.SessionManager:StateLabel())
	self.pauseButton:SetGlyph(active and 'pause' or 'resume')
	self:UpdateClock()
end

function Window:UpdateNav(bucket)
	for key, btn in pairs(self.navButtons) do
		local page = LibsFarmAssistant.Pages[key]
		local count = page and page.Count and page:Count(bucket)
		btn.count:SetText(count and count > 0 and Format.Short(count) or '')
	end

	local name = UnitName('player') or ''
	local _, class = UnitClass('player')
	local color = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
	if color then
		self.who:SetTextColor(color.r, color.g, color.b)
	end
	self.who:SetText(name)
	local session = Ledger:Session()
	self.zone:SetText(LibsFarmAssistant.Compat.CurrentZone() or session.zone or '')
end

function Window:UpdateFooter()
	local tracking = LibsFarmAssistant.db.tracking
	local mode
	if tracking.mode == 'selected' then
		mode = 'Tracking chosen items only'
	else
		local lowest
		for q = 0, 5 do
			if tracking.qualities[q] ~= false then
				lowest = q
				break
			end
		end
		local name = lowest and _G['ITEM_QUALITY' .. lowest .. '_DESC'] or 'any'
		mode = lowest == 0 and 'Tracking every item' or ('Tracking ' .. name .. ' and better')
	end
	self.footerLeft:SetText(mode .. '    ' .. LibsFarmAssistant.Pricing:Describe())

	local best, bestSession = Ledger:BestSession()
	if best and bestSession then
		self.footerRight:SetText(string.format('Best session: %s /hr, %s', Format.Money(best), date('%b %d', bestSession.start)))
	else
		self.footerRight:SetText('')
	end
end

---Redraws the header, nav counts, footer and the visible page.
function Window:Refresh()
	if not self.frame or not self.frame:IsShown() then
		return
	end
	local bucket = self:Bucket()
	self:UpdateHeader()
	self:UpdateNav(bucket)
	self:UpdateFooter()
	self:RefreshSettings()
	local page = LibsFarmAssistant.Pages[self.page]
	if page and page.Refresh then
		page:Refresh(bucket, self.range)
	end
end

function Window:OnUpdateMessage()
	self:Refresh()
end

---@param page? string
function Window:Toggle(page)
	local frame = self:Create()
	if frame:IsShown() and (not page or page == self.page) then
		frame:Hide()
		return
	end
	if page then
		self:ShowPage(page, true)
	end
	frame:Show()
end

---@param page string
function Window:Open(page)
	local frame = self:Create()
	self:ShowPage(page, true)
	if frame:IsShown() then
		self:Refresh()
	else
		frame:Show()
	end
end
