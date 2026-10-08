---@class LibsFarmAssistant
local LibsFarmAssistant = LibStub('AceAddon-3.0'):GetAddon('Libs-FarmAssistant')

-- Every mob, node, chest and fishing spot farmed, what each try is worth, and its drop table.

local T = LibsFarmAssistant.Theme
local W = LibsFarmAssistant.Widgets
local C = T.color
local Ledger = LibsFarmAssistant.Ledger
local Format = LibsFarmAssistant.Format
local Compat = LibsFarmAssistant.Compat

---@type FarmPage
local Page = { key = 'sources', title = 'Sources', icon = 'Interface\\Icons\\INV_Misc_Bone_HumanSkull_01' }
LibsFarmAssistant.Pages.sources = Page

local DETAIL_WIDTH = 280

local FILTERS = {
	{ key = 'all', label = 'All' },
	{ key = 'c', label = 'Mobs' },
	{ key = 'o', label = 'Nodes and chests' },
	{ key = 'f', label = 'Fishing' },
}

local KIND_WORD = { creature = 'kills', object = 'opens', fishing = 'catches', container = 'opens', boss = 'kills', reward = 'rewards', gathering = 'gathers', pickpocket = 'picks' }

---@param key string
---@param stats FarmSourceStats
---@return number copper coin plus item value
local function SourceValue(key, stats)
	local Pricing = LibsFarmAssistant.Pricing
	local value = stats.money or 0
	for itemID, count in pairs(stats.items) do
		value = value + (Pricing:Value(itemID) or 0) * count
	end
	return value
end

-- Shared with the broker tooltip, so a source reads the same there as on this page.
Page.KIND_WORD = KIND_WORD
Page.SourceValue = SourceValue

