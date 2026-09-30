---@class LibsFarmAssistant
local LibsFarmAssistant = LibStub('AceAddon-3.0'):GetAddon('Libs-FarmAssistant')

-- The first sheet: how much value the time is producing, what activity drove it, which loot
-- made it, and the hunts and standings being pushed.

local T = LibsFarmAssistant.Theme
local W = LibsFarmAssistant.Widgets
local C = T.color
local Ledger = LibsFarmAssistant.Ledger
local Format = LibsFarmAssistant.Format

---@type FarmPage
local Page = { key = 'overview', title = 'Overview', icon = 'Interface\\Icons\\INV_Misc_Coin_02' }
LibsFarmAssistant.Pages.overview = Page

local RIGHT_WIDTH = 250
local ROW = T.size.row

local function Money(copper)
	return Format.Money(copper, true)
end

function Page:Create(parent, window)
	self.window = window

	local left = CreateFrame('Frame', nil, parent)
	left:SetPoint('TOPLEFT')
	left:SetPoint('BOTTOMRIGHT', parent, 'BOTTOMRIGHT', -(RIGHT_WIDTH + 18), 0)
	local right = CreateFrame('Frame', nil, parent)
	right:SetPoint('TOPRIGHT')
	right:SetPoint('BOTTOMRIGHT')
	right:SetWidth(RIGHT_WIDTH)
	self.left, self.right = left, right

	-- Income
	self.incomeHeading = W.Heading(left, 'Income')
	self.incomeHeading:SetPoint('TOPLEFT')
	self.incomeHeading:SetPoint('RIGHT')
	self.income = W.Table(left, {
		{ key = 'label', flex = true },
		{ key = 'total', title = 'Total', width = 96, align = 'RIGHT', figures = true },
		{ key = 'rate', title = 'Per hour', width = 96, align = 'RIGHT', figures = true },
	}, {
		ruleOf = function(row)
			return row.strongRule and C.lineStrong or nil
		end,
		cell = function(row, col)
			return row[col.key], row[col.key .. 'Color'] or (col.key == 'label' and C.muted or C.text)
		end,
	})
	self.income:SetPoint('TOPLEFT', self.incomeHeading, 'BOTTOMLEFT', 0, -2)
	self.income:SetPoint('RIGHT')

	-- Activity
	self.activityHeading = W.Heading(left, 'Activity')
	self.activityHeading:SetPoint('TOPLEFT', self.income, 'BOTTOMLEFT', 0, -12)
	self.activityHeading:SetPoint('RIGHT')
	self.activity = W.Table(left, {
		{ key = 'label', flex = true },
		{ key = 'total', width = 96, align = 'RIGHT', figures = true },
		{ key = 'rate', width = 96, align = 'RIGHT', figures = true },
	}, {
		header = false,
		cell = function(row, col)
			return row[col.key], col.key == 'label' and C.muted or (col.key == 'rate' and C.muted or C.text)
		end,
	})
	self.activity:SetPoint('TOPLEFT', self.activityHeading, 'BOTTOMLEFT', 0, -2)
	self.activity:SetPoint('RIGHT')

	-- Top loot
	self.lootHeading = W.Heading(left, 'Top loot')
	self.lootHeading:SetPoint('TOPLEFT', self.activity, 'BOTTOMLEFT', 0, -12)
	self.lootHeading:SetPoint('RIGHT')
	self.loot = W.Table(left, {
		{ key = 'name', title = 'Item', flex = true, icon = true },
		{ key = 'count', title = 'Count', width = 48, align = 'RIGHT', figures = true },
		{ key = 'perHour', title = 'Per hour', width = 56, align = 'RIGHT', figures = true },
		{ key = 'value', title = 'Value', width = 76, align = 'RIGHT', figures = true },
	}, {
		keyOf = function(row)
			return row.id
		end,
		cell = function(row, col)
			if col.key == 'name' then
				return row.name, T.quality[row.quality or 1], LibsFarmAssistant.Compat.ItemIcon(row.id)
			elseif col.key == 'count' then
				return Format.Number(row.count)
			elseif col.key == 'perHour' then
				return Format.Rate(row.perHour), C.muted
			end
			return row.value > 0 and Money(row.value) or '-', C.muted
		end,
		onEnter = function(rowFrame, row)
			W.ShowItemTooltip(rowFrame, row.id)
		end,
		onClick = function(row)
			if not W.ModifiedItemClick(row.id) then
				LibsFarmAssistant.Pages.loot.selected = row.id
				window:ShowPage('loot')
			end
		end,
	})
	self.loot:SetPoint('TOPLEFT', self.lootHeading, 'BOTTOMLEFT', 0, -2)
	self.loot:SetPoint('BOTTOMRIGHT')

	-- Right column
	self.huntHeading = W.Heading(right, 'Hunts')
	self.huntHeading:SetPoint('TOPLEFT')
	self.huntHeading:SetPoint('RIGHT')
	self.huntCards = {}
	for i = 1, 3 do
		local card = W.HuntCard(right, {
			onClick = function(hunt)
				LibsFarmAssistant.Pages.hunts.selected = hunt.id
				window:ShowPage('hunts')
			end,
		})
		card:SetPoint('LEFT')
		card:SetPoint('RIGHT')
		self.huntCards[i] = card
	end
	self.huntEmpty = T.Text(right, 11, C.muted)
	self.huntEmpty:SetWordWrap(true)
	self.huntEmpty:SetJustifyV('TOP')
	self.huntEmpty:SetText('Hunting a rare drop? Open Hunts and add the item to count your attempts.')

	self.repHeading = W.Heading(right, 'Standing')
	self.repCards = {}
	for i = 1, 2 do
		local card = W.RepCard(right)
		card:SetPoint('LEFT')
		card:SetPoint('RIGHT')
		self.repCards[i] = card
	end

	self.xpHeading = W.Heading(right, 'Level')
	self.xpBar = W.Bar(right, 6)
	self.xpLeft = T.Text(right, 10, C.muted, 'figures')
	self.xpRight = T.Text(right, 10, C.muted, 'figures')
	self.xpRight:SetJustifyH('RIGHT')

	self.empty = CreateFrame('Frame', nil, parent)
	self.empty:SetAllPoints(left)
	self.empty:Hide()
	local emptyTitle = T.Text(self.empty, 14, C.text)
	emptyTitle:SetPoint('TOPLEFT', 0, -40)
	emptyTitle:SetText('Nothing counted yet')
	local emptyBody = T.Text(self.empty, 12, C.muted)
	emptyBody:SetPoint('TOPLEFT', emptyTitle, 'BOTTOMLEFT', 0, -8)
	emptyBody:SetPoint('RIGHT', -20, 0)
	emptyBody:SetWordWrap(true)
	emptyBody:SetJustifyV('TOP')
	emptyBody:SetSpacing(3)
	self.emptyBody = emptyBody
