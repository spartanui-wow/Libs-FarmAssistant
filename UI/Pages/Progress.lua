---@class LibsFarmAssistant
local LibsFarmAssistant = LibStub('AceAddon-3.0'):GetAddon('Libs-FarmAssistant')

-- Standings, experience and currencies: what is being pushed, how fast, and how long until the
-- next step.

local T = LibsFarmAssistant.Theme
local W = LibsFarmAssistant.Widgets
local C = T.color
local Ledger = LibsFarmAssistant.Ledger
local Format = LibsFarmAssistant.Format
local Compat = LibsFarmAssistant.Compat

---@type FarmPage
local Page = { key = 'progress', title = 'Progress', icon = 'Interface\\Icons\\INV_Scroll_03' }
LibsFarmAssistant.Pages.progress = Page

local RIGHT_WIDTH = 270

function Page:Create(parent, window)
	self.window = window

	local repHeading = W.Heading(parent, 'Reputation')
	repHeading:SetPoint('TOPLEFT')
	repHeading:SetPoint('RIGHT', parent, 'RIGHT', -(RIGHT_WIDTH + 20), 0)
	self.repHeading = repHeading

	local reps = W.List(parent, {
		rowHeight = 60,
		createRow = function(row)
			row.card = W.RepCard(row)
			row.card:SetTall(true)
			row.card:SetAllPoints(row)
		end,
		updateRow = function(row, gain)
			row.card:Set(gain)
		end,
	})
	reps:SetPoint('TOPLEFT', repHeading, 'BOTTOMLEFT', 0, -2)
	reps:SetPoint('BOTTOMRIGHT', parent, 'BOTTOMRIGHT', -(RIGHT_WIDTH + 20), 0)
	self.reps = reps

	local right = CreateFrame('Frame', nil, parent)
	right:SetPoint('TOPRIGHT')
	right:SetPoint('BOTTOMRIGHT')
	right:SetWidth(RIGHT_WIDTH)
	self.right = right

	local xpHeading = W.Heading(right, 'Experience')
	xpHeading:SetPoint('TOPLEFT')
	xpHeading:SetPoint('RIGHT')
	self.xpHeading = xpHeading
	local xpBar = W.Bar(right, 6)
	xpBar:SetPoint('TOPLEFT', xpHeading, 'BOTTOMLEFT', 0, -3)
	xpBar:SetPoint('RIGHT')
	self.xpBar = xpBar

	local xp = W.Table(right, {
		{ key = 'label', flex = true },
		{ key = 'value', width = 130, align = 'RIGHT', figures = true },
	}, {
		header = false,
		cell = function(row, col)
			return row[col.key], col.key == 'label' and C.muted or C.text
		end,
	})
	xp:SetPoint('TOPLEFT', xpBar, 'BOTTOMLEFT', 0, -4)
	xp:SetPoint('RIGHT')
	self.xp = xp

	local currencyHeading = W.Heading(right, 'Currency')
	self.currencyHeading = currencyHeading
	local currencies = W.Table(right, {
		{ key = 'name', flex = true, icon = true },
		{ key = 'amount', width = 56, align = 'RIGHT', figures = true },
		{ key = 'rate', width = 70, align = 'RIGHT', figures = true },
	}, {
		header = false,
		cell = function(row, col)
			if col.key == 'name' then
				return row.name, C.text, row.icon
			elseif col.key == 'amount' then
				return Format.Number(row.amount)
			end
			return row.rate and (Format.Rate(row.rate) .. ' /hr') or '-', C.muted
		end,
		onEnter = function(rowFrame, row)
			if row.id and GameTooltip.SetCurrencyByID then
				GameTooltip:SetOwner(rowFrame, 'ANCHOR_RIGHT')
				GameTooltip:SetCurrencyByID(row.id)
				GameTooltip:Show()
			end
		end,
	})
	currencies:SetPoint('BOTTOMRIGHT')
	self.currencies = currencies
end

function Page:Count(bucket)
	local n = 0
	for _ in pairs(bucket.rep) do
		n = n + 1
	end
	return n > 0 and n or nil
end

function Page:Refresh(bucket, range)
	local rangeLabel = LibsFarmAssistant.Window.RANGE_LABEL[range] or ''
	local gains = LibsFarmAssistant.ReputationTracker:Gains(bucket)
	self.repHeading.aside:SetText(#gains > 0 and ('+' .. Format.Number(Ledger.RepTotal(bucket)) .. ' ' .. rangeLabel) or '')
	self.reps:SetData(gains, 'No reputation gained ' .. rangeLabel .. '. Standings you raise show up here with a bar, your pace and the time to the next step.')

	-- Experience
	local status = LibsFarmAssistant.ExperienceTracker:Status()
	local rows = {}
	local anchor
	if status.canGain then
		self.xpHeading.title:SetText('Level ' .. status.level)
		self.xpBar:SetValue(status.current / status.max, C.xp)
		self.xpBar:SetExtra(status.rested / status.max, C.rested)
		self.xpBar:Show()
		rows[#rows + 1] = { label = 'Progress', value = Format.Number(status.current) .. ' / ' .. Format.Number(status.max) }
		rows[#rows + 1] = { label = 'Gained ' .. rangeLabel, value = Format.Number(bucket.xp) }
		local perHour = Ledger.PerHour(bucket.xp, bucket)
		rows[#rows + 1] = { label = 'Per hour', value = perHour and Format.Number(perHour) or '-' }
		if status.rested > 0 then
			rows[#rows + 1] = { label = 'Rested', value = Format.Percent(status.rested / status.max) .. ' of a level' }
		end
		local seconds, kills = LibsFarmAssistant.ExperienceTracker:TimeToLevel(bucket)
		rows[#rows + 1] = { label = 'Next level in', value = seconds and Format.Duration(seconds) or '-' }
		if kills then
			rows[#rows + 1] = { label = 'At this pace', value = 'about ' .. Format.Number(kills) .. ' kills' }
		end
	else
		self.xpHeading.title:SetText('Experience')
		self.xpBar:Hide()
		rows[#rows + 1] = { label = 'Level ' .. status.level, value = 'max level' }
	end
	self.xp:SetHeight(#rows * T.size.row)
	self.xp:SetData(rows)
	anchor = self.xp

	-- Currency and honor
	local list = {}
	for currencyID, amount in pairs(bucket.currencies) do
		local name, icon = Compat.CurrencyInfo(currencyID)
		list[#list + 1] = { id = currencyID, name = name or ('Currency ' .. currencyID), icon = icon, amount = amount, rate = Ledger.PerHour(amount, bucket) }
	end
	table.sort(list, function(a, b)
		return a.amount > b.amount
	end)
	if bucket.honor > 0 then
		table.insert(list, 1, { name = HONOR or 'Honor', icon = 'Interface\\Icons\\INV_Misc_Coin_17', amount = bucket.honor, rate = Ledger.PerHour(bucket.honor, bucket) })
	end
	self.currencyHeading:ClearAllPoints()
	self.currencyHeading:SetPoint('TOPLEFT', anchor, 'BOTTOMLEFT', 0, -14)
	self.currencyHeading:SetPoint('RIGHT', self.right, 'RIGHT')
	self.currencies:ClearAllPoints()
	self.currencies:SetPoint('TOPLEFT', self.currencyHeading, 'BOTTOMLEFT', 0, -2)
	self.currencies:SetPoint('BOTTOMRIGHT', self.right, 'BOTTOMRIGHT')
	self.currencies:SetData(list, 'No currency or honor ' .. rangeLabel .. '.')
end
