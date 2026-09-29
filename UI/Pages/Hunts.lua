---@class LibsFarmAssistant
local LibsFarmAssistant = LibStub('AceAddon-3.0'):GetAddon('Libs-FarmAssistant')

-- Rare drop hunts: how many tries so far, how long, how lucky, and which mobs count.

local T = LibsFarmAssistant.Theme
local W = LibsFarmAssistant.Widgets
local C = T.color
local Ledger = LibsFarmAssistant.Ledger
local Format = LibsFarmAssistant.Format
local Compat = LibsFarmAssistant.Compat

---@type FarmPage
local Page = { key = 'hunts', title = 'Hunts', icon = 'Interface\\Icons\\Ability_Hunter_SniperShot' }
LibsFarmAssistant.Pages.hunts = Page

local LIST_WIDTH = 236

local KIND_LABEL = { mount = 'Mount', pet = 'Pet', toy = 'Toy' }

StaticPopupDialogs['LIBSFA_STOP_HUNT'] = {
	text = 'Stop hunting %s? Its count and history are removed.',
	button1 = 'Stop hunting',
	button2 = CANCEL or 'Cancel',
	OnAccept = function(_, itemID)
		LibsFarmAssistant.Hunts:Remove(itemID)
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
}

---@param itemID number|nil
function Page:AddHunt(itemID)
	if not itemID then
		return
	end
	LibsFarmAssistant.Hunts:Add(itemID)
	self.selected = itemID
	self:Refresh()
end

local function CursorItem()
	local kind, itemID = GetCursorInfo()
	if kind == 'item' and itemID then
		ClearCursor()
		return itemID
	end
	return nil
end

function Page:Create(parent, window)
	self.window = window

	local left = CreateFrame('Frame', nil, parent)
	left:SetPoint('TOPLEFT')
	left:SetPoint('BOTTOMLEFT')
	left:SetWidth(LIST_WIDTH)
	left:EnableMouse(true)
	left:SetScript('OnReceiveDrag', function()
		self:AddHunt(CursorItem())
	end)
	left:SetScript('OnMouseUp', function()
		self:AddHunt(CursorItem())
	end)

	local add = W.EditBox(left, LIST_WIDTH, 'Add: Shift-click an item or type its ID')
	add:SetPoint('TOPLEFT')
	add.onSubmit = function(text)
		local itemID = Compat.ItemIDFromLink(text) or tonumber(text)
		if itemID then
			self:AddHunt(itemID)
		end
		add:SetText('')
	end
	add:SetScript('OnReceiveDrag', function()
		self:AddHunt(CursorItem())
	end)
	W.AcceptLinks(add)
	self.addBox = add

	local list = W.List(left, {
		rowHeight = 46,
		keyOf = function(hunt)
			return hunt.id
		end,
		createRow = function(row)
			row.card = W.HuntCard(row, {
				onClick = function(hunt)
					self.selected = hunt.id
					self:Refresh()
				end,
			})
			row.card:SetAllPoints(row)
			row.card:SetScript('OnReceiveDrag', function()
				self:AddHunt(CursorItem())
			end)
		end,
		updateRow = function(row, hunt)
			row.card:Set(hunt, hunt.id == self.selected)
		end,
	})
	list:SetPoint('TOPLEFT', add, 'BOTTOMLEFT', 0, -8)
	list:SetPoint('BOTTOMRIGHT', left, 'BOTTOMRIGHT', 0, 0)
	self.list = list

	self:CreateDetail(parent)
end

local function Stat(parent, caption)
	local figure = T.Text(parent, T.size.big, C.text, 'figures')
	local label = T.Text(parent, 10, C.muted)
	label:SetWidth(110)
	label:SetPoint('TOPLEFT', figure, 'BOTTOMLEFT', 0, -3)
	label:SetText(caption)
	figure.caption = label
	return figure
end

