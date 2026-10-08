---@class LibsFarmAssistant
local LibsFarmAssistant = LibStub('AceAddon-3.0'):GetAddon('Libs-FarmAssistant')

-- The broker tooltip: this session at a glance, in sections the player can fold. Every line opens
-- the window on the page that shows it in full; item lines show the item beside the tooltip and
-- link it on shift-click. The same content can also be written into a plain GameTooltip.

local T = LibsFarmAssistant.Theme
local W = LibsFarmAssistant.Widgets
local C = T.color
local Ledger = LibsFarmAssistant.Ledger
local Format = LibsFarmAssistant.Format
local Compat = LibsFarmAssistant.Compat
local QTip = LibStub('LibQTip-2.0', true)

---@class LibsFarmAssistant.BrokerTooltip
local Tip = {}
LibsFarmAssistant.BrokerTooltip = Tip

local KEY = 'LibsFarmAssistantBrokerTooltip'
local COLUMNS = 3
local AUTO_HIDE = 0.25
local LIMIT = { loot = 8, drops = 6, sources = 5, hunts = 6, rep = 5, currency = 6 }

local EXPAND = '|TInterface\\Buttons\\UI-PlusButton-Up:14:14|t '
local COLLAPSE = '|TInterface\\Buttons\\UI-MinusButton-Up:14:14|t '

Tip.HINTS = {
	broker = {
		'Click: window   Right-click: pause   Middle-click: tracker',
		'Shift-click: new session   Scroll: change the text shown',
	},
	compartment = {
		'Click: window   Right-click: settings',
	},
}

local function Wrap(text, color)
	return T.Wrap(text, color)
end

local function Icon(texture)
	if not texture then
		return ''
	end
	return '|T' .. texture .. ':14:14:0:0:64:64:5:59:5:59|t '
end

local function ItemLabel(itemID)
	local meta = LibsFarmAssistant.Pricing:Meta(itemID)
	return Icon(Compat.ItemIcon(itemID)) .. Wrap(meta.n or ('Item ' .. itemID), T.quality[meta.q or 1] or T.quality[1])
end

local function PerHourMoney(amount, bucket)
	local rate = Ledger.PerHour(amount, bucket)
	return rate and Wrap(Format.Money(rate) .. ' /hr', C.muted) or ''
end

local function PerHour(amount, bucket)
	local rate = Ledger.PerHour(amount, bucket)
	return rate and Wrap(Format.Rate(rate) .. ' /hr', C.muted) or ''
end

local function Collapsed()
	return LibsFarmAssistant.db.display.collapsed
end

----------------------------------------------------------------------------------------------------
-- Actions
----------------------------------------------------------------------------------------------------

---Opens the window on a page, with the line's item or source selected. When the window's time
---range does not hold that line (the tooltip always shows this session), it switches to Session.
---@param action table
local function Open(action)
	local Window = LibsFarmAssistant.Window
	Window:Create()
	if action.select ~= nil then
		local bucket = Window:Bucket()
		local missing = (action.kind == 'item' and not bucket.items[action.select]) or (action.kind == 'source' and not bucket.sources[action.select])
		if missing and Window.range ~= 'session' then
			Window:SetRange('session')
		end
		local page = LibsFarmAssistant.Pages[action.page]
		if page then
			page.selected = action.select
		end
	end
	Window:Open(action.page)
end

---Places GameTooltip beside the broker tooltip, on the side with more room.
---@param owner Frame
local function AnchorBeside(owner)
	GameTooltip:SetOwner(owner, 'ANCHOR_NONE')
	GameTooltip:ClearAllPoints()
	local x = owner:GetCenter()
	local scale = owner:GetEffectiveScale() / UIParent:GetEffectiveScale()
	if x and x * scale > UIParent:GetWidth() / 2 then
		GameTooltip:SetPoint('TOPRIGHT', owner, 'TOPLEFT', -2, 0)
	else
		GameTooltip:SetPoint('TOPLEFT', owner, 'TOPRIGHT', 2, 0)
	end
end

