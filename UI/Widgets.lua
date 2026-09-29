---@class LibsFarmAssistant
local LibsFarmAssistant = LibStub('AceAddon-3.0'):GetAddon('Libs-FarmAssistant')

-- The small set of controls every screen is built from. Plain frames and textures only, so they
-- look and behave the same on every client, and no other addon is needed to draw them.

---@class LibsFarmAssistant.Widgets
local W = {}
LibsFarmAssistant.Widgets = W

local T = LibsFarmAssistant.Theme
local C = T.color

----------------------------------------------------------------------------------------------------
-- Tooltips
----------------------------------------------------------------------------------------------------

---@param owner Frame
---@param title string
---@param ... string lines
function W.ShowTooltip(owner, title, ...)
	GameTooltip:SetOwner(owner, 'ANCHOR_TOP')
	GameTooltip:SetText(title, 1, 1, 1)
	for i = 1, select('#', ...) do
		local line = select(i, ...)
		if line then
			GameTooltip:AddLine(line, C.muted[1], C.muted[2], C.muted[3], true)
		end
	end
	GameTooltip:Show()
end

---@param frame Frame
---@param title string
---@param ... string
function W.SetTooltip(frame, title, ...)
	local lines = { ... }
	frame:HookScript('OnEnter', function(self)
		W.ShowTooltip(self, title, unpack(lines))
	end)
	frame:HookScript('OnLeave', function()
		GameTooltip:Hide()
	end)
end

---Shows the game's own item tooltip, with our lines added by the tooltip hooks.
---@param owner Frame
---@param itemID number
function W.ShowItemTooltip(owner, itemID)
	GameTooltip:SetOwner(owner, 'ANCHOR_RIGHT')
	if GameTooltip.SetItemByID then
		GameTooltip:SetItemByID(itemID)
	else
		GameTooltip:SetHyperlink('item:' .. itemID)
	end
	GameTooltip:Show()
end

---@param itemID number
---@return boolean handled
function W.ModifiedItemClick(itemID)
	if not IsModifiedClick or not IsModifiedClick() then
		return false
	end
	local _, link = LibsFarmAssistant.Compat.ItemInfo(itemID)
	if link and HandleModifiedItemClick then
		HandleModifiedItemClick(link)
		return true
	end
	return false
end

----------------------------------------------------------------------------------------------------
-- Buttons
----------------------------------------------------------------------------------------------------

local function PaintButton(btn)
	local quiet = btn.quiet
	local fill
	if btn.pressed then
		fill = C.selected
	elseif btn.hover then
		fill = C.selected
	elseif quiet then
		fill = { 0, 0, 0, 0 }
	else
		fill = { 1, 1, 1, 0.04 }
	end
	T.Tint(btn.bg, fill)
	T.ColorBorder(btn.border, (btn.pressed or not quiet) and C.lineStrong or C.line)
	local textColor = (quiet and not btn.hover and not btn.pressed) and C.muted or C.text
	if btn.label then
		T.Color(btn.label, btn.color or textColor)
	end
	btn:SetAlpha(btn.disabled and 0.4 or 1)
end