function Page:Create(parent, window)
	self.window = window
	self.filter = 'all'

	local filter = W.Segmented(parent, FILTERS, function(key)
		self.filter = key
		self:Refresh(window:Bucket(), window.range)
	end)
	filter:SetPoint('TOPLEFT')
	filter:Select('all')

	local list = W.Table(parent, {
		{
			key = 'name',
			title = 'Source',
			flex = true,
			sort = function(a, b)
				return a.name < b.name
			end,
			defaultDesc = false,
		},
		{
			key = 'tries',
			title = 'Tries',
			width = 56,
			align = 'RIGHT',
			figures = true,
			sort = function(a, b)
				return a.tries < b.tries
			end,
		},
		{
			key = 'perHour',
			title = 'Per hour',
			width = 60,
			align = 'RIGHT',
			figures = true,
			sort = function(a, b)
				return (a.perHour or 0) < (b.perHour or 0)
			end,
		},
		{
			key = 'each',
			title = 'Value each',
			width = 86,
			align = 'RIGHT',
			figures = true,
			sort = function(a, b)
				return a.each < b.each
			end,
		},
	}, {
		sortKey = 'tries',
		keyOf = function(row)
			return row.key
		end,
		cell = function(row, col)
			if col.key == 'name' then
				local suffix = row.kind ~= 'creature' and T.Wrap('  ' .. row.kind, C.faint) or ''
				return row.name .. suffix
			elseif col.key == 'tries' then
				return Format.Number(row.tries)
			elseif col.key == 'perHour' then
				return Format.Rate(row.perHour), C.muted
			end
			return row.each > 0 and Format.Money(row.each, true) or '-', C.muted
		end,
		onClick = function(row)
			self.selected = row.key
			self.list:Select(row.key)
			self:RefreshDetail(window:Bucket())
		end,
	})
	list:SetPoint('TOPLEFT', filter, 'BOTTOMLEFT', 0, -8)
	list:SetPoint('BOTTOMRIGHT', parent, 'BOTTOMRIGHT', -(DETAIL_WIDTH + 14), 0)
	self.list = list

	local detail = CreateFrame('Frame', nil, parent)
	detail:SetPoint('TOPRIGHT', 0, -30)
	detail:SetPoint('BOTTOMRIGHT')
	detail:SetWidth(DETAIL_WIDTH)
	local edge = detail:CreateTexture(nil, 'BORDER')
	edge:SetTexture(T.WHITE)
	T.Tint(edge, C.line)
	edge:SetWidth(T.Pixel(detail))
	edge:SetPoint('TOPLEFT', -10, 0)
	edge:SetPoint('BOTTOMLEFT', -10, 0)
	self.detail = detail

	local name = T.Text(detail, T.size.title, C.text)
	name:SetPoint('TOPLEFT')
	name:SetPoint('RIGHT')
	self.name = name
	local sub = T.Text(detail, 10, C.muted)
	sub:SetPoint('TOPLEFT', name, 'BOTTOMLEFT', 0, -5)
	sub:SetPoint('RIGHT')
	self.sub = sub
	local worth = T.Text(detail, 10, C.muted, 'figures')
	worth:SetPoint('TOPLEFT', sub, 'BOTTOMLEFT', 0, -4)
	worth:SetPoint('RIGHT')
	self.worth = worth

	local heading = W.Heading(detail, 'Drops')
	heading:SetPoint('TOPLEFT', worth, 'BOTTOMLEFT', 0, -12)
	heading:SetPoint('RIGHT')
	self.dropsHeading = heading

	local drops = W.Table(detail, {
		{
			key = 'name',
			title = 'Item',
			flex = true,
			icon = true,
			sort = function(a, b)
				return a.name < b.name
			end,
			defaultDesc = false,
		},
		{
			key = 'drops',
			title = 'Drops',
			width = 46,
			align = 'RIGHT',
			figures = true,
			sort = function(a, b)
				return a.drops < b.drops
			end,
		},
		{
			key = 'rate',
			title = 'Rate',
			width = 66,
			align = 'RIGHT',
			figures = true,
			sort = function(a, b)
				return a.rate < b.rate
			end,
		},
	}, {
		sortKey = 'rate',
		keyOf = function(row)
			return row.id
		end,
		cell = function(row, col)
			if col.key == 'name' then
				return row.name, T.quality[row.quality or 1], Compat.ItemIcon(row.id)
			elseif col.key == 'drops' then
				return Format.Number(row.drops)
			end
			return Format.Odds(row.rate)
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
	drops:SetPoint('TOPLEFT', heading, 'BOTTOMLEFT', 0, -2)
	drops:SetPoint('BOTTOMRIGHT')
	self.drops = drops

	local none = T.Text(parent, 11, C.muted)
	none:SetPoint('TOPLEFT', detail, 'TOPLEFT', 0, -4)
	none:SetPoint('RIGHT')
	none:SetWordWrap(true)
	none:SetJustifyV('TOP')
	none:SetText('Select a source to see everything it dropped and how often.')
	self.none = none
end

function Page:Rows(bucket)
	local rows = {}
	for key, stats in pairs(bucket.sources) do
		local prefix = key:sub(1, 1)
		local group = (prefix == 'p' or prefix == 'e') and 'c' or ((prefix == 'i' or prefix == 'g') and 'o' or prefix)
		if key ~= 'q' and (self.filter == 'all' or group == self.filter) then
			local tries = Ledger.Attempts(key, stats)
			local value = SourceValue(key, stats)
			rows[#rows + 1] = {
				key = key,
				name = Ledger.SourceName(key),
				kind = Ledger.SourceKind(key),
				tries = tries,
				perHour = Ledger.PerHour(tries, bucket),
				each = tries > 0 and value / tries or 0,
				stats = stats,
			}
		end
	end
	return rows
end

function Page:Count(bucket)
	local n = 0
	for key in pairs(bucket.sources) do
		if key ~= 'q' then
			n = n + 1
		end
	end
	return n
end

function Page:Refresh(bucket, range)
	self.list:SetData(self:Rows(bucket), 'Nothing killed, gathered or fished ' .. (LibsFarmAssistant.Window.RANGE_LABEL[range] or '') .. ' yet.')
	self.list:Select(self.selected)
	self:RefreshDetail(bucket)
end

function Page:RefreshDetail(bucket)
	local key = self.selected
	local stats = key and bucket.sources[key]
	self.detail:SetShown(stats ~= nil)
	self.none:SetShown(stats == nil)
	if not stats then
		return
	end

	local kind = Ledger.SourceKind(key)
	local tries = Ledger.Attempts(key, stats)
	self.name:SetText(Ledger.SourceName(key))
	local parts = { Format.Number(tries) .. ' ' .. (KIND_WORD[kind] or 'tries') }
	if kind == 'creature' and stats.loots ~= tries then
		parts[#parts + 1] = Format.Number(stats.loots) .. ' looted'
	end
	if (stats.money or 0) > 0 then
		parts[#parts + 1] = Format.Money(stats.money) .. ' coin'
	end
	local xpEach = kind == 'creature' and LibsFarmAssistant.ExperienceTracker:SourcePerKill(key)
	if xpEach then
		parts[#parts + 1] = Format.Number(math.floor(xpEach + 0.5)) .. ' xp each'
	end
	self.sub:SetText(table.concat(parts, '   '))

	local value = SourceValue(key, stats)
	if tries > 0 and value > 0 then
		self.worth:SetText('Worth ' .. Format.Money(value / tries, true) .. ' each, ' .. Format.Money(value, true) .. ' in total')
	else
		self.worth:SetText('')
	end

	local rows = {}
	local Pricing = LibsFarmAssistant.Pricing
	for itemID, drops in pairs(stats.drops) do
		local meta = Pricing:Meta(itemID)
		rows[#rows + 1] = {
			id = itemID,
			name = meta.n or ('Item ' .. itemID),
			quality = meta.q,
			drops = drops,
			rate = tries > 0 and math.min(1, drops / tries) or 0,
		}
	end
	self.drops:SetData(rows, 'Nothing dropped yet.')
end
