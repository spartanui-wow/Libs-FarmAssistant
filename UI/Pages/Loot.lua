---@class LibsFarmAssistant
local LibsFarmAssistant = LibStub('AceAddon-3.0'):GetAddon('Libs-FarmAssistant')

-- Every item looted in the chosen time, and for the selected item, where it drops best.

local T = LibsFarmAssistant.Theme
local W = LibsFarmAssistant.Widgets
local C = T.color
local Ledger = LibsFarmAssistant.Ledger
local Format = LibsFarmAssistant.Format
local Compat = LibsFarmAssistant.Compat

---@type FarmPage
local Page = { key = 'loot', title = 'Loot', icon = 'Interface\\Icons\\INV_Misc_Bag_10' }
LibsFarmAssistant.Pages.loot = Page

local DETAIL_WIDTH = 270
local QUALITIES = { 0, 1, 2, 3, 4, 5 }

function Page:Create(parent, window)
	self.window = window
	self.hidden = {} -- quality -> true when filtered out of the view
	self.search = ''

	local toolbar = CreateFrame('Frame', nil, parent)
	toolbar:SetHeight(20)
	toolbar:SetPoint('TOPLEFT')
	toolbar:SetPoint('TOPRIGHT')
	local x = 0
	for _, q in ipairs(QUALITIES) do
		local label = _G['ITEM_QUALITY' .. q .. '_DESC'] or tostring(q)
		local chip = W.Chip(toolbar, label, T.quality[q], function(pressed)
			self.hidden[q] = not pressed or nil
			self:Refresh(window:Bucket(), window.range)
		end)
		chip:SetPoint('LEFT', toolbar, 'LEFT', x, 0)
		x = x + chip:GetWidth() + 4
	end
	local search = W.EditBox(toolbar, 150, 'Search loot')
	search:SetPoint('RIGHT', toolbar, 'RIGHT', 0, 0)
	search.onChange = function(text)
		self.search = (text or ''):lower()
		self:Refresh(window:Bucket(), window.range)
	end

	local tableFrame = W.Table(parent, {
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
			key = 'count',
			title = 'Count',
			width = 48,
			align = 'RIGHT',
			figures = true,
			sort = function(a, b)
				return a.count < b.count
			end,
		},
		{
			key = 'perHour',
			title = 'Per hour',
			width = 56,
			align = 'RIGHT',
			figures = true,
			sort = function(a, b)
				return (a.perHour or 0) < (b.perHour or 0)
			end,
		},
		{
			key = 'value',
			title = 'Value',
			width = 80,
			align = 'RIGHT',
			figures = true,
			sort = function(a, b)
				return a.value < b.value
			end,
		},
	}, {
		sortKey = 'count',
		keyOf = function(row)
			return row.id
		end,
		cell = function(row, col)
			if col.key == 'name' then
				return row.name, T.quality[row.quality or 1], Compat.ItemIcon(row.id)
			elseif col.key == 'count' then
				return Format.Number(row.count)
			elseif col.key == 'perHour' then
				return Format.Rate(row.perHour), C.muted
			end
			return row.value > 0 and Format.Money(row.value, true) or '-', C.muted
		end,
		onEnter = function(rowFrame, row)
			W.ShowItemTooltip(rowFrame, row.id)
		end,
		onClick = function(row)
			if not W.ModifiedItemClick(row.id) then
				self.selected = row.id
				self:RefreshDetail(window:Bucket(), window.range)
				self.table:Select(row.id)
			end
		end,
	})
	tableFrame:SetPoint('TOPLEFT', toolbar, 'BOTTOMLEFT', 0, -8)
	tableFrame:SetPoint('BOTTOMRIGHT', parent, 'BOTTOMRIGHT', -(DETAIL_WIDTH + 14), 0)
	self.table = tableFrame

	self:CreateDetail(parent)
end