function Page:CreateDetail(parent)
	local detail = CreateFrame('Frame', nil, parent)
	detail:SetPoint('TOPLEFT', parent, 'TOPLEFT', LIST_WIDTH + 18, 0)
	detail:SetPoint('BOTTOMRIGHT')
	self.detail = detail

	local icon = T.Icon(detail, 40)
	icon:SetPoint('TOPLEFT')
	self.icon = icon
	local iconButton = CreateFrame('Button', nil, detail)
	iconButton:SetAllPoints(icon)
	iconButton:SetScript('OnEnter', function(btn)
		if self.selected then
			W.ShowItemTooltip(btn, self.selected)
		end
	end)
	iconButton:SetScript('OnLeave', function()
		GameTooltip:Hide()
	end)
	iconButton:SetScript('OnClick', function()
		if self.selected then
			W.ModifiedItemClick(self.selected)
		end
	end)

	local name = T.Text(detail, T.size.title, C.text)
	name:SetPoint('TOPLEFT', icon, 'TOPRIGHT', 10, -3)
	name:SetPoint('RIGHT')
	self.name = name
	local sub = T.Text(detail, 10, C.muted)
	sub:SetPoint('TOPLEFT', name, 'BOTTOMLEFT', 0, -5)
	sub:SetPoint('RIGHT')
	self.sub = sub

	local views = W.Segmented(detail, {
		{ key = 'details', label = 'Details' },
		{ key = 'characters', label = 'Characters', tooltip = 'Which of your characters can still try for it before the lockout resets.' },
	}, function(key)
		self.view = key
		self:Refresh()
	end)
	views:SetPoint('TOPRIGHT')
	views:Select('details')
	self.views = views
	self.view = 'details'
	name:SetPoint('RIGHT', views, 'LEFT', -8, 0)
	sub:SetPoint('RIGHT', views, 'LEFT', -8, 0)

	self:CreateCharacters(detail, icon)

	-- Everything below the title belongs to the Details view.
	local body = CreateFrame('Frame', nil, detail)
	body:SetPoint('TOPLEFT', icon, 'BOTTOMLEFT', 0, 0)
	body:SetPoint('BOTTOMRIGHT')
	self.body = body
	detail = body

	local attempts = Stat(detail, 'attempts')
	attempts:SetPoint('TOPLEFT', icon, 'BOTTOMLEFT', 0, -14)
	self.attempts = attempts
	local timeStat = Stat(detail, 'time hunting')
	timeStat:SetPoint('TOPLEFT', attempts, 'TOPLEFT', 120, 0)
	self.timeStat = timeStat
	local chanceStat = Stat(detail, 'drop chance')
	chanceStat:SetPoint('TOPLEFT', attempts, 'TOPLEFT', 240, 0)
	self.chanceStat = chanceStat
	-- Three equal columns, so captions never run into each other or past the window edge.
	detail:SetScript('OnSizeChanged', function(frame)
		local slot = math.floor((frame:GetWidth() or 360) / 3)
		timeStat:ClearAllPoints()
		timeStat:SetPoint('TOPLEFT', attempts, 'TOPLEFT', slot, 0)
		chanceStat:ClearAllPoints()
		chanceStat:SetPoint('TOPLEFT', attempts, 'TOPLEFT', slot * 2, 0)
		for _, stat in ipairs({ attempts, timeStat, chanceStat }) do
			stat.caption:SetWidth(slot - 10)
		end
	end)

	local luckHeading = W.Heading(detail, 'Luck')
	luckHeading:SetPoint('TOPLEFT', attempts.caption, 'BOTTOMLEFT', 0, -14)
	luckHeading:SetPoint('RIGHT')
	self.luckHeading = luckHeading
	local luckBar = W.Bar(detail, 6)
	luckBar:SetPoint('TOPLEFT', luckHeading, 'BOTTOMLEFT', 0, -3)
	luckBar:SetPoint('RIGHT')
	self.luckBar = luckBar
	local luckText = T.Text(detail, 11, C.muted)
	luckText:SetPoint('TOPLEFT', luckBar, 'BOTTOMLEFT', 0, -6)
	luckText:SetPoint('RIGHT')
	luckText:SetWordWrap(true)
	luckText:SetJustifyV('TOP')
	self.luckText = luckText

	local chanceLabel = T.Text(detail, 11, C.muted)
	chanceLabel:SetText('Drop chance')
	local chanceBox = W.EditBox(detail, 56, '%')
	chanceBox:SetPoint('TOPLEFT', luckText, 'BOTTOMLEFT', 76, -8)
	chanceLabel:SetPoint('RIGHT', chanceBox, 'LEFT', -8, 0)
	chanceBox.onSubmit = function(text)
		if self.selected then
			local cleaned = (text or ''):gsub('%%', ''):gsub(',', '.')
			local value = tonumber(cleaned)
			LibsFarmAssistant.Hunts:SetChance(self.selected, value)
			self:Refresh()
		end
	end
	W.SetTooltip(chanceBox, 'Drop chance', 'Type the chance in percent, like 1 or 0.5, and press Enter. Leave empty to clear it.')
	self.chanceBox = chanceBox
	local chanceHint = T.Text(detail, 10, C.faint)
	chanceHint:SetPoint('LEFT', chanceBox, 'RIGHT', 8, 0)
	chanceHint:SetText('Set it to see how lucky you are.')
	self.chanceHint = chanceHint

	local sourcesHeading = W.Heading(detail, 'Counts when these die')
	sourcesHeading:SetPoint('TOPLEFT', chanceBox, 'BOTTOMLEFT', -76, -14)
	sourcesHeading:SetPoint('RIGHT')
	self.sourcesHeading = sourcesHeading

	local mode = W.Segmented(detail, {
		{ key = 'sources', label = 'These sources', tooltip = 'Only kills and opens of the sources below count.' },
		{ key = 'any', label = 'Every kill', tooltip = 'Every kill, node and catch counts. Good for world drops.' },
	}, function(key)
		if self.selected then
			LibsFarmAssistant.Hunts:SetMode(self.selected, key)
			self:Refresh()
		end
	end)
	mode:SetPoint('RIGHT', sourcesHeading, 'RIGHT', 0, 0)
	self.mode = mode

	local sources = W.Table(detail, {
		{ key = 'name', title = 'Source', flex = true },
		{ key = 'tries', title = 'Tries', width = 60, align = 'RIGHT', figures = true },
		{ key = 'drops', title = 'Drops', width = 50, align = 'RIGHT', figures = true },
		{ key = 'rate', title = 'Rate', width = 70, align = 'RIGHT', figures = true },
	}, {
		cell = function(row, col)
			if col.key == 'name' then
				return Ledger.SourceName(row.key) .. (row.kind ~= 'creature' and T.Wrap('  ' .. row.kind, C.faint) or '')
			elseif col.key == 'tries' then
				return Format.Number(row.tries), C.muted
			elseif col.key == 'drops' then
				return Format.Number(row.drops)
			end
			return row.drops > 0 and Format.Odds(row.drops / math.max(1, row.tries)) or '-'
		end,
		onEnter = function(rowFrame, row)
			W.ShowTooltip(rowFrame, Ledger.SourceName(row.key), 'Right-click to stop counting this source.')
		end,
		onClick = function(row, button)
			if button == 'RightButton' and self.selected then
				LibsFarmAssistant.Hunts:RemoveSource(self.selected, row.key)
				self:Refresh()
			end
		end,
	})
	sources:SetPoint('TOPLEFT', sourcesHeading, 'BOTTOMLEFT', 0, -4)
	sources:SetPoint('RIGHT')
	sources:SetHeight(18 + 3 * T.size.row)
	self.sources = sources

	local history = T.Text(detail, 10, C.muted, 'figures')
	history:SetPoint('TOPLEFT', sources, 'BOTTOMLEFT', 0, -8)
	history:SetPoint('RIGHT')
	history:SetWordWrap(true)
	history:SetJustifyV('TOP')
	self.history = history

	local target = W.Button(detail, 'Count my target', {
		onClick = function()
			if self.selected and not LibsFarmAssistant.Hunts:AddTargetAsSource(self.selected) then
				LibsFarmAssistant:Print('Target a creature first, then press Count my target.')
			end
			self:Refresh()
		end,
		tooltip = { 'Count my target', 'Kills of the creature you have targeted count as attempts for this hunt.' },
	})
	target:SetPoint('BOTTOMLEFT')
	self.targetButton = target

	local pause = W.Button(detail, 'Pause', {
		quiet = true,
		onClick = function()
			if self.selected then
				LibsFarmAssistant.Hunts:TogglePaused(self.selected)
				self:Refresh()
			end
		end,
	})
	pause:SetPoint('LEFT', target, 'RIGHT', 6, 0)
	self.pauseButton = pause

	local reset = W.Button(detail, 'Reset count', {
		quiet = true,
		onClick = function()
			if self.selected then
				LibsFarmAssistant.Hunts:ResetCount(self.selected)
				self:Refresh()
			end
		end,
		tooltip = { 'Reset count', 'Start the attempt count and time again. Past drops are kept.' },
	})
	reset:SetPoint('LEFT', pause, 'RIGHT', 6, 0)

	local stop = W.Button(detail, 'Stop hunting', {
		quiet = true,
		onClick = function()
			if self.selected then
				StaticPopup_Show('LIBSFA_STOP_HUNT', LibsFarmAssistant.Pricing:Meta(self.selected).n or 'this item', nil, self.selected)
			end
		end,
	})
	stop:SetPoint('BOTTOMRIGHT')

	local none = CreateFrame('Frame', nil, parent)
	none:SetAllPoints(self.detail)
	local noneTitle = T.Text(none, 14, C.text)
	noneTitle:SetPoint('TOPLEFT', 0, -40)
	noneTitle:SetText('Hunt a rare drop')
	local noneBody = T.Text(none, 12, C.muted)
	noneBody:SetPoint('TOPLEFT', noneTitle, 'BOTTOMLEFT', 0, -8)
	noneBody:SetPoint('RIGHT', -20, 0)
	noneBody:SetWordWrap(true)
	noneBody:SetJustifyV('TOP')
	noneBody:SetSpacing(3)
	noneBody:SetText(
		'Pick any item, mount, pet or toy and every chance at it is counted until it drops: kills of the mobs that carry it, nodes, chests and catches.\n\n'
			.. 'Click in the box on the left and Shift-click the item, type its ID, or drag it from your bags. Set the drop chance to see how your luck compares.'
	)
	self.none = none
