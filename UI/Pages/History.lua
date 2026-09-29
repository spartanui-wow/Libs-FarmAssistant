---@class LibsFarmAssistant
local LibsFarmAssistant = LibStub('AceAddon-3.0'):GetAddon('Libs-FarmAssistant')

-- The last thirty days at a glance, and every past session with its pace.

local T = LibsFarmAssistant.Theme
local W = LibsFarmAssistant.Widgets
local C = T.color
local Ledger = LibsFarmAssistant.Ledger
local Format = LibsFarmAssistant.Format

---@type FarmPage
local Page = { key = 'history', title = 'History', icon = 'Interface\\Icons\\INV_Misc_PocketWatch_01' }
LibsFarmAssistant.Pages.history = Page

local DAYS = 30
local CHART_HEIGHT = 120

local METRICS = {
	{ key = 'value', label = 'Value' },
	{ key = 'time', label = 'Time' },
	{ key = 'kills', label = 'Kills' },
}

---@param bucket FarmBucket|nil
---@param metric string
---@return number
local function Measure(bucket, metric)
	if not bucket then
		return 0
	end
	if metric == 'time' then
		return bucket.time or 0
	elseif metric == 'kills' then
		return bucket.kills or 0
	end
	return Ledger.TotalValue(Ledger.Normalize(bucket))
end

---@param amount number
---@param metric string
---@return string
local function Show(amount, metric)
	if metric == 'time' then
		return Format.Duration(amount)
	elseif metric == 'kills' then
		return Format.Number(amount)
	end
	return Format.Money(amount, true)
end