-- Cell scripts always get their action through LibQTip's script argument, so the handler sees
-- (cell, action, button) whichever copy of the library loaded first.
local function OnCellEnter(_, action)
	local qtip = Tip.qtip
	if not qtip then
		return
	end
	if action.item then
		AnchorBeside(qtip)
		if GameTooltip.SetItemByID then
			GameTooltip:SetItemByID(action.item)
		else
			GameTooltip:SetHyperlink('item:' .. action.item)
		end
		GameTooltip:Show()
	elseif action.currency and GameTooltip.SetCurrencyByID then
		AnchorBeside(qtip)
		GameTooltip:SetCurrencyByID(action.currency)
		GameTooltip:Show()
	end
end

local function OnCellLeave()
	if Tip.qtip and GameTooltip:GetOwner() == Tip.qtip then
		GameTooltip:Hide()
	end
end

local function OnCellClick(_, action, button)
	if action.toggle then
		local collapsed = Collapsed()
		collapsed[action.toggle] = not collapsed[action.toggle] or nil
		Tip:Redraw()
		return
	end
	if action.item and W.ModifiedItemClick(action.item) then
		return
	end
	if button and button ~= 'LeftButton' then
		return
	end
	if action.run then
		action.run()
		Tip:Redraw()
		return
	end
	if action.page then
		Tip:Hide()
		Open(action)
	end
end

----------------------------------------------------------------------------------------------------
-- Writers: the content is written once, through one of these
----------------------------------------------------------------------------------------------------

---@class FarmTooltipWriter
local QTipWriter = {}
QTipWriter.__index = QTipWriter

local function Bind(cell, action)
	if action then
		cell:SetScript('OnEnter', OnCellEnter, action)
		cell:SetScript('OnLeave', OnCellLeave, action)
		cell:SetScript('OnMouseUp', OnCellClick, action)
	end
end

---@return table cell The right cell, so the clock can tick in place
function QTipWriter:Title(left, right)
	local row = self.tip:AddHeadingRow(left)
	local cell = row:GetCell(2)
	cell:SetText(right)
	cell:SetColSpan(COLUMNS - 1)
	return cell
end

function QTipWriter:Line(left, mid, right, action)
	local row = self.tip:AddRow(left or '', mid or '', right or '')
	for i = 1, COLUMNS do
		Bind(row:GetCell(i), action)
	end
end

function QTipWriter:Wide(text, action)
	local row = self.tip:AddRow(text)
	local cell = row:GetCell(1)
	cell:SetColSpan(COLUMNS)
	Bind(cell, action)
end

---@return boolean open
function QTipWriter:Section(key, title, aside)
	local open = not Collapsed()[key]
	self.tip:AddSeparator(6, 0, 0, 0, 0)
	local row = self.tip:AddRow((open and COLLAPSE or EXPAND) .. Wrap(title, C.gold), '', aside or '')
	row:SetColor(1, 1, 1, 0.06)
	for i = 1, COLUMNS do
		Bind(row:GetCell(i), { toggle = key })
	end
	return open
end

---Two clickable words on one row, left and right.
function QTipWriter:Buttons(left, leftAction, right, rightAction)
	self.tip:AddSeparator(6, 0, 0, 0, 0)
	local row = self.tip:AddRow(left, '', right)
	Bind(row:GetCell(1), leftAction)
	Bind(row:GetCell(3), rightAction)
end

function QTipWriter:Gap()
	self.tip:AddSeparator(6, 0, 0, 0, 0)
end

---@class FarmTooltipWriter
local GameTooltipWriter = {}
GameTooltipWriter.__index = GameTooltipWriter

function GameTooltipWriter:Title(left, right)
	self.tip:AddDoubleLine(left, right, 1, 1, 1, 1, 1, 1)
end

function GameTooltipWriter:Line(left, mid, right)
	if mid and mid ~= '' and right and right ~= '' then
		mid = mid .. '   ' .. right
	elseif not mid or mid == '' then
		mid = right
	end
	self.tip:AddDoubleLine(left or '', mid or '', 1, 1, 1, 1, 1, 1)
end

function GameTooltipWriter:Wide(text)
	self.tip:AddLine(text, 1, 1, 1)