---@param parent Frame
---@param text string
---@param opts? table { quiet = bool, width = number, height = number, onClick = fn, tooltip = {title, ...} }
---@return Button
function W.Button(parent, text, opts)
	opts = opts or {}
	local btn = CreateFrame('Button', nil, parent)
	btn:SetHeight(opts.height or 22)
	btn.quiet = opts.quiet
	btn.bg = T.Fill(btn, { 1, 1, 1, 0.04 })
	btn.border = T.Border(btn, C.lineStrong)
	btn.label = T.Text(btn, opts.size or 11, C.text)
	btn.label:SetPoint('CENTER')
	btn:RegisterForClicks('AnyUp')

	function btn:SetLabel(value)
		self.label:SetText(value)
		if not opts.width then
			self:SetWidth(math.max(40, math.floor(self.label:GetStringWidth() + 20)))
		end
	end
	function btn:SetPressed(pressed)
		self.pressed = pressed
		PaintButton(self)
	end
	function btn:SetDisabled(disabled)
		self.disabled = disabled
		self:EnableMouse(not disabled)
		PaintButton(self)
	end
	function btn:SetQuiet(quiet)
		self.quiet = quiet
		PaintButton(self)
	end

	btn:SetScript('OnEnter', function(self)
		self.hover = true
		PaintButton(self)
	end)
	btn:SetScript('OnLeave', function(self)
		self.hover = false
		PaintButton(self)
	end)
	if opts.onClick then
		btn:SetScript('OnClick', opts.onClick)
	end
	if opts.width then
		btn:SetWidth(opts.width)
	end
	btn:SetLabel(text)
	if opts.tooltip then
		W.SetTooltip(btn, unpack(opts.tooltip))
	end
	PaintButton(btn)
	return btn
end

local function Bar(parent, w, h, rotation, x, y)
	local tex = parent:CreateTexture(nil, 'OVERLAY')
	tex:SetTexture(T.WHITE)
	tex:SetSize(w, h)
	tex:SetPoint('CENTER', parent, 'CENTER', x or 0, y or 0)
	if rotation and tex.SetRotation then
		tex:SetRotation(rotation)
	end
	return tex
end

-- Glyphs drawn from bars, so they stay crisp at any scale and need no font support.
local GLYPHS = {
	pause = function(btn)
		return { Bar(btn, 2, 9, nil, -2.5, 0), Bar(btn, 2, 9, nil, 2.5, 0) }
	end,
	plus = function(btn)
		return { Bar(btn, 9, 1.5), Bar(btn, 1.5, 9) }
	end,
	close = function(btn)
		return { Bar(btn, 11, 1.5, math.pi / 4), Bar(btn, 11, 1.5, -math.pi / 4) }
	end,
	resume = function(btn)
		return { Bar(btn, 7, 1.8, -math.pi / 4 - 0.25, 0, 2.2), Bar(btn, 7, 1.8, math.pi / 4 + 0.25, 0, -2.2) }
	end,
	menu = function(btn)
		return { Bar(btn, 9, 1.5, nil, 0, 3), Bar(btn, 9, 1.5), Bar(btn, 9, 1.5, nil, 0, -3) }
	end,
	tracker = function(btn)
		return { Bar(btn, 10, 1.5, nil, 0, 3.5), Bar(btn, 7, 1.5, nil, -1.5, 0), Bar(btn, 10, 1.5, nil, 0, -3.5) }
	end,
}

---A square button that draws a small glyph.
---@param parent Frame
---@param glyph string
---@param tooltip? table { title, ... }
---@return Button
function W.IconButton(parent, glyph, tooltip)
	local btn = CreateFrame('Button', nil, parent)
	btn:SetSize(22, 22)
	btn.bg = T.Fill(btn, { 0, 0, 0, 0 })
	btn.border = T.Border(btn, C.line)
	btn:RegisterForClicks('AnyUp')

	function btn:SetGlyph(name)
		for _, tex in ipairs(self.glyph or {}) do
			tex:Hide()
		end
		self.glyphs = self.glyphs or {}
		if not self.glyphs[name] then
			self.glyphs[name] = GLYPHS[name](self)
		end
		self.glyph = self.glyphs[name]
		for _, tex in ipairs(self.glyph) do
			tex:Show()
		end
		self:Paint()
	end
	function btn:Paint()
		local c = self.hover and C.text or C.muted
		for _, tex in ipairs(self.glyph or {}) do
			tex:SetVertexColor(c[1], c[2], c[3], 1)
		end
		T.Tint(self.bg, self.hover and C.hover or { 0, 0, 0, 0 })
	end
	btn:SetScript('OnEnter', function(self)
		self.hover = true
		self:Paint()
	end)
	btn:SetScript('OnLeave', function(self)
		self.hover = false
		self:Paint()
	end)
	btn:SetGlyph(glyph)
	if tooltip then
		W.SetTooltip(btn, unpack(tooltip))
	end
	return btn