function Page:Create(parent, window)
	self.window = window
	self.metric = 'value'

	local heading = W.Heading(parent, 'Last 30 days')
	heading:SetPoint('TOPLEFT')
	heading:SetPoint('RIGHT', parent, 'RIGHT', -150, 0)
	self.heading = heading

	local metric = W.Segmented(parent, METRICS, function(key)
		self.metric = key
		self:Refresh(window:Bucket(), window.range)
	end)
	metric:SetPoint('TOPRIGHT')
	metric:Select('value')

	local chart = CreateFrame('Frame', nil, parent)
	chart:SetPoint('TOPLEFT', heading, 'BOTTOMLEFT', 0, -10)
	chart:SetPoint('RIGHT')
	chart:SetHeight(CHART_HEIGHT)
	local base = T.Rule(chart, C.lineStrong)
	base:SetPoint('BOTTOMLEFT')
	base:SetPoint('BOTTOMRIGHT')
	self.chart = chart
	self.bars = {}
	for i = 1, DAYS do
		local bar = CreateFrame('Button', nil, chart)
		bar.fill = bar:CreateTexture(nil, 'ARTWORK')
		bar.fill:SetTexture(T.WHITE)
		bar.fill:SetPoint('BOTTOMLEFT')
		bar.fill:SetPoint('BOTTOMRIGHT')
		bar.hl = T.Fill(bar, { 0, 0, 0, 0 })
		bar:SetScript('OnEnter', function(b)
			T.Tint(b.hl, C.hover)
			if b.day then
				GameTooltip:SetOwner(b, 'ANCHOR_TOP')
				GameTooltip:SetText(date('%A, %b %d', Ledger.DayEpoch(b.day)), 1, 1, 1)
				local bucket = LibsFarmAssistant.char.days[b.day]
				if bucket and (bucket.time or 0) > 0 then
					bucket = Ledger.Normalize(bucket)
					local value = Ledger.TotalValue(bucket)
					GameTooltip:AddDoubleLine('Value', Format.Money(value), C.muted[1], C.muted[2], C.muted[3], 1, 1, 1)
					GameTooltip:AddDoubleLine('Time farming', Format.Duration(bucket.time), C.muted[1], C.muted[2], C.muted[3], 1, 1, 1)
					local rate = Ledger.PerHour(value, bucket)
					if rate then
						GameTooltip:AddDoubleLine('Per hour', Format.Money(rate), C.muted[1], C.muted[2], C.muted[3], 1, 1, 1)
					end
					GameTooltip:AddDoubleLine('Kills', Format.Number(bucket.kills), C.muted[1], C.muted[2], C.muted[3], 1, 1, 1)
				else
					GameTooltip:AddLine('No farming', C.muted[1], C.muted[2], C.muted[3])
				end
				GameTooltip:Show()
			end
		end)
		bar:SetScript('OnLeave', function(b)
			T.Tint(b.hl, { 0, 0, 0, 0 })
			GameTooltip:Hide()
		end)
		self.bars[i] = bar
	end
	chart:SetScript('OnSizeChanged', function()
		self:LayoutBars()
	end)

	local axisLeft = T.Text(parent, 10, C.faint, 'figures')
	axisLeft:SetPoint('TOPLEFT', chart, 'BOTTOMLEFT', 0, -3)
	local axisMid = T.Text(parent, 10, C.faint, 'figures')
	axisMid:SetPoint('TOP', chart, 'BOTTOM', 0, -3)
	local axisRight = T.Text(parent, 10, C.faint, 'figures')
	axisRight:SetPoint('TOPRIGHT', chart, 'BOTTOMRIGHT', 0, -3)
	axisRight:SetText('Today')
	self.axisLeft, self.axisMid = axisLeft, axisMid

	local sessionsHeading = W.Heading(parent, 'Sessions')
	sessionsHeading:SetPoint('TOPLEFT', chart, 'BOTTOMLEFT', 0, -22)
	sessionsHeading:SetPoint('RIGHT')
	self.sessionsHeading = sessionsHeading

	local sessions = W.Table(parent, {
		{
			key = 'start',
			title = 'Started',
			width = 120,
			sort = function(a, b)
				return a.start < b.start
			end,
		},
		{ key = 'zone', title = 'Where', flex = true },
		{
			key = 'time',
			title = 'Time',
			width = 64,
			align = 'RIGHT',
			figures = true,
			sort = function(a, b)
				return a.time < b.time
			end,
		},
		{
			key = 'kills',
			title = 'Kills',
			width = 52,
			align = 'RIGHT',
			figures = true,
			sort = function(a, b)
				return (a.kills or 0) < (b.kills or 0)
			end,
		},
		{
			key = 'value',
			title = 'Value',
			width = 96,
			align = 'RIGHT',
			figures = true,
			sort = function(a, b)
				return (a.value or 0) < (b.value or 0)
			end,
		},
		{
			key = 'rate',
			title = 'Per hour',
			width = 90,
			align = 'RIGHT',
			figures = true,
			sort = function(a, b)
				return a.rate < b.rate
			end,
		},
	}, {
		sortKey = 'start',
		cell = function(row, col)
			if col.key == 'start' then
				return Format.When(row.start), row.current and C.text or C.muted
			elseif col.key == 'zone' then
				return row.zone or '-', C.muted
			elseif col.key == 'time' then
				return Format.Duration(row.time)
			elseif col.key == 'kills' then
				return Format.Number(row.kills or 0), C.muted
			elseif col.key == 'value' then
				return Format.Money(row.value or 0, true)
			end
			return Format.Money(row.rate, true), row.best and C.good or C.text
		end,
		onEnter = function(rowFrame, row)
			GameTooltip:SetOwner(rowFrame, 'ANCHOR_RIGHT')
			GameTooltip:SetText(row.current and 'This session' or Format.When(row.start), 1, 1, 1)
			if row.xp and row.xp > 0 then
				GameTooltip:AddDoubleLine('Experience', Format.Number(row.xp), C.muted[1], C.muted[2], C.muted[3], 1, 1, 1)
			end
			if row.rep and row.rep > 0 then
				GameTooltip:AddDoubleLine('Reputation', Format.Number(row.rep), C.muted[1], C.muted[2], C.muted[3], 1, 1, 1)
			end
			if row.honor and row.honor > 0 then
				GameTooltip:AddDoubleLine('Honor', Format.Number(row.honor), C.muted[1], C.muted[2], C.muted[3], 1, 1, 1)
			end
			if row.loot and row.loot > 0 then
				GameTooltip:AddDoubleLine('Gold looted', Format.Money(row.loot), C.muted[1], C.muted[2], C.muted[3], 1, 1, 1)
			end
			for _, top in ipairs(row.top or {}) do
				local meta = LibsFarmAssistant.Pricing:Meta(top.id)
				local r, g, b = T.QualityRGB(meta.q)
				GameTooltip:AddDoubleLine(meta.n or ('Item ' .. top.id), Format.Number(top.count), r, g, b, 1, 1, 1)
			end
			GameTooltip:Show()
		end,
	})
	sessions:SetPoint('TOPLEFT', sessionsHeading, 'BOTTOMLEFT', 0, -2)
	sessions:SetPoint('BOTTOMRIGHT')
	self.sessions = sessions