end

function GameTooltipWriter:Section(_, title, aside)
	self.tip:AddLine(' ')
	self.tip:AddDoubleLine(Wrap(title, C.gold), aside or '', 1, 1, 1, 1, 1, 1)
	return true
end

function GameTooltipWriter:Buttons() end

function GameTooltipWriter:Gap()
	self.tip:AddLine(' ')
end

----------------------------------------------------------------------------------------------------
-- Content
----------------------------------------------------------------------------------------------------

local function HeaderRight()
	local A = LibsFarmAssistant
	local state = A:IsSessionActive() and Wrap('Farming', C.good) or Wrap(A.SessionManager:StateText(), C.warn)
	return state .. '   ' .. Wrap(Format.Clock(A:GetSessionDuration()), C.text)
end

---@param bucket FarmBucket
---@return boolean
local function IsEmpty(bucket)
	return bucket.time < 1
		and next(bucket.items) == nil
		and Ledger.Money(bucket) == 0
		and bucket.kills == 0
		and bucket.xp == 0
		and next(bucket.rep) == nil
		and next(bucket.currencies) == nil
		and bucket.honor == 0
end

---@param w FarmTooltipWriter
local function More(w, count, shown, page)
	if count > shown then
		w:Wide(Wrap(string.format('and %d more', count - shown), C.faint), { page = page })
	end
end

local function Summary(w, bucket)
	local looted = Ledger.Money(bucket, 'loot')
	local quest = Ledger.Money(bucket, 'quest')
	local items = Ledger.ItemValue(bucket)
	local total = looted + quest + items
	local action = { page = 'overview' }
	local rate = Ledger.PerHour(total, bucket)
	w:Line(Wrap('Total value', C.text), Wrap(Format.Money(total), C.gold), rate and Wrap(Format.Money(rate) .. ' /hr', C.gold) or '', action)
	if looted > 0 then
		w:Line(Wrap('Gold looted', C.muted), Format.Money(looted), PerHourMoney(looted, bucket), action)
	end
	if quest > 0 then
		w:Line(Wrap('Quest gold', C.muted), Format.Money(quest), PerHourMoney(quest, bucket), action)
	end
	if items > 0 then
		w:Line(Wrap('Item value', C.muted), Format.Money(items), PerHourMoney(items, bucket), action)
	end
	if bucket.kills > 0 then
		w:Line(Wrap('Kills', C.muted), Format.Number(bucket.kills), PerHour(bucket.kills, bucket), action)
	end
end