end

---A row of joined buttons where one is selected.
---@param parent Frame
---@param items table[] { key, label }
---@param onSelect fun(key: string)
---@return Frame
function W.Segmented(parent, items, onSelect)
	local frame = CreateFrame('Frame', nil, parent)
	frame:SetHeight(22)
	frame.border = T.Border(frame, C.line)
	frame.buttons = {}
	local x = 0
	for i, item in ipairs(items) do
		local btn = CreateFrame('Button', nil, frame)
		btn.key = item.key
		btn.bg = T.Fill(btn, { 0, 0, 0, 0 })
		btn.label = T.Text(btn, 11, C.muted)
		btn.label:SetText(item.label)
		btn.label:SetPoint('CENTER')
		local width = math.floor(btn.label:GetStringWidth() + 18)
		btn:SetSize(width, 22)
		btn:SetPoint('LEFT', frame, 'LEFT', x, 0)
		x = x + width
		if i < #items then
			local sep = frame:CreateTexture(nil, 'BORDER')
			sep:SetTexture(T.WHITE)
			T.Tint(sep, C.line)
			sep:SetWidth(T.Pixel(frame))
			sep:SetPoint('TOPLEFT', btn, 'TOPRIGHT')
			sep:SetPoint('BOTTOMLEFT', btn, 'BOTTOMRIGHT')
		end
		btn:SetScript('OnClick', function(self)
			frame:Select(self.key)
			onSelect(self.key)
		end)
		btn:SetScript('OnEnter', function(self)
			self.hover = true
			frame:Paint()
			if item.tooltip then
				W.ShowTooltip(self, item.label, item.tooltip)
			end
		end)
		btn:SetScript('OnLeave', function(self)
			self.hover = false
			frame:Paint()
			GameTooltip:Hide()
		end)
		frame.buttons[i] = btn
	end
	frame:SetWidth(x)

	function frame:Paint()
		for _, btn in ipairs(self.buttons) do
			local on = btn.key == self.selected
			T.Tint(btn.bg, on and C.selected or (btn.hover and C.hover or { 0, 0, 0, 0 }))
			T.Color(btn.label, (on or btn.hover) and C.text or C.muted)
		end
	end
	function frame:Select(key)
		self.selected = key
		self:Paint()
	end
	return frame
end

---A toggle chip for filters.
---@param parent Frame
---@param text string
---@param color table|nil
---@param onToggle fun(pressed: boolean)
---@return Button
function W.Chip(parent, text, color, onToggle)
	local chip = CreateFrame('Button', nil, parent)
	chip:SetHeight(18)
	chip.bg = T.Fill(chip, { 0, 0, 0, 0 })
	chip.border = T.Border(chip, C.line)
	chip.label = T.Text(chip, 10, color or C.muted)
	chip.label:SetText(text)
	chip.label:SetPoint('CENTER')
	chip:SetWidth(math.floor(chip.label:GetStringWidth() + 14))
	chip.color = color

	function chip:SetPressed(pressed)
		self.pressed = pressed
		T.Tint(self.bg, pressed and C.selected or { 0, 0, 0, 0 })
		T.ColorBorder(self.border, pressed and C.lineStrong or C.line)
		self.label:SetAlpha(pressed and 1 or 0.45)
	end
	chip:SetScript('OnClick', function(self)
		self:SetPressed(not self.pressed)
		onToggle(self.pressed)
	end)
	chip:SetPressed(true)
	return chip
end

----------------------------------------------------------------------------------------------------
-- Text input
----------------------------------------------------------------------------------------------------