function Page:CreateDetail(parent)
	local detail = CreateFrame('Frame', nil, parent)
	detail:SetPoint('TOPRIGHT', 0, -28)
	detail:SetPoint('BOTTOMRIGHT')
	detail:SetWidth(DETAIL_WIDTH)
	local edge = detail:CreateTexture(nil, 'BORDER')
	edge:SetTexture(T.WHITE)
	T.Tint(edge, C.line)
	edge:SetWidth(T.Pixel(detail))
	edge:SetPoint('TOPLEFT', -10, 0)
	edge:SetPoint('BOTTOMLEFT', -10, 0)
	self.detail = detail

	local icon = T.Icon(detail, 36)
	icon:SetPoint('TOPLEFT', 2, 0)
	self.detailIcon = icon
	local name = T.Text(detail, 13, C.text)
	name:SetPoint('TOPLEFT', icon, 'TOPRIGHT', 8, -2)
	name:SetPoint('RIGHT')
	self.detailName = name
	local sub = T.Text(detail, 10, C.muted)
	sub:SetPoint('TOPLEFT', name, 'BOTTOMLEFT', 0, -4)
	sub:SetPoint('RIGHT')
	self.detailSub = sub

	local heading = W.Heading(detail, 'Where it drops')
	heading:SetPoint('TOPLEFT', icon, 'BOTTOMLEFT', -2, -12)
	heading:SetPoint('RIGHT')
	heading.aside:SetText('best rate first')
	self.detailHeading = heading

	local sources = W.Table(detail, {
		{ key = 'name', title = 'Source', flex = true },
		{ key = 'kills', title = 'Tries', width = 44, align = 'RIGHT', figures = true },
		{ key = 'drops', title = 'Drops', width = 42, align = 'RIGHT', figures = true },
		{ key = 'rate', title = 'Rate', width = 64, align = 'RIGHT', figures = true },
	}, {
		cell = function(row, col)
			if col.key == 'name' then
				return Ledger.SourceName(row.key)
			elseif col.key == 'kills' then
				return Format.Number(row.kills), C.muted
			elseif col.key == 'drops' then
				return Format.Number(row.drops)
			end
			return Format.Odds(row.rate), row.best and C.good or C.text
		end,
		onEnter = function(rowFrame, row)
			W.ShowTooltip(
				rowFrame,
				Ledger.SourceName(row.key),
				string.format('%s tries, dropped %s times (%s in total).', Format.Number(row.kills), Format.Number(row.drops), Format.Number(row.quantity))
			)
		end,
	})
	sources:SetPoint('TOPLEFT', heading, 'BOTTOMLEFT', 0, -2)
	sources:SetPoint('RIGHT')
	sources:SetHeight(18 + 5 * T.size.row)
	self.sources = sources

	local note = T.Text(detail, 10, C.muted)
	note:SetPoint('TOPLEFT', sources, 'BOTTOMLEFT', 0, -6)
	note:SetPoint('RIGHT')
	note:SetWordWrap(true)
	note:SetJustifyV('TOP')
	self.note = note

	local hunt = W.Button(detail, 'Hunt this item', {
		onClick = function()
			if self.selected then
				LibsFarmAssistant.Hunts:Add(self.selected)
				LibsFarmAssistant.Pages.hunts.selected = self.selected
				self.window:ShowPage('hunts')
			end
		end,
		tooltip = { 'Hunt this item', 'Count attempts until it drops again, and see how lucky you are.' },
	})
	hunt:SetPoint('BOTTOMLEFT', 0, 0)
	self.huntButton = hunt

	local always = W.Button(detail, 'Always loot', {
		quiet = true,
		onClick = function()
			if self.selected then
				local list = LibsFarmAssistant.db.lootModules.whitelist
				local key = tostring(self.selected)
				if list[key] then
					list[key] = nil
				else
					list[key] = LibsFarmAssistant.Pricing:Meta(self.selected).n or key
				end
				LibsFarmAssistant:InvalidateLootingModuleCache()
				self:RefreshDetail(self.window:Bucket(), self.window.range)
			end
		end,
		tooltip = { 'Always loot', 'Auto-loot picks this item up no matter which filters are on.' },
	})
	always:SetPoint('LEFT', hunt, 'RIGHT', 6, 0)
	self.alwaysButton = always

	local none = T.Text(detail, 11, C.muted)
	none:SetPoint('TOPLEFT', 2, -4)
	none:SetPoint('RIGHT')
	none:SetWordWrap(true)
	none:SetJustifyV('TOP')
	none:SetText('Select an item to see which mobs and nodes drop it, and which one drops it most often.')
	self.detailNone = none