local function TopLoot(w, bucket)
	local rows = W.ItemRows(bucket)
	if #rows == 0 then
		return
	end
	table.sort(rows, function(a, b)
		if a.value ~= b.value then
			return a.value > b.value
		end
		if a.count ~= b.count then
			return a.count > b.count
		end
		return a.id < b.id
	end)
	local total = Ledger.ItemCounts(bucket)
	if not w:Section('loot', 'Top loot', Format.Number(total) .. ' items') then
		return
	end
	local shown = math.min(LIMIT.loot, #rows)
	for i = 1, shown do
		local row = rows[i]
		w:Line(ItemLabel(row.id), 'x' .. Format.Number(row.count), row.value > 0 and Format.Money(row.value) or '', { page = 'loot', kind = 'item', select = row.id, item = row.id })
	end
	More(w, #rows, shown, 'loot')
end

---The best rate each uncommon-or-better (or hunted) item dropped at, and from where.
---@param bucket FarmBucket
---@return table[]
function Tip.DropRows(bucket)
	local Pricing = LibsFarmAssistant.Pricing
	local Hunts = LibsFarmAssistant.Hunts
	local best = {}
	for key, stats in pairs(bucket.sources) do
		local tries = key ~= 'q' and Ledger.Attempts(key, stats) or 0
		if tries > 0 then
			for itemID, drops in pairs(stats.drops) do
				local quality = Pricing:Meta(itemID).q or 1
				if quality >= 2 or Hunts:Get(itemID) then
					local rate = math.min(1, drops / tries)
					local current = best[itemID]
					if not current or rate > current.rate then
						best[itemID] = { id = itemID, key = key, rate = rate, quality = quality }
					end
				end
			end
		end
	end
	local rows = {}
	for _, row in pairs(best) do
		rows[#rows + 1] = row
	end
	table.sort(rows, function(a, b)
		if a.quality ~= b.quality then
			return a.quality > b.quality
		end
		if a.rate ~= b.rate then
			return a.rate < b.rate
		end
		return a.id < b.id
	end)
	return rows
end

local function Drops(w, bucket)
	local rows = Tip.DropRows(bucket)
	if #rows == 0 or not w:Section('drops', 'Drop rates', 'best source') then
		return
	end
	local shown = math.min(LIMIT.drops, #rows)
	for i = 1, shown do
		local row = rows[i]
		w:Line(ItemLabel(row.id), Wrap(Ledger.SourceName(row.key), C.muted), Format.Odds(row.rate), { page = 'loot', kind = 'item', select = row.id, item = row.id })
	end
	More(w, #rows, shown, 'loot')
end

local function Sources(w, bucket)
	local page = LibsFarmAssistant.Pages.sources
	local rows = {}
	for key, stats in pairs(bucket.sources) do
		if key ~= 'q' then
			rows[#rows + 1] = { key = key, tries = Ledger.Attempts(key, stats), value = page.SourceValue(key, stats) }
		end
	end
	if #rows == 0 then
		return
	end
	table.sort(rows, function(a, b)
		if a.value ~= b.value then
			return a.value > b.value
		end
		if a.tries ~= b.tries then
			return a.tries > b.tries
		end
		return a.key < b.key
	end)
	if not w:Section('sources', 'Mobs and nodes', Format.Number(#rows) .. (#rows == 1 and ' source' or ' sources')) then
		return
	end
	local shown = math.min(LIMIT.sources, #rows)
	for i = 1, shown do
		local row = rows[i]
		local word = page.KIND_WORD[Ledger.SourceKind(row.key)] or 'tries'
		local each = row.tries > 0 and row.value > 0 and (Format.Money(row.value / row.tries) .. ' each') or ''
		w:Line(Ledger.SourceName(row.key), Wrap(Format.Number(row.tries) .. ' ' .. word, C.muted), each, { page = 'sources', kind = 'source', select = row.key })
	end
	More(w, #rows, shown, 'sources')
end

local function HuntsSection(w)
	local Hunts = LibsFarmAssistant.Hunts
	local hunts = {}
	for _, hunt in ipairs(Hunts:List()) do
		if not hunt.paused and not Hunts:IsCollected(hunt) then
			hunts[#hunts + 1] = hunt
		end
	end
	if #hunts == 0 or not w:Section('hunts', 'Hunts', Format.Number(#hunts) .. ' active') then
		return
	end
	local shown = math.min(LIMIT.hunts, #hunts)
	for i = 1, shown do
		local hunt = hunts[i]
		local attempts = hunt.attempts or 0
		local anyKill = hunt.mode == 'any' or not Hunts:HasSources(hunt)
		local word = attempts == 1 and 'attempt' or (anyKill and 'kills' or 'attempts')
		local right
		local status, reset = LibsFarmAssistant.Lockouts:MyStatus(hunt)
		if status == 'done' and reset then
			right = Wrap('saved ' .. Format.Duration(reset - time()), C.muted)
		elseif hunt.chance then
			local byNow = Hunts.ChanceByNow(hunt.chance, attempts)
			right = Wrap(Format.Odds(hunt.chance), C.muted) .. '  ' .. Wrap(Format.Percent(byNow) .. ' by now', W.LuckColor(byNow))
		else
			right = Wrap(Format.Duration(hunt.time or 0), C.muted)
		end
		w:Line(ItemLabel(hunt.id), Format.Number(attempts) .. ' ' .. Wrap(word, C.muted), right, { page = 'hunts', select = hunt.id, item = hunt.id })
	end
	More(w, #hunts, shown, 'hunts')
end

local function Reputation(w, bucket)
	local gains = LibsFarmAssistant.ReputationTracker:Gains(bucket)
	if #gains == 0 or not w:Section('rep', 'Reputation', '+' .. Format.Number(Ledger.RepTotal(bucket))) then
		return
	end
	local shown = math.min(LIMIT.rep, #gains)
	for i = 1, shown do
		local gain = gains[i]
		w:Line(gain.progress.name, Wrap('+' .. Format.Number(gain.gained), C.good), Wrap(W.RepPace(gain), W.StandingColor(gain.progress)), { page = 'progress' })
	end
	More(w, #gains, shown, 'progress')
end

local function Currency(w, bucket)
	local rows = {}
	for currencyID, amount in pairs(bucket.currencies) do
		local name, icon = Compat.CurrencyInfo(currencyID)
		rows[#rows + 1] = { id = currencyID, name = name or ('Currency ' .. currencyID), icon = icon, amount = amount }
	end
	table.sort(rows, function(a, b)
		if a.amount ~= b.amount then
			return a.amount > b.amount
		end
		return a.id < b.id
	end)
	if bucket.honor > 0 then
		table.insert(rows, 1, { name = HONOR or 'Honor', icon = 'Interface\\Icons\\INV_Misc_Coin_17', amount = bucket.honor })
	end
	if #rows == 0 or not w:Section('currency', 'Currency', '') then
		return
	end
	local shown = math.min(LIMIT.currency, #rows)
	for i = 1, shown do
		local row = rows[i]
		w:Line(Icon(row.icon) .. row.name, Wrap('+' .. Format.Number(row.amount), C.good), PerHour(row.amount, bucket), { page = 'progress', currency = row.id })
	end
	More(w, #rows, shown, 'progress')
end

local function Experience(w, bucket)
	local XP = LibsFarmAssistant.ExperienceTracker
	local status = XP:Status()
	if bucket.xp <= 0 or not status.canGain then
		return
	end
	if not w:Section('xp', 'Experience', 'Level ' .. status.level .. '  ' .. Format.Percent(status.current / status.max)) then
		return
	end
	local action = { page = 'progress' }
	w:Line(Wrap('Gained', C.muted), Format.Number(bucket.xp), PerHour(bucket.xp, bucket), action)
	local seconds, kills = XP:TimeToLevel(bucket)
	if seconds then
		w:Line(Wrap('Next level in', C.muted), Format.Duration(seconds), '', action)
	end
	local perKill = XP:PerKill()
	if perKill then
		w:Line(Wrap('Per kill', C.muted), Format.Number(math.floor(perKill + 0.5)), kills and Wrap('about ' .. Format.Number(kills) .. ' kills to level', C.muted) or '', action)
	end
end

local function Goals(w)
	local A = LibsFarmAssistant
	local goals = {}
	for _, goal in ipairs(A.db.goals) do
		if goal.active then
			goals[#goals + 1] = goal
		end
	end
	if #goals == 0 or not w:Section('goals', 'Goals', '') then
		return
	end
	for _, goal in ipairs(goals) do
		local current, target, progress = A.GoalTracker:Progress(goal)
		local eta = A.GoalTracker:ETA(goal)
		local right = ''
		if progress >= 1 then
			right = Wrap('done', C.good)
		elseif eta then
			right = Wrap(Format.Duration(eta), C.muted)
		end
		w:Line(A.GoalTracker:Name(goal), A.GoalTracker:FormatValue(goal, current) .. ' / ' .. A.GoalTracker:FormatValue(goal, target), right)
	end
end

---Writes the whole tooltip.
---@param w FarmTooltipWriter
---@param hints string[]
---@param interactive boolean
---@return table|nil clockCell
function Tip.Build(w, hints, interactive)
	local A = LibsFarmAssistant
	local bucket = Ledger:Session()
	local clockCell = w:Title('Farm Assistant', HeaderRight())
	local zone = Compat.CurrentZone() or bucket.zone
	if zone and zone ~= '' then
		w:Wide(Wrap(zone, C.faint))
	end

	if IsEmpty(bucket) then
		w:Gap()
		w:Wide(Wrap('Nothing farmed yet this session.', C.muted))
		w:Wide(Wrap('Kill, gather, fish or quest and it shows up here.', C.faint))
	else
		w:Gap()
		Summary(w, bucket)
		TopLoot(w, bucket)
		Drops(w, bucket)
		Sources(w, bucket)
	end
	HuntsSection(w)
	Reputation(w, bucket)
	Currency(w, bucket)
	Experience(w, bucket)
	Goals(w)

	w:Buttons(
		Wrap(A:IsSessionActive() and 'Pause tracking' or 'Resume tracking', C.text),
		{
			run = function()
				A:ToggleSession()
			end,
		},
		Wrap('New session', C.text),
		{
			run = function()
				StaticPopup_Show('LIBSFA_NEW_SESSION')
			end,
		}
	)
	w:Gap()
	if interactive then
		w:Wide(Wrap('Click a line to open it. Shift-click an item to link it.', C.faint))
	end
	for _, hint in ipairs(hints or Tip.HINTS.broker) do
		w:Wide(Wrap(hint, C.faint))
	end
	return clockCell
end

----------------------------------------------------------------------------------------------------
-- Showing
----------------------------------------------------------------------------------------------------

local function StopClock()
	if Tip.clockTimer then
		LibsFarmAssistant:CancelTimer(Tip.clockTimer)
		Tip.clockTimer = nil
	end
end

local function OnRelease(_, tooltip)
	if tooltip ~= Tip.qtip then
		return
	end
	if GameTooltip:GetOwner() == tooltip then
		GameTooltip:Hide()
	end
	Tip.qtip = nil
	Tip.clockCell = nil
	StopClock()
end

if QTip and QTip.RegisterCallback then
	QTip.RegisterCallback(Tip, 'OnReleaseTooltip', OnRelease)
end

function Tip:TickClock()
	if not self.qtip or not QTip:IsAcquiredTooltip(KEY) then
		StopClock()
		return
	end
	if self.clockCell then
		self.clockCell:SetText(HeaderRight())
	end
end

---Shows the tooltip at a broker display, minimap button or menu entry.
---@param anchor Frame
---@param hints? string[] Click hints for whatever the tooltip belongs to
function Tip:Show(anchor, hints)
	if not anchor then
		return
	end
	self.anchor = anchor
	self.hints = hints
	if not QTip then
		GameTooltip:SetOwner(anchor, 'ANCHOR_BOTTOMLEFT')
		LibsFarmAssistant:BuildTooltip(GameTooltip, hints)
		return
	end
	if self.qtip then
		QTip:ReleaseTooltip(self.qtip)
	end
	local qtip = QTip:AcquireTooltip(KEY, COLUMNS, 'LEFT', 'RIGHT', 'RIGHT')
	self.qtip = qtip
	qtip:SetMaxHeight(UIParent:GetHeight() * 0.6)
	self.clockCell = Tip.Build(setmetatable({ tip = qtip }, QTipWriter), hints, true)
	qtip:SmartAnchorTo(anchor)
	qtip:SetAutoHideDelay(AUTO_HIDE, anchor)
	qtip:UpdateLayout()
	qtip:Show()
	if not self.clockTimer then
		self.clockTimer = LibsFarmAssistant:ScheduleRepeatingTimer(function()
			Tip:TickClock()
		end, 1)
	end
end

---Draws the open tooltip again in place (after a fold, a click or new data).
function Tip:Redraw()
	if self.qtip and self.anchor then
		self:Show(self.anchor, self.hints)
	end
end

---Redraws on new data, but never under the mouse, so lines do not move while being read.
function Tip:Refresh()
	if self.qtip and not self.qtip:IsMouseOver() then
		self:Redraw()
	end
end

function Tip:Hide()
	if self.qtip then
		QTip:ReleaseTooltip(self.qtip)
	end
end

---@return boolean
function Tip:IsShown()
	return self.qtip ~= nil
end

---Writes the same content into a GameTooltip (for places that hand over one).
---@param tooltip GameTooltip
---@param hints? string[]
function LibsFarmAssistant:BuildTooltip(tooltip, hints)
	Tip.Build(setmetatable({ tip = tooltip }, GameTooltipWriter), hints, false)
	tooltip:Show()
end