end

function Page:LayoutBars()
	local width = self.chart:GetWidth() or 0
	local gap = 3
	local barWidth = math.max(2, (width - gap * (DAYS - 1)) / DAYS)
	for i, bar in ipairs(self.bars) do
		bar:ClearAllPoints()
		bar:SetPoint('BOTTOMLEFT', self.chart, 'BOTTOMLEFT', (i - 1) * (barWidth + gap), 0)
		bar:SetSize(barWidth, CHART_HEIGHT)
	end
end

function Page:Count()
	return #LibsFarmAssistant.char.sessions
end

function Page:Refresh()
	local metric = self.metric
	local days = LibsFarmAssistant.char.days
	local values, peak, total, active = {}, 0, 0, 0
	for i = 1, DAYS do
		local key = Ledger.DayKey(time() - (DAYS - i) * 86400)
		local amount = Measure(days[key], metric)
		values[i] = { key = key, amount = amount }
		peak = math.max(peak, amount)
		total = total + amount
		if amount > 0 then
			active = active + 1
		end
	end

	self:LayoutBars()
	for i, bar in ipairs(self.bars) do
		local v = values[i]
		bar.day = v.key
		local isToday = i == DAYS
		if v.amount > 0 and peak > 0 then
			bar.fill:SetHeight(math.max(2, CHART_HEIGHT * v.amount / peak))
			T.Tint(bar.fill, isToday and C.gold or { C.gold[1], C.gold[2], C.gold[3], 0.5 })
		else
			bar.fill:SetHeight(1)
			T.Tint(bar.fill, C.line)
		end
	end
	self.axisLeft:SetText(date('%b %d', Ledger.DayEpoch(values[1].key)))
	self.axisMid:SetText(date('%b %d', Ledger.DayEpoch(values[16].key)))
	local label = ({ value = 'value', time = 'farming', kills = 'kills' })[metric]
	self.heading.aside:SetText(active > 0 and (Show(total, metric) .. ' ' .. label .. ' over ' .. active .. (active == 1 and ' day' or ' days')) or '')

	local rows = {}
	local session = Ledger:Session()
	if (session.time or 0) >= 60 then
		rows[#rows + 1] = {
			current = true,
			start = session.started or time(),
			zone = LibsFarmAssistant.Compat.CurrentZone(),
			time = session.time,
			kills = session.kills,
			value = Ledger.TotalValue(session),
			loot = Ledger.Money(session, 'loot'),
			xp = session.xp,
			rep = Ledger.RepTotal(session),
			honor = session.honor,
		}
	end
	-- Copies, so display fields never end up in saved data.
	for _, saved in ipairs(LibsFarmAssistant.char.sessions) do
		local row = {}
		for k, v in pairs(saved) do
			row[k] = v
		end
		rows[#rows + 1] = row
	end
	local best, bestRate = nil, 0
	for _, row in ipairs(rows) do
		row.rate = row.time > 0 and ((row.value or 0) * 3600 / row.time) or 0
		if row.time >= 600 and row.rate > bestRate then
			best, bestRate = row, row.rate
		end
	end
	if best then
		best.best = true
	end
	self.sessionsHeading.aside:SetText(best and ('best ' .. Format.Money(bestRate) .. ' per hour') or '')
	self.sessions:SetData(rows, 'Finished sessions are kept here. A new one starts on its own when you come back after a break, or with the + button.')
end