end

function Page:Count(bucket)
	local _, unique = Ledger.ItemCounts(bucket)
	return unique
end

function Page:Refresh(bucket, range)
	local rows = {}
	for _, row in ipairs(W.ItemRows(bucket)) do
		local visible = not self.hidden[row.quality or 1]
		if visible and self.search ~= '' then
			visible = row.name:lower():find(self.search, 1, true) ~= nil
		end
		if visible then
			rows[#rows + 1] = row
		end
	end
	local emptyText
	if next(bucket.items) == nil then
		emptyText = 'No loot ' .. (LibsFarmAssistant.Window.RANGE_LABEL[range] or '') .. ' yet.'
	else
		emptyText = 'No loot matches the filters.'
	end
	self.table:SetData(rows, emptyText)
	self.table:Select(self.selected)
	self:RefreshDetail(bucket, range)
end

function Page:RefreshDetail(bucket, range)
	local itemID = self.selected
	local count = itemID and bucket.items[itemID]
	local hasItem = itemID ~= nil

	for _, region in ipairs({ self.detailIcon, self.detailName, self.detailSub, self.detailHeading, self.sources, self.note, self.huntButton, self.alwaysButton }) do
		region:SetShown(hasItem)
	end
	self.detailNone:SetShown(not hasItem)
	if not hasItem then
		return
	end

	local meta = LibsFarmAssistant.Pricing:Meta(itemID)
	self.detailIcon:SetTexture(Compat.ItemIcon(itemID))
	self.detailName:SetText(meta.n or ('Item ' .. itemID))
	self.detailName:SetTextColor(T.QualityRGB(meta.q))

	-- Drop rates want as many tries as possible, so small windows borrow all-time sources.
	local list = Ledger.ItemSources(bucket, itemID)
	local fromAll = false
	if #list == 0 and bucket ~= Ledger:Lifetime() then
		list = Ledger.ItemSources(Ledger:Lifetime(), itemID)
		fromAll = #list > 0
	end
	if list[1] and #list > 1 then
		list[1].best = true
	end

	local where = #list == 1 and '1 source' or (#list .. ' sources')
	self.detailSub:SetText(string.format('%s looted %s from %s', Format.Number(count or 0), LibsFarmAssistant.Window.RANGE_LABEL[range] or '', where))
	self.sources:SetData(list, 'No source recorded. It came from a quest, a container or somewhere the addon could not see.')

	local note = ''
	if fromAll then
		note = 'Showing all-time sources, since none dropped it in this range.'
	elseif #list >= 2 and list[1].rate and list[2].rate and list[2].rate > 0 then
		local ratio = list[1].rate / list[2].rate
		if ratio >= 1.2 then
			note = string.format('%s drops it %s times as often as %s.', Ledger.SourceName(list[1].key), string.format('%.1f', ratio), Ledger.SourceName(list[2].key))
		else
			note = 'These sources drop it about equally often.'
		end
	end
	if #list > 0 then
		note = note .. (note ~= '' and ' ' or '') .. 'Tries count kills for mobs and opens for nodes, chests and catches.'
	end
	self.note:SetText(note)

	local whitelisted = LibsFarmAssistant.db.lootModules.whitelist[tostring(itemID)] ~= nil
	self.alwaysButton:SetLabel(whitelisted and 'Stop always looting' or 'Always loot')
	self.huntButton:SetLabel(LibsFarmAssistant.Hunts:Get(itemID) and 'View hunt' or 'Hunt this item')
end