---@param parent Frame
---@param width number
---@param placeholder string
---@return EditBox
function W.EditBox(parent, width, placeholder)
	local box = CreateFrame('EditBox', nil, parent)
	box:SetSize(width, 20)
	box:SetAutoFocus(false)
	T.SetFont(box, 11)
	box:SetTextColor(C.text[1], C.text[2], C.text[3])
	box:SetTextInsets(6, 6, 0, 0)
	box.bg = T.Fill(box, C.well)
	box.border = T.Border(box, C.line)
	box.placeholder = T.Text(box, 11, C.faint)
	box.placeholder:SetPoint('LEFT', 6, 0)
	box.placeholder:SetText(placeholder)

	local function Update(self)
		self.placeholder:SetShown(self:GetText() == '' and not self:HasFocus())
		T.ColorBorder(self.border, self:HasFocus() and C.lineStrong or C.line)
	end
	box:SetScript('OnEditFocusGained', Update)
	box:SetScript('OnEditFocusLost', Update)
	box:SetScript('OnTextChanged', function(self, userInput)
		Update(self)
		if self.onChange then
			self.onChange(self:GetText(), userInput)
		end
	end)
	box:SetScript('OnEscapePressed', function(self)
		self:ClearFocus()
	end)
	box:SetScript('OnEnterPressed', function(self)
		if self.onSubmit then
			self.onSubmit(self:GetText())
		end
		self:ClearFocus()
	end)
	return box
end

-- Shift-clicking an item while one of our boxes has focus inserts the link there.
local linkTargets = {}