end

function Page:Count()
	return LibsFarmAssistant.Hunts:Count()
end

---@param hunt FarmHunt
---@return table[]
local function SourceRows(hunt)
	local lifetime = Ledger:Lifetime()
	local rows, seen = {}, {}
	local function Add(key)
		if seen[key] then
			return
		end
		seen[key] = true
		local stats = lifetime.sources[key]
		rows[#rows + 1] = {
			key = key,
			kind = Ledger.SourceKind(key),
			tries = stats and Ledger.Attempts(key, stats) or 0,
			drops = stats and stats.drops[hunt.id] or 0,
		}
	end
	for key in pairs(hunt.sources) do
		Add(key)
	end
	table.sort(rows, function(a, b)
		return a.tries > b.tries
	end)
	return rows
end

function Page:Refresh()
	local Hunts = LibsFarmAssistant.Hunts
	local hunts = Hunts:List()
	if not self.selected or not Hunts:Get(self.selected) then
		self.selected = hunts[1] and hunts[1].id or nil
	end
	self.list:SetData(hunts, 'No hunts yet.')
	self.list:Select(self.selected)

	local hunt = self.selected and Hunts:Get(self.selected)
	self.detail:SetShown(hunt ~= nil)
	self.none:SetShown(hunt == nil)
	if not hunt then
		return
	end

	local meta = LibsFarmAssistant.Pricing:Meta(hunt.id)
	self.icon:SetTexture(Compat.ItemIcon(hunt.id))
	self.name:SetText(meta.n or ('Item ' .. hunt.id))
	self.name:SetTextColor(T.QualityRGB(meta.q))

	local kind, collected = Hunts:Collectible(hunt)
	local parts = {}
	if kind then
		parts[#parts + 1] = KIND_LABEL[kind] .. (collected and ', collected' or ', not collected')
	end
	parts[#parts + 1] = string.format('hunting since %s', date('%b %d', hunt.added))
	if hunt.shared then
		parts[#parts + 1] = 'all characters'
	end
	if hunt.paused then
		parts[#parts + 1] = 'paused'
	end
	self.sub:SetText(table.concat(parts, '  |  '))

	self.attempts:SetText(Format.Number(hunt.attempts or 0))
	local anyKill = hunt.mode == 'any' or not Hunts:HasSources(hunt)
	self.attempts.caption:SetText(#hunt.found > 0 and 'since last drop' or (anyKill and 'kills so far' or 'attempts so far'))
	self.timeStat:SetText(Format.Duration(hunt.time or 0))
	self.chanceStat:SetText(hunt.chance and Format.Percent(hunt.chance) or '-')
	self.chanceStat.caption:SetText(hunt.chance and ('drop chance, ' .. Format.Odds(hunt.chance)) or 'drop chance')
	if not self.chanceBox:HasFocus() then
		self.chanceBox:SetText(hunt.chance and tostring(math.floor(hunt.chance * 10000 + 0.5) / 100) or '')
	end
	self.chanceHint:SetShown(not hunt.chance)

	local text, byNow = Hunts:LuckText(hunt)
	self.luckBar:SetShown(text ~= nil)
	if text then
		self.luckBar:SetValue(math.max(byNow or 0, 0.01), W.LuckColor(byNow or 0))
		self.luckText:SetText(text)
	else
		local observed = Hunts:ObservedSources(hunt)[1]
		if observed and observed.rate then
			self.luckText:SetText(string.format('You have seen it drop %s from %s. Set the drop chance to compare your luck.', Format.Odds(observed.rate), Ledger.SourceName(observed.key)))
		else
			self.luckText:SetText('No drop chance set yet.')
		end
	end

	self.mode:Select(hunt.mode == 'any' and 'any' or 'sources')
	local rows = SourceRows(hunt)
	local emptyText = 'No source yet, so every kill, node and catch counts. The first drop teaches the source, or target the mob and press Count my target.'
	self.sources:SetData(rows, emptyText)

	if #hunt.found > 0 then
		local lines = {}
		for i = #hunt.found, math.max(1, #hunt.found - 3), -1 do
			local drop = hunt.found[i]
			lines[#lines + 1] = string.format('%s:  after %s attempts, %s', date('%b %d', drop.at), Format.Number(drop.attempts), Format.Duration(drop.time))
		end
		local total = #hunt.found
		self.history:SetText(T.Wrap(total == 1 and 'Dropped once' or ('Dropped ' .. total .. ' times'), C.gold) .. '\n' .. table.concat(lines, '\n'))
	else
		self.history:SetText('')
	end

	self.pauseButton:SetLabel(hunt.paused and 'Resume' or 'Pause')

	self.views:Select(self.view)
	self.body:SetShown(self.view ~= 'characters')
	self.characters:SetShown(self.view == 'characters')
	if self.view == 'characters' then
		self:RefreshCharacters(hunt)
	end
end

---@param detail Frame
---@param icon Texture
function Page:CreateCharacters(detail, icon)
	local view = CreateFrame('Frame', nil, detail)
	view:SetPoint('TOPLEFT', icon, 'BOTTOMLEFT', 0, -14)
	view:SetPoint('BOTTOMRIGHT')
	view:Hide()
	self.characters = view

	local heading = W.Heading(view, 'This week')
	heading:SetPoint('TOPLEFT')
	heading:SetPoint('RIGHT')
	self.weekHeading = heading

	local STATUS_TEXT = {
		open = 'Can still try',
		unknown = 'Not checked yet',
	}
	local rows = W.Table(view, {
		{ key = 'name', title = 'Character', flex = true },
		{ key = 'status', title = 'Lockout', width = 136 },
		{ key = 'week', title = 'This week', width = 58, align = 'RIGHT', figures = true },
		{ key = 'attempts', title = 'Since drop', width = 64, align = 'RIGHT', figures = true },
	}, {
		cell = function(row, col)
			if col.key == 'name' then
				local color = row.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[row.class]
				return row.name .. (row.current and T.Wrap('  you', C.faint) or ''), color and { color.r, color.g, color.b } or C.text
			elseif col.key == 'status' then
				if row.status == 'done' then
					return 'Done, resets in ' .. Format.Duration((row.reset or time()) - time()), C.muted
				elseif row.status == 'unknown' and not self.hasBosses then
					return 'No boss linked', C.faint
				end
				return STATUS_TEXT[row.status] or row.status, row.status == 'open' and C.good or C.faint
			elseif col.key == 'week' then
				return row.hasHunt and Format.Number(row.week) or '-', C.muted
			end
			return row.hasHunt and Format.Number(row.attempts) or '-'
		end,
		onEnter = function(rowFrame, row)
			GameTooltip:SetOwner(rowFrame, 'ANCHOR_RIGHT')
			GameTooltip:SetText(row.name .. (row.realm ~= '' and (' - ' .. row.realm) or ''), 1, 1, 1)
			GameTooltip:AddLine('Level ' .. row.level, C.muted[1], C.muted[2], C.muted[3])
			if row.lockout then
				local lockout = row.lockout
				local where = lockout.instance .. (lockout.difficulty ~= '' and (', ' .. lockout.difficulty) or '')
				GameTooltip:AddDoubleLine('Saved to', where, C.muted[1], C.muted[2], C.muted[3], 1, 1, 1)
				GameTooltip:AddDoubleLine('Resets', date('%A %H:%M', lockout.reset), C.muted[1], C.muted[2], C.muted[3], 1, 1, 1)
			elseif row.status == 'unknown' then
				GameTooltip:AddLine('Log in on this character once to read its lockouts.', C.muted[1], C.muted[2], C.muted[3], true)
			end
			if row.hasHunt then
				GameTooltip:AddDoubleLine('Attempts in total', Format.Number(row.total), C.muted[1], C.muted[2], C.muted[3], 1, 1, 1)
			else
				GameTooltip:AddLine('Not hunting this item. Share the hunt to count on every character.', C.muted[1], C.muted[2], C.muted[3], true)
			end
			GameTooltip:Show()
		end,
	})
	rows:SetPoint('TOPLEFT', heading, 'BOTTOMLEFT', 0, -2)
	rows:SetPoint('RIGHT')
	self.characterRows = rows

	local account = T.Text(view, 11, C.muted)
	account:SetPoint('BOTTOMLEFT', view, 'BOTTOMLEFT', 0, 98)
	account:SetPoint('RIGHT')
	self.accountText = account
	rows:SetPoint('BOTTOM', account, 'TOP', 0, 8)

	local bossHeading = W.Heading(view, 'Bosses')
	bossHeading:SetPoint('TOPLEFT', account, 'BOTTOMLEFT', 0, -12)
	bossHeading:SetPoint('RIGHT')
	bossHeading.aside:SetText('lockouts and attempts follow these')
	local bosses = T.Text(view, 11, C.text)
	bosses:SetPoint('TOPLEFT', bossHeading, 'BOTTOMLEFT', 0, -4)
	bosses:SetPoint('RIGHT')
	bosses:SetWordWrap(true)
	bosses:SetJustifyV('TOP')
	self.bossText = bosses

	local addBoss = W.Button(view, 'Add a boss', {
		onClick = function(btn)
			if not self.selected then
				return
			end
			local items = {}
			for _, boss in ipairs(LibsFarmAssistant.Lockouts:KnownBosses()) do
				items[#items + 1] = { text = boss.name, detail = boss.detail, value = boss }
			end
			W.Menu(btn, items, function(item)
				local boss = item.value
				if boss.key then
					LibsFarmAssistant.Hunts:AddSource(self.selected, boss.key)
				end
				LibsFarmAssistant.Hunts:AddBoss(self.selected, boss.name)
				self:Refresh()
			end, 'No bosses yet. Kill the boss once, or open the raid info panel on a saved character.')
		end,
		tooltip = { 'Add a boss', 'Pick the boss that drops it. Its kills count as attempts and its lockout shows for every character.' },
	})
	addBoss:SetPoint('BOTTOMLEFT')

	local clear = W.Button(view, 'Clear bosses', {
		quiet = true,
		onClick = function()
			local hunt = self.selected and LibsFarmAssistant.Hunts:Get(self.selected)
			if hunt then
				for lower in pairs(hunt.bosses or {}) do
					LibsFarmAssistant.Hunts:RemoveBoss(hunt.id, lower)
				end
				self:Refresh()
			end
		end,
		tooltip = { 'Clear bosses', 'Removes the bosses you added by hand. Mobs it dropped from stay on the Details view.' },
	})
	clear:SetPoint('LEFT', addBoss, 'RIGHT', 6, 0)

	local share = W.Button(view, 'Hunt on all characters', {
		quiet = true,
		onClick = function()
			local hunt = self.selected and LibsFarmAssistant.Hunts:Get(self.selected)
			if hunt then
				LibsFarmAssistant.Hunts:SetShared(hunt.id, not hunt.shared)
				self:Refresh()
			end
		end,
		tooltip = { 'Hunt on all characters', 'Every character you log in on starts counting this hunt, and the counts add up here.' },
	})
	share:SetPoint('BOTTOMRIGHT')
	self.shareButton = share

	view:SetScript('OnHide', W.CloseMenu)
end

---@param hunt FarmHunt
function Page:RefreshCharacters(hunt)
	local Lockouts = LibsFarmAssistant.Lockouts
	local names = Lockouts:BossNames(hunt)
	self.hasBosses = next(names) ~= nil

	local list = Lockouts:HuntRows(hunt)
	self.characterRows:SetData(list, 'No characters yet.')

	local summary = Lockouts:Summary(hunt)
	if self.hasBosses and summary.characters > 0 then
		self.weekHeading.aside:SetText(string.format('%d of %d can still try', summary.open, summary.characters))
	else
		self.weekHeading.aside:SetText('')
	end

	local account
	if summary.characters > 1 then
		account = string.format('%s attempts on the account across %d characters, %s this week.', Format.Number(summary.total), summary.characters, Format.Number(summary.week))
	else
		account = string.format('%s attempts in total, %s this week.', Format.Number(summary.total), Format.Number(summary.week))
	end
	if not hunt.shared then
		account = account .. ' Only this character counts it.'
	end
	self.accountText:SetText(account)

	local display = {}
	for _, name in pairs(names) do
		display[#display + 1] = name
	end
	table.sort(display)
	if #display > 0 then
		self.bossText:SetText(table.concat(display, ', '))
		T.Color(self.bossText, C.text)
	else
		self.bossText:SetText('None yet. Add the boss that drops it to see which characters can still try this week.')
		T.Color(self.bossText, C.muted)
	end
	self.shareButton:SetLabel(hunt.shared and 'Stop sharing' or 'Hunt on all characters')
end