end

---@param bucket FarmBucket
---@return table[] income rows
---@return string note comparison with the player's average
local function IncomeRows(bucket)
	local rows = {}
	local looted = Ledger.Money(bucket, 'loot')
	local items = Ledger.ItemValue(bucket)
	local function Add(label, amount, always)
		if amount > 0 or always then
			local rate = Ledger.PerHour(amount, bucket)
			rows[#rows + 1] = { label = label, total = Money(amount), rate = rate and Money(rate) or '-' }
		end
	end
	local quest = Ledger.Money(bucket, 'quest')
	Add('Gold looted', looted, true)
	Add('Quest gold', quest)
	local pricing = LibsFarmAssistant.Pricing
	local valueLabel = (LibsFarmAssistant.db.pricing.source ~= 'vendor' and pricing:HasAuctionSource()) and 'Item value (auction)' or 'Item value (vendor)'
	Add(valueLabel, items, true)
	rows[#rows].strongRule = true

	local total = looted + quest + items
	local rate = Ledger.PerHour(total, bucket)
	local average = Ledger:AverageRate()
	local note = ''
	if rate and average and average > 0 and bucket.time >= 600 then
		local diff = (rate - average) / average
		if diff >= 0.05 then
			note = T.Wrap('+' .. Format.Percent(diff) .. ' vs your average', C.good)
		elseif diff <= -0.05 then
			note = T.Wrap('-' .. Format.Percent(-diff) .. ' vs your average', C.bad)
		end
	end
	rows[#rows + 1] = {
		label = 'Total value',
		labelColor = C.text,
		total = Format.Money(total),
		totalColor = C.gold,
		rate = rate and Format.Money(rate) or '-',
		rateColor = C.gold,
	}
	local sold = Ledger.Money(bucket, 'vendor')
	if sold > 0 then
		local soldRate = Ledger.PerHour(sold, bucket)
		rows[#rows + 1] = {
			label = 'Sold to vendors (already in item value)',
			labelColor = C.faint,
			total = Format.Money(sold),
			totalColor = C.faint,
			rate = soldRate and Format.Money(soldRate) or '-',
			rateColor = C.faint,
		}
	end
	return rows, note
end

---@param bucket FarmBucket
---@return table[]
local function ActivityRows(bucket)
	local rows = {}
	local function Add(label, amount, suffix, always)
		if amount > 0 or always then
			local rate = Ledger.PerHour(amount, bucket)
			rows[#rows + 1] = { label = label, total = Format.Number(amount), rate = rate and (Format.Rate(rate) .. (suffix or ' /hr')) or '-' }
		end
	end
	Add('Kills', bucket.kills, nil, true)
	local nodes = 0
	for key, stats in pairs(bucket.sources) do
		local kind = key:sub(1, 1)
		if kind == 'o' or kind == 'f' then
			nodes = nodes + (stats.loots or 0)
		end
	end
	Add('Nodes and catches', nodes)
	Add('Experience', bucket.xp, nil, LibsFarmAssistant.Compat.CanGainXP())
	Add('Reputation', Ledger.RepTotal(bucket))
	Add('Honor', bucket.honor)
	return rows
end

function Page:Count() end

function Page:Refresh(bucket, range)
	local isEmpty = bucket.time < 1 and next(bucket.items) == nil and Ledger.Money(bucket) == 0 and bucket.kills == 0 and bucket.xp == 0 and next(bucket.rep) == nil

	-- Left column
	local income, note = IncomeRows(bucket)
	self.incomeHeading.aside:SetText(note)
	self.income:SetHeight(#income * ROW + 18)
	self.income:SetData(income)
	local activity = ActivityRows(bucket)
	self.activity:SetHeight(#activity * ROW)
	self.activity:SetData(activity)

	local items = W.ItemRows(bucket)
	self.loot.sortKey = 'value'
	for _, row in ipairs(items) do
		row.sortValue = row.value > 0 and row.value or row.count * 0.0001
	end
	table.sort(items, function(a, b)
		return a.sortValue > b.sortValue
	end)
	self.loot:SetData(items, 'No loot ' .. (LibsFarmAssistant.Window.RANGE_LABEL[range] or '') .. ' yet.')

	for _, region in ipairs({ self.incomeHeading, self.income, self.activityHeading, self.activity, self.lootHeading, self.loot }) do
		region:SetShown(not isEmpty)
	end
	self.empty:SetShown(isEmpty)
	if isEmpty then
		self.emptyBody:SetText(
			'Kill, gather, fish or quest and it shows up here: gold, the value of your loot, kills, experience and reputation, all per hour.\n\n'
				.. 'Loot counts only when it reaches your bags, and every drop is tied to the mob, node or catch it came from, so you can see which one pays best.'
		)
	end

	-- Hunts
	local hunts = LibsFarmAssistant.Hunts:List()
	local anchor = self.huntHeading
	local shown = 0
	for i, card in ipairs(self.huntCards) do
		local hunt = hunts[i]
		card:ClearAllPoints()
		if hunt then
			card:SetPoint('TOPLEFT', anchor, 'BOTTOMLEFT', 0, i == 1 and -2 or 0)
			card:SetPoint('RIGHT', self.right, 'RIGHT')
			card:Set(hunt)
			card:Show()
			anchor = card
			shown = shown + 1
		else
			card:Hide()
		end
	end
	self.huntHeading.aside:SetText(#hunts > 3 and (#hunts - 3 .. ' more') or '')
	self.huntEmpty:ClearAllPoints()
	self.huntEmpty:SetPoint('TOPLEFT', self.huntHeading, 'BOTTOMLEFT', 0, -4)
	self.huntEmpty:SetPoint('RIGHT', self.right, 'RIGHT')
	self.huntEmpty:SetShown(shown == 0)
	if shown == 0 then
		anchor = self.huntEmpty
	end

	-- Standing
	local gains = LibsFarmAssistant.ReputationTracker:Gains(bucket)
	self.repHeading:ClearAllPoints()
	self.repHeading:SetPoint('TOPLEFT', anchor, 'BOTTOMLEFT', 0, -14)
	self.repHeading:SetPoint('RIGHT', self.right, 'RIGHT')
	self.repHeading:SetShown(#gains > 0)
	self.repHeading.aside:SetText(#gains > 2 and (#gains - 2 .. ' more') or '')
	local repAnchor = self.repHeading
	for i, card in ipairs(self.repCards) do
		local gain = gains[i]
		card:ClearAllPoints()
		if gain then
			card:SetPoint('TOPLEFT', repAnchor, 'BOTTOMLEFT', 0, 0)
			card:SetPoint('RIGHT', self.right, 'RIGHT')
			card:Set(gain)
			card:Show()
			repAnchor = card
		else
			card:Hide()
		end
	end
	if #gains > 0 then
		anchor = repAnchor
	end

	-- Level
	local xp = LibsFarmAssistant.ExperienceTracker:Status()
	local showXP = xp.canGain
	for _, region in ipairs({ self.xpHeading, self.xpBar, self.xpLeft, self.xpRight }) do
		region:SetShown(showXP)
	end
	if showXP then
		self.xpHeading:ClearAllPoints()
		self.xpHeading:SetPoint('TOPLEFT', anchor, 'BOTTOMLEFT', 0, -14)
		self.xpHeading:SetPoint('RIGHT', self.right, 'RIGHT')
		self.xpHeading.title:SetText('Level ' .. xp.level)
		self.xpHeading.aside:SetText(bucket.xp > 0 and ('+' .. Format.Short(bucket.xp)) or '')
		self.xpBar:ClearAllPoints()
		self.xpBar:SetPoint('TOPLEFT', self.xpHeading, 'BOTTOMLEFT', 0, -3)
		self.xpBar:SetPoint('RIGHT', self.right, 'RIGHT')
		self.xpBar:SetValue(xp.current / xp.max, C.xp)
		self.xpBar:SetExtra(xp.rested / xp.max, C.rested)
		self.xpLeft:ClearAllPoints()
		self.xpLeft:SetPoint('TOPLEFT', self.xpBar, 'BOTTOMLEFT', 0, -4)
		local restedText = xp.rested > 0 and ('  rested ' .. Format.Percent(math.min(xp.rested / xp.max, 1.5))) or ''
		self.xpLeft:SetText(Format.Percent(xp.current / xp.max) .. restedText)
		self.xpRight:ClearAllPoints()
		self.xpRight:SetPoint('TOPRIGHT', self.xpBar, 'BOTTOMRIGHT', 0, -4)
		local seconds, kills = LibsFarmAssistant.ExperienceTracker:TimeToLevel(bucket)
		local parts = {}
		if kills then
			parts[#parts + 1] = Format.Number(kills) .. (kills == 1 and ' kill' or ' kills')
		end
		if seconds then
			parts[#parts + 1] = Format.Duration(seconds)
		end
		self.xpRight:SetText(#parts > 0 and (table.concat(parts, ', ') .. ' to level ' .. (xp.level + 1)) or '')
	end
end