---@param box EditBox
function W.AcceptLinks(box)
	linkTargets[#linkTargets + 1] = box
end

local function InsertLink(link)
	if not link then
		return
	end
	for _, box in ipairs(linkTargets) do
		if box:IsVisible() and box:HasFocus() then
			box:SetText(link)
			if box.onSubmit then
				box.onSubmit(link)
			end
			return true
		end
	end
end

if ChatFrameUtil and ChatFrameUtil.InsertLink then
	hooksecurefunc(ChatFrameUtil, 'InsertLink', InsertLink)
end
if ChatEdit_InsertLink then
	hooksecurefunc('ChatEdit_InsertLink', InsertLink)
end

----------------------------------------------------------------------------------------------------
-- Headings and bars
----------------------------------------------------------------------------------------------------

---A section heading in gold with an optional note on the right.
---@param parent Frame
---@param text string
---@return Frame heading with .title and .aside
function W.Heading(parent, text)
	local frame = CreateFrame('Frame', nil, parent)
	frame:SetHeight(18)
	frame.title = T.Text(frame, 12, C.gold)
	frame.title:SetPoint('LEFT')
	frame.title:SetText(text)
	frame.aside = T.Text(frame, 10, C.faint)
	frame.aside:SetPoint('RIGHT')
	return frame
end

---A flat progress bar with an optional second segment (rested XP, pending gains).
---@param parent Frame
---@param height number
---@return Frame
function W.Bar(parent, height)
	local bar = CreateFrame('Frame', nil, parent)
	bar:SetHeight(height)
	bar.track = T.Fill(bar, C.track, 'BACKGROUND')
	bar.fill = bar:CreateTexture(nil, 'ARTWORK')
	bar.fill:SetTexture(T.WHITE)
	bar.fill:SetPoint('TOPLEFT')
	bar.fill:SetPoint('BOTTOMLEFT')
	bar.extra = bar:CreateTexture(nil, 'ARTWORK', nil, -1)
	bar.extra:SetTexture(T.WHITE)
	bar.extra:SetPoint('TOPLEFT', bar.fill, 'TOPRIGHT')
	bar.extra:SetPoint('BOTTOMLEFT', bar.fill, 'BOTTOMRIGHT')
	bar.value, bar.extraValue = 0, 0

	function bar:Layout()
		local width = self:GetWidth() or 0
		local value = math.max(0, math.min(1, self.value or 0))
		local extra = math.max(0, math.min(1 - value, self.extraValue or 0))
		self.fill:SetWidth(math.max(0.01, width * value))
		self.fill:SetShown(value > 0)
		self.extra:SetWidth(math.max(0.01, width * extra))
		self.extra:SetShown(extra > 0)
	end
	---@param value number 0-1
	---@param color table
	function bar:SetValue(value, color)
		self.value = value
		if color then
			T.Tint(self.fill, color)
		end
		self:Layout()
	end
	---@param value number 0-1
	---@param color table
	function bar:SetExtra(value, color)
		self.extraValue = value
		if color then
			T.Tint(self.extra, color)
		end
		self:Layout()
	end
	bar:SetScript('OnSizeChanged', bar.Layout)
	return bar
end

----------------------------------------------------------------------------------------------------
-- Scrolling list and table
----------------------------------------------------------------------------------------------------

---A list that draws only the rows it can show, so long loot tables stay cheap.
---@param parent Frame
---@param opts table { rowHeight, createRow(row), updateRow(row, data, index), onClick(data, button), onEnter(row, data), empty }
---@return Frame
function W.List(parent, opts)
	local list = CreateFrame('Frame', nil, parent)
	list.rowHeight = opts.rowHeight or T.size.row
	list.rows = {}
	list.data = {}
	list.offset = 0
	list:EnableMouseWheel(true)
	if list.SetClipsChildren then
		list:SetClipsChildren(true)
	end

	list.scrollTrack = list:CreateTexture(nil, 'OVERLAY')
	list.scrollTrack:SetTexture(T.WHITE)
	T.Tint(list.scrollTrack, { 1, 1, 1, 0.04 })
	list.scrollTrack:SetWidth(3)
	list.scrollTrack:SetPoint('TOPRIGHT')
	list.scrollTrack:SetPoint('BOTTOMRIGHT')
	list.scrollThumb = list:CreateTexture(nil, 'OVERLAY', nil, 1)
	list.scrollThumb:SetTexture(T.WHITE)
	T.Tint(list.scrollThumb, { 1, 1, 1, 0.22 })
	list.scrollThumb:SetWidth(3)

	list.empty = T.Text(list, 11, C.muted)
	list.empty:SetPoint('TOPLEFT', 4, -8)
	list.empty:SetPoint('RIGHT', -8, 0)
	list.empty:SetWordWrap(true)
	list.empty:SetJustifyV('TOP')

	function list:Visible()
		return math.max(1, math.floor((self:GetHeight() or 0) / self.rowHeight))
	end

	function list:MaxOffset()
		return math.max(0, #self.data - self:Visible())
	end

	function list:Row(i)
		local row = self.rows[i]
		if not row then
			row = CreateFrame('Button', nil, self)
			row:SetHeight(self.rowHeight)
			row:SetPoint('TOPLEFT', self, 'TOPLEFT', 0, -(i - 1) * self.rowHeight)
			row:SetPoint('RIGHT', self, 'RIGHT', -6, 0)
			row.hl = T.Fill(row, { 0, 0, 0, 0 })
			row.rule = T.Rule(row)
			row.rule:SetPoint('BOTTOMLEFT')
			row.rule:SetPoint('BOTTOMRIGHT')
			row:RegisterForClicks('AnyUp')
			row:SetScript('OnEnter', function(r)
				r.hover = true
				list:PaintRow(r)
				if opts.onEnter and r.data then
					opts.onEnter(r, r.data)
				end
			end)
			row:SetScript('OnLeave', function(r)
				r.hover = false
				list:PaintRow(r)
				GameTooltip:Hide()
			end)
			row:SetScript('OnClick', function(r, button)
				if opts.onClick and r.data then
					opts.onClick(r.data, button, r)
				end
			end)
			opts.createRow(row, self)
			self.rows[i] = row
		end
		return row
	end

	function list:PaintRow(row)
		local selected = self.selectedKey ~= nil and row.data and opts.keyOf and opts.keyOf(row.data) == self.selectedKey
		T.Tint(row.hl, selected and C.selected or (row.hover and opts.onClick and C.hover or { 0, 0, 0, 0 }))
	end

	function list:Refresh()
		local visible = self:Visible()
		self.offset = math.max(0, math.min(self.offset, self:MaxOffset()))
		for i = 1, math.max(visible, #self.rows) do
			local index = self.offset + i
			local data = self.data[index]
			if i <= visible and data then
				local row = self:Row(i)
				row.data = data
				row.index = index
				opts.updateRow(row, data, index)
				self:PaintRow(row)
				row:Show()
			elseif self.rows[i] then
				self.rows[i].data = nil
				self.rows[i]:Hide()
			end
		end

		local total = #self.data
		local show = total > visible
		self.scrollTrack:SetShown(show)
		self.scrollThumb:SetShown(show)
		if show then
			local height = self:GetHeight()
			local thumb = math.max(12, height * visible / total)
			local y = (height - thumb) * (self.offset / math.max(1, self:MaxOffset()))
			self.scrollThumb:SetHeight(thumb)
			self.scrollThumb:ClearAllPoints()
			self.scrollThumb:SetPoint('TOPRIGHT', self, 'TOPRIGHT', 0, -y)
		end

		self.empty:SetShown(total == 0 and self.emptyText ~= nil)
		self.empty:SetText(self.emptyText or '')
	end

	---@param data table[]
	---@param emptyText? string
	function list:SetData(data, emptyText)
		self.data = data or {}
		self.emptyText = emptyText
		self:Refresh()
	end

	function list:Select(key)
		self.selectedKey = key
		for _, row in ipairs(self.rows) do
			if row:IsShown() then
				self:PaintRow(row)
			end
		end
	end

	list:SetScript('OnMouseWheel', function(self, delta)
		self.offset = math.max(0, math.min(self:MaxOffset(), self.offset - delta * 3))
		self:Refresh()
	end)
	list:SetScript('OnSizeChanged', function(self)
		self:Refresh()
	end)
	return list
end

---Column spec: { key, title, width (px) or flex = true, align = 'LEFT'|'RIGHT', figures = bool,
---icon = bool, sort = function(a, b) }
---@param parent Frame
---@param columns table[]
---@param opts table { header = bool, onClick, onEnter, keyOf, cell(data, column) -> text, r, g, b, icon, sortKey, sortDesc, onSort }
---@return Frame table with :SetData(rows, emptyText) and :SetSort(key, desc)
function W.Table(parent, columns, opts)
	local frame = CreateFrame('Frame', nil, parent)
	local headerHeight = opts.header == false and 0 or 18
	frame.sortKey = opts.sortKey
	frame.sortDesc = opts.sortDesc ~= false

	local function LayoutCells(container, cells)
		local fixed = 0
		local flexCount = 0
		for _, col in ipairs(columns) do
			if col.flex then
				flexCount = flexCount + 1
			else
				fixed = fixed + col.width
			end
		end
		local width = (container:GetWidth() or 0) - 6
		local flexWidth = math.max(40, (width - fixed) / math.max(1, flexCount))
		local x = 0
		for i, col in ipairs(columns) do
			local w = col.flex and flexWidth or col.width
			local cell = cells[i]
			cell:ClearAllPoints()
			cell:SetPoint('LEFT', container, 'LEFT', x + 4 + (cell.iconOffset or 0), 0)
			cell:SetWidth(math.max(1, w - 8 - (cell.iconOffset or 0)))
			if cell.icon then
				cell.icon:ClearAllPoints()
				cell.icon:SetPoint('LEFT', container, 'LEFT', x + 4, 0)
			end
			x = x + w
		end
	end

	if headerHeight > 0 then
		local header = CreateFrame('Frame', nil, frame)
		header:SetHeight(headerHeight)
		header:SetPoint('TOPLEFT')
		header:SetPoint('TOPRIGHT')
		local rule = T.Rule(header, C.lineStrong)
		rule:SetPoint('BOTTOMLEFT')
		rule:SetPoint('BOTTOMRIGHT')
		header.cells = {}
		for i, col in ipairs(columns) do
			local btn = CreateFrame('Button', nil, header)
			btn:SetHeight(headerHeight)
			local label = T.Text(btn, 10, C.faint)
			label:SetAllPoints()
			label:SetJustifyH(col.align or 'LEFT')
			label:SetText(col.title or '')
			btn.label = label
			btn.column = col
			if col.sort then
				btn:SetScript('OnClick', function()
					if frame.sortKey == col.key then
						frame.sortDesc = not frame.sortDesc
					else
						frame.sortKey = col.key
						frame.sortDesc = col.defaultDesc ~= false
					end
					frame:Resort()
					if opts.onSort then
						opts.onSort(frame.sortKey, frame.sortDesc)
					end
				end)
				btn:SetScript('OnEnter', function(b)
					T.Color(b.label, C.text)
				end)
				btn:SetScript('OnLeave', function(b)
					T.Color(b.label, b.column.key == frame.sortKey and C.text or C.faint)
				end)
			end
			header.cells[i] = btn
		end
		header:SetScript('OnSizeChanged', function(self)
			LayoutCells(self, self.cells)
		end)
		frame.header = header
	end

	local list = W.List(frame, {
		rowHeight = opts.rowHeight or T.size.row,
		keyOf = opts.keyOf,
		onClick = opts.onClick,
		onEnter = opts.onEnter,
		createRow = function(row)
			row.cells = {}
			for i, col in ipairs(columns) do
				local cell = T.Text(row, col.figures and T.size.body or T.size.body, C.text, col.figures and 'figures' or 'words')
				cell:SetJustifyH(col.align or 'LEFT')
				if col.icon then
					cell.icon = T.Icon(row, 16)
					cell.iconOffset = 22
				end
				row.cells[i] = cell
			end
			row:SetScript('OnSizeChanged', function(self)
				LayoutCells(self, self.cells)
			end)
			LayoutCells(row, row.cells)
		end,
		updateRow = function(row, data)
			for i, col in ipairs(columns) do
				local text, color, icon = opts.cell(data, col)
				local cell = row.cells[i]
				cell:SetText(text or '')
				color = color or C.text
				cell:SetTextColor(color[1], color[2], color[3], color[4] or 1)
				if cell.icon then
					cell.icon:SetTexture(icon)
					cell.icon:SetShown(icon ~= nil)
					cell.icon.edge:SetShown(icon ~= nil)
				end
			end
			T.Tint(row.rule, (opts.ruleOf and opts.ruleOf(data)) or C.line)
		end,
	})
	list:SetPoint('TOPLEFT', frame, 'TOPLEFT', 0, -headerHeight)
	list:SetPoint('BOTTOMRIGHT')
	frame.list = list

	function frame:PaintHeader()
		if not self.header then
			return
		end
		for _, btn in ipairs(self.header.cells) do
			T.Color(btn.label, btn.column.key == self.sortKey and C.text or C.faint)
		end
	end

	function frame:Resort()
		local column
		for _, col in ipairs(columns) do
			if col.key == self.sortKey then
				column = col
			end
		end
		if column and column.sort and self.rows then
			local desc = self.sortDesc
			table.sort(self.rows, function(a, b)
				if desc then
					return column.sort(b, a)
				end
				return column.sort(a, b)
			end)
		end
		self:PaintHeader()
		list:SetData(self.rows, self.emptyText)
	end

	---@param rows table[]
	---@param emptyText? string
	function frame:SetData(rows, emptyText)
		self.rows = rows
		self.emptyText = emptyText
		self:Resort()
	end

	function frame:Select(key)
		list:Select(key)
	end

	return frame
end
