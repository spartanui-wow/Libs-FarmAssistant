---@class LibsFarmAssistant
local LibsFarmAssistant = LibStub('AceAddon-3.0'):GetAddon('Libs-FarmAssistant')

-- Every setting, inside the window. The page draws the same options table as /farm options, so the
-- two always match and a new setting appears in both without extra work. Option widths follow the
-- options table: half, normal and double take a share of a row, full takes the whole row.

local T = LibsFarmAssistant.Theme
local W = LibsFarmAssistant.Widgets
local C = T.color

local APP = 'LibsFarmAssistant'
local OWN = '_own' -- tab for a group's own settings when it also has sub-pages
local UNIT = 170 -- width of a normal option before stretching to fill the row
local GAP = 12
local ROW_GAP = 8
local CONTROL_MAX = 320
local SCROLL_STEP = 40

---@type FarmPage
local Page = { key = 'settings', title = 'Settings', icon = 'Interface\\Icons\\INV_Misc_Gear_01' }
LibsFarmAssistant.Pages.settings = Page

StaticPopupDialogs['LIBSFA_CONFIRM_SETTING'] = {
	text = '%s',
	button1 = YES or 'Yes',
	button2 = NO or 'No',
	OnAccept = function(_, data)
		if data then
			data()
		end
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
}

----------------------------------------------------------------------------------------------------
-- Reading the options table
----------------------------------------------------------------------------------------------------

local function Root()
	return LibsFarmAssistant.Options and LibsFarmAssistant.Options.optionsTable
end

local function Eval(value, info, ...)
	if type(value) == 'function' then
		return value(info, ...)
	end
	return value
end

---Options inherit get, set and disabled from the groups above them.
local function Inherited(field, opt, parents)
	if opt[field] ~= nil then
		return opt[field]
	end
	for i = #parents, 1, -1 do
		if parents[i][field] ~= nil then
			return parents[i][field]
		end
	end
	return nil
end

---@return table[] { key, opt } sorted the way the options window sorts them
local function SortedArgs(group)
	local list = {}
	for key, opt in pairs(group.args or {}) do
		list[#list + 1] = { key = key, opt = opt }
	end
	table.sort(list, function(a, b)
		local oa = type(a.opt.order) == 'number' and a.opt.order or 100
		local ob = type(b.opt.order) == 'number' and b.opt.order or 100
		if oa ~= ob then
			return oa < ob
		end
		return tostring(a.key) < tostring(b.key)
	end)
	return list
end

---The info table the options window hands to callbacks: the key path plus the option.
local function MakeEntry(opt, parents, path)
	local info = { options = Root(), option = opt, type = opt.type, arg = opt.arg, appName = APP, uiType = 'dialog', uiName = APP }
	for i, key in ipairs(path) do
		info[i] = key
	end
	local entry = { opt = opt, parents = parents, path = path, info = info }
	local disabled = false
	if Eval(Inherited('disabled', opt, parents), info) then
		disabled = true
	end
	entry.disabled = disabled
	return entry
end

local function IsHidden(opt, info)
	return Eval(opt.hidden, info) and true or false
end

local function Name(entry)
	return Eval(entry.opt.name, entry.info) or ''
end

local function Desc(entry)
	return Eval(entry.opt.desc, entry.info)
end

---@return table[] { key, text } in display order
local function SortedValues(entry)
	local values = Eval(entry.opt.values, entry.info) or {}
	local list = {}
	if entry.opt.sorting then
		for _, key in ipairs(Eval(entry.opt.sorting, entry.info) or {}) do
			if values[key] ~= nil then
				list[#list + 1] = { key = key, text = values[key] }
			end
		end
		return list
	end
	local numeric = true
	for key, text in pairs(values) do
		list[#list + 1] = { key = key, text = text }
		if type(key) ~= 'number' then
			numeric = false
		end
	end
	table.sort(list, function(a, b)
		if numeric then
			return a.key < b.key
		end
		return tostring(a.text) < tostring(b.text)
	end)
	return list
end

----------------------------------------------------------------------------------------------------
-- Widgets, pooled by kind and handed out again on every layout
----------------------------------------------------------------------------------------------------

local function ShowDesc(frame)
	local entry = frame.entry
	if not entry then
		return
	end
	local desc = Desc(entry)
	if desc and desc ~= '' then
		W.ShowTooltip(frame, Name(entry), desc)
	end
end

local function HookTooltip(frame)
	frame:HookScript('OnEnter', ShowDesc)
	frame:HookScript('OnLeave', function()
		GameTooltip:Hide()
	end)
end

local function Label(parent)
	local label = T.Text(parent, 11, C.muted)
	label:SetPoint('TOPLEFT')
	label:SetPoint('RIGHT')
	return label
end

local Kinds = {}

Kinds.heading = {
	create = function(_, parent)
		local frame = W.Heading(parent, '')
		frame:SetHeight(22)
		local rule = T.Rule(frame)
		rule:SetPoint('BOTTOMLEFT')
		rule:SetPoint('BOTTOMRIGHT')
		return frame
	end,
	bind = function(frame, entry)
		frame.title:SetText(Name(entry))
		return 22
	end,
}

Kinds.text = {
	create = function(_, parent)
		local frame = CreateFrame('Frame', nil, parent)
		frame.text = T.Text(frame, 11, C.muted)
		frame.text:SetPoint('TOPLEFT')
		frame.text:SetPoint('RIGHT')
		frame.text:SetWordWrap(true)
		frame.text:SetJustifyV('TOP')
		return frame
	end,
	bind = function(frame, entry, width)
		frame.text:SetWidth(width)
		frame.text:SetText(Name(entry))
		return math.max(14, math.ceil(frame.text:GetStringHeight() or 14))
	end,
}

Kinds.toggle = {
	create = function(page, parent)
		local check
		check = W.Check(parent, '', function(checked)
			page:Set(check.entry, checked)
		end)
		check.label:SetPoint('RIGHT', check, 'RIGHT')
		HookTooltip(check)
		return check
	end,
	bind = function(check, entry, _, page)
		check.label:SetText(Name(entry))
		check:SetChecked(page:Get(entry))
		check:EnableMouse(not entry.disabled)
		return 20
	end,
}

Kinds.select = {
	create = function(page, parent)
		local frame = CreateFrame('Frame', nil, parent)
		frame.label = Label(frame)
		local button = W.Button(frame, '', { width = 100 })
		button:SetPoint('TOPLEFT', frame.label, 'BOTTOMLEFT', 0, -4)
		button.label:ClearAllPoints()
		button.label:SetPoint('LEFT', 8, 0)
		button.label:SetPoint('RIGHT', -20, 0)
		local spot = button:CreateTexture(nil, 'OVERLAY')
		spot:SetSize(1, 1)
		spot:SetPoint('RIGHT', -10, 0)
		T.Chevron(button, C.muted):SetDirection('DOWN', spot)
		button:SetScript('OnClick', function(btn)
			local entry = frame.entry
			if not entry or entry.disabled then
				return
			end
			local current = page:Get(entry)
			local items = {}
			for _, value in ipairs(SortedValues(entry)) do
				items[#items + 1] = { text = value.text, value = value.key, detail = value.key == current and 'current' or nil }
			end
			W.Menu(btn, items, function(item)
				page:Set(entry, item.value)
			end)
		end)
		HookTooltip(button)
		frame.button = button
		return frame
	end,
	bind = function(frame, entry, width, page)
		frame.label:SetText(Name(entry))
		frame.button.entry = entry
		frame.button:SetWidth(math.min(width, CONTROL_MAX))
		local values = Eval(entry.opt.values, entry.info) or {}
		local current = page:Get(entry)
		frame.button.label:SetText(values[current] or '')
		frame.button:SetDisabled(entry.disabled)
		return 40
	end,
}

Kinds.input = {
	create = function(page, parent)
		local frame = CreateFrame('Frame', nil, parent)
		frame.label = Label(frame)
		local box = W.EditBox(frame, 100, '')
		box:SetPoint('TOPLEFT', frame.label, 'BOTTOMLEFT', 0, -4)
		box.onChange = function(text)
			if not box.binding and frame.entry then
				page:SetQuiet(frame.entry, text)
			end
		end
		box.onSubmit = function()
			page:Notify()
		end
		box:HookScript('OnEditFocusGained', function()
			page.editing = box
		end)
		box:HookScript('OnEditFocusLost', function()
			if page.editing == box then
				page.editing = nil
			end
			page:Notify()
		end)
		W.AcceptLinks(box)
		frame.box = box
		return frame
	end,
	bind = function(frame, entry, width, page)
		frame.label:SetText(Name(entry))
		local box = frame.box
		box:SetWidth(math.min(width, CONTROL_MAX))
		box.binding = true
		box:SetText(tostring(page:Get(entry) or ''))
		box.binding = false
		box:EnableMouse(not entry.disabled)
		return 38
	end,
}

local function FormatRange(opt, value)
	if opt.isPercent then
		return math.floor(value * 100 + 0.5) .. '%'
	end
	local step = opt.step or 1
	if step >= 1 then
		return tostring(math.floor(value + 0.5))
	end
	local decimals = math.min(3, math.ceil(-math.log10(step)))
	return string.format('%.' .. decimals .. 'f', value)
end

Kinds.range = {
	create = function(page, parent)
		local frame = CreateFrame('Frame', nil, parent)
		frame.label = Label(frame)
		frame.value = T.Text(frame, 11, C.text, 'figures')
		frame.value:SetPoint('TOPRIGHT')
		frame.label:SetPoint('RIGHT', frame.value, 'LEFT', -6, 0)

		local slider = CreateFrame('Slider', nil, frame)
		slider:SetOrientation('HORIZONTAL')
		slider:SetHeight(14)
		slider:SetPoint('TOPLEFT', frame.label, 'BOTTOMLEFT', 0, -6)
		slider:SetPoint('RIGHT', frame, 'RIGHT')
		slider:EnableMouseWheel(true)
		local track = slider:CreateTexture(nil, 'BACKGROUND')
		track:SetTexture(T.WHITE)
		T.Tint(track, C.lineStrong)
		track:SetHeight(2)
		track:SetPoint('LEFT')
		track:SetPoint('RIGHT')
		slider:SetThumbTexture(T.WHITE)
		local thumb = slider:GetThumbTexture()
		if thumb then
			thumb:SetSize(6, 14)
			T.Tint(thumb, C.text)
		end
		if slider.SetObeyStepOnDrag then
			slider:SetObeyStepOnDrag(true)
		end

		-- Dragging only moves the number; the setting changes on release, so a slider that
		-- resizes this window does not move under the mouse.
		slider:SetScript('OnValueChanged', function(_, value)
			if frame.binding or not frame.entry then
				return
			end
			frame.pending = value
			frame.value:SetText(FormatRange(frame.entry.opt, value))
		end)
		slider:SetScript('OnMouseDown', function()
			page.dragging = true
		end)
		slider:SetScript('OnMouseUp', function()
			page.dragging = nil
			if frame.pending ~= nil and frame.entry then
				local value = frame.pending
				frame.pending = nil
				page:Set(frame.entry, value)
			end
		end)
		slider:SetScript('OnMouseWheel', function(_, delta)
			local entry = frame.entry
			if not entry or entry.disabled then
				return
			end
			local opt = entry.opt
			local step = opt.bigStep or opt.step or 1
			local value = math.max(opt.min or 0, math.min(opt.max or 1, (page:Get(entry) or 0) + delta * step))
			page:Set(entry, value)
		end)
		HookTooltip(slider)
		frame.slider = slider
		return frame
	end,
	bind = function(frame, entry, width, page)
		local opt = entry.opt
		frame:SetWidth(math.min(width, CONTROL_MAX))
		frame.label:SetText(Name(entry))
		local value = page:Get(entry) or opt.min or 0
		frame.binding = true
		frame.pending = nil
		frame.slider.entry = entry
		frame.slider:SetMinMaxValues(opt.softMin or opt.min or 0, opt.softMax or opt.max or 1)
		frame.slider:SetValueStep(opt.step or 0.01)
		frame.slider:SetValue(value)
		frame.slider:EnableMouse(not entry.disabled)
		frame.binding = false
		frame.value:SetText(FormatRange(opt, value))
		return 38
	end,
}

Kinds.execute = {
	create = function(page, parent)
		local button
		button = W.Button(parent, '', {
			onClick = function()
				page:Run(button.entry)
			end,
		})
		HookTooltip(button)
		return button
	end,
	bind = function(button, entry, width)
		button:SetLabel(Name(entry))
		button:SetWidth(math.min(width, math.max(100, button:GetWidth())))
		button:SetDisabled(entry.disabled)
		return 24
	end,
}

Kinds.multiselect = {
	create = function(page, parent)
		local frame = CreateFrame('Frame', nil, parent)
		frame.label = Label(frame)
		frame.checks = {}
		frame.empty = T.Text(frame, 11, C.faint)
		frame.empty:SetText('Nothing here yet.')
		function frame:Check(i)
			local check = self.checks[i]
			if not check then
				check = W.Check(self, '', function(checked)
					page:Set(self.entry, check.key, checked)
				end)
				check.label:SetPoint('RIGHT', check, 'RIGHT')
				self.checks[i] = check
			end
			return check
		end
		return frame
	end,
	bind = function(frame, entry, width, page)
		local name = Name(entry)
		frame.label:SetText(name)
		local top = name ~= '' and 18 or 0
		local values = SortedValues(entry)
		local columns = width >= 450 and 3 or 2
		local colWidth = (width - (columns - 1) * GAP) / columns
		for i, value in ipairs(values) do
			local check = frame:Check(i)
			check.key = value.key
			check.label:SetText(value.text)
			check:SetChecked(page:Get(entry, value.key))
			check:SetWidth(colWidth)
			check:EnableMouse(not entry.disabled)
			check:ClearAllPoints()
			local col = (i - 1) % columns
			local row = math.floor((i - 1) / columns)
			check:SetPoint('TOPLEFT', frame, 'TOPLEFT', col * (colWidth + GAP), -top - row * 20)
			check:Show()
		end
		for i = #values + 1, #frame.checks do
			frame.checks[i]:Hide()
		end
		frame.empty:ClearAllPoints()
		frame.empty:SetPoint('TOPLEFT', frame, 'TOPLEFT', 0, -top)
		frame.empty:SetShown(#values == 0)
		return top + math.max(1, math.ceil(#values / columns)) * 20
	end,
}

----------------------------------------------------------------------------------------------------
-- Page
----------------------------------------------------------------------------------------------------

function Page:Create(parent, window)
	self.window = window
	self.parent = parent
	self.pools = {}
	for kind in pairs(Kinds) do
		self.pools[kind] = { free = {}, used = {} }
	end
	self.tabRows = {}
	local settings = LibsFarmAssistant.db.window
	self.selected = { settings.settingsTab, settings.settingsSub }

	local scroll = CreateFrame('ScrollFrame', nil, parent)
	scroll:EnableMouseWheel(true)
	scroll:SetScript('OnMouseWheel', function(_, delta)
		self:ScrollBy(-delta * SCROLL_STEP)
	end)
	scroll:SetScript('OnSizeChanged', function()
		if parent:IsVisible() then
			self:Layout()
		end
	end)
	self.scroll = scroll

	local child = CreateFrame('Frame', nil, scroll)
	child:SetSize(1, 1)
	scroll:SetScrollChild(child)
	self.child = child

	local thumb = parent:CreateTexture(nil, 'OVERLAY')
	thumb:SetTexture(T.WHITE)
	T.Tint(thumb, { 1, 1, 1, 0.22 })
	thumb:SetWidth(3)
	self.thumb = thumb

	local registry = LibStub('AceConfigRegistry-3.0', true)
	if registry then
		registry.RegisterCallback(self, 'ConfigTableChange', 'OnConfigChanged')
	end
end

function Page:OnConfigChanged(_, appName)
	if appName == APP and self.parent and self.parent:IsVisible() then
		self:Layout()
	end
end

function Page:Refresh()
	self:Layout()
end

---@param entry table
---@param ... any value, or key and value for a multiselect
function Page:Get(entry, ...)
	local get = Inherited('get', entry.opt, entry.parents)
	if type(get) == 'function' then
		return get(entry.info, ...)
	end
	return nil
end

---Writes without redrawing, for text being typed into a box.
---@param entry table
---@param ... any value, or key and value for a multiselect
function Page:SetQuiet(entry, ...)
	if not entry or entry.disabled then
		return
	end
	local set = Inherited('set', entry.opt, entry.parents)
	if type(set) == 'function' then
		set(entry.info, ...)
	end
end

---@param entry table
---@param ... any value, or key and value for a multiselect
function Page:Set(entry, ...)
	if not entry or entry.disabled then
		return
	end
	self:SetQuiet(entry, ...)
	self:Notify()
end

---Runs a button, asking first when the option wants confirmation.
function Page:Run(entry)
	if not entry or entry.disabled then
		return
	end
	local function Go()
		local func = entry.opt.func
		if type(func) == 'function' then
			func(entry.info)
		end
		self:Notify()
	end
	local confirm = Eval(Inherited('confirm', entry.opt, entry.parents), entry.info)
	if confirm then
		local text = type(confirm) == 'string' and confirm or entry.opt.confirmText or (Name(entry) .. '?')
		StaticPopup_Show('LIBSFA_CONFIRM_SETTING', text, nil, Go)
	else
		Go()
	end
end

---Tells the options window and this page that something changed.
function Page:Notify()
	local registry = LibStub('AceConfigRegistry-3.0', true)
	if registry then
		registry:NotifyChange(APP)
	else
		self:Layout()
	end
end

function Page:Acquire(kind)
	local pool = self.pools[kind]
	local widget = table.remove(pool.free)
	if not widget then
		widget = Kinds[kind].create(self, self.child)
	end
	pool.used[#pool.used + 1] = widget
	widget:Show()
	return widget
end

function Page:ReleaseAll()
	for _, pool in pairs(self.pools) do
		for i = #pool.used, 1, -1 do
			local widget = pool.used[i]
			widget:Hide()
			widget:ClearAllPoints()
			widget.entry = nil
			pool.free[#pool.free + 1] = widget
			pool.used[i] = nil
		end
	end
end

---Child groups that are their own page (not drawn inline).
local function SubPages(group, parents, path)
	local pages = {}
	local hasOwn = false
	for _, arg in ipairs(SortedArgs(group)) do
		local opt = arg.opt
		local childPath = { unpack(path) }
		childPath[#childPath + 1] = arg.key
		if opt.type == 'group' and not opt.inline then
			local entry = MakeEntry(opt, parents, childPath)
			if not IsHidden(opt, entry.info) then
				pages[#pages + 1] = { key = arg.key, label = Name(entry), opt = opt }
			end
		else
			hasOwn = true
		end
	end
	return pages, hasOwn
end

---A tab row per group, made once.
function Page:TabRow(id, items, depth)
	local row = self.tabRows[id]
	if not row then
		row = W.Segmented(self.parent, items, function(key)
			self.selected[depth] = key
			for i = depth + 1, #self.selected do
				self.selected[i] = nil
			end
			local settings = LibsFarmAssistant.db.window
			settings.settingsTab, settings.settingsSub = self.selected[1], self.selected[2]
			self.scroll:SetVerticalScroll(0)
			self:Layout()
		end)
		self.tabRows[id] = row
	end
	return row
end

function Page:Layout()
	local root = Root()
	if not root or self.editing or self.dragging or not self.parent then
		return
	end
	for _, row in pairs(self.tabRows) do
		row:Hide()
	end

	-- Tab rows: walk down the selected pages
	local group, parents, path = root, {}, {}
	local top = 0
	for depth = 1, 3 do
		local pages, hasOwn = SubPages(group, parents, path)
		if #pages == 0 then
			break
		end
		local items = {}
		if hasOwn then
			items[#items + 1] = { key = OWN, label = Name(MakeEntry(group, parents, path)) }
		end
		for _, page in ipairs(pages) do
			items[#items + 1] = { key = page.key, label = page.label }
		end
		local selected = self.selected[depth]
		local valid = false
		for _, item in ipairs(items) do
			if item.key == selected then
				valid = true
			end
		end
		if not valid then
			selected = items[1].key
			self.selected[depth] = selected
		end
		local row = self:TabRow(table.concat(path, '.') .. '#' .. #items, items, depth)
		row:ClearAllPoints()
		row:SetPoint('TOPLEFT', self.parent, 'TOPLEFT', 0, -top)
		row:Select(selected)
		row:Show()
		top = top + 22 + 10
		if selected == OWN then
			break
		end
		parents = { unpack(parents) }
		parents[#parents + 1] = group
		path = { unpack(path) }
		path[#path + 1] = selected
		group = group.args[selected]
	end

	self.scroll:ClearAllPoints()
	self.scroll:SetPoint('TOPLEFT', self.parent, 'TOPLEFT', 0, -top)
	self.scroll:SetPoint('BOTTOMRIGHT', self.parent, 'BOTTOMRIGHT', -8, 0)

	local width = self.scroll:GetWidth()
	if not width or width < 100 then
		width = 560
	end
	self.width = width
	self.child:SetWidth(width)

	self:ReleaseAll()
	local cursor = { x = 0, y = 0, used = 0, height = 0 }
	self.cap = math.max(1, math.floor((width + GAP) / (UNIT + GAP)))
	self.unit = (width - (self.cap - 1) * GAP) / self.cap
	self:Draw(group, parents, path, cursor)
	self:NewRow(cursor)

	self.child:SetHeight(math.max(1, cursor.y))
	self:ScrollBy(0)
end

function Page:NewRow(cursor)
	if cursor.used > 0 or cursor.height > 0 then
		cursor.y = cursor.y + cursor.height + ROW_GAP
	end
	cursor.x, cursor.used, cursor.height = 0, 0, 0
end

local WIDTH_UNITS = { half = 0.5, normal = 1, double = 2 }
local FULL_ROW = { heading = true, text = true, multiselect = true }

---Places one option in the flowing rows.
function Page:Place(kind, entry, cursor)
	local opt = entry.opt
	local units = (opt.width == 'full' or FULL_ROW[kind]) and self.cap or WIDTH_UNITS[opt.width or 'normal'] or 1
	units = math.min(units, self.cap)
	if cursor.used > 0 and cursor.used + units > self.cap + 0.001 then
		self:NewRow(cursor)
	end
	if kind == 'heading' and cursor.y > 0 then
		cursor.y = cursor.y + 6
	end
	local width = units >= self.cap and self.width or (units * self.unit + math.max(0, math.ceil(units) - 1) * GAP)
	local widget = self:Acquire(kind)
	widget.entry = entry
	widget:SetWidth(width)
	local height = Kinds[kind].bind(widget, entry, width, self)
	widget:SetHeight(height)
	widget:SetAlpha(entry.disabled and 0.45 or 1)
	widget:SetPoint('TOPLEFT', self.child, 'TOPLEFT', cursor.x, -cursor.y)
	cursor.x = cursor.x + width + GAP
	cursor.used = cursor.used + units
	cursor.height = math.max(cursor.height, height)
	if units >= self.cap then
		self:NewRow(cursor)
	end
end

local KIND_FOR = {
	header = 'heading',
	description = 'text',
	toggle = 'toggle',
	select = 'select',
	input = 'input',
	range = 'range',
	execute = 'execute',
	multiselect = 'multiselect',
}

---Draws a group's own settings; inline groups get a heading and their settings under it.
function Page:Draw(group, parents, path, cursor)
	local childParents = { unpack(parents) }
	childParents[#childParents + 1] = group
	for _, arg in ipairs(SortedArgs(group)) do
		local opt = arg.opt
		local childPath = { unpack(path) }
		childPath[#childPath + 1] = arg.key
		local entry = MakeEntry(opt, childParents, childPath)
		if not IsHidden(opt, entry.info) then
			if opt.type == 'group' then
				if opt.inline then
					self:Place('heading', entry, cursor)
					self:Draw(opt, childParents, childPath, cursor)
				end
			elseif KIND_FOR[opt.type] then
				self:Place(KIND_FOR[opt.type], entry, cursor)
			end
		end
	end
end

function Page:ScrollBy(delta)
	local scroll = self.scroll
	local height = scroll:GetHeight() or 0
	local max = math.max(0, (self.child:GetHeight() or 0) - height)
	local offset = math.max(0, math.min(max, (scroll:GetVerticalScroll() or 0) + delta))
	scroll:SetVerticalScroll(offset)
	local thumb = self.thumb
	thumb:SetShown(max > 0)
	if max > 0 and height > 0 then
		local total = height + max
		local size = math.max(16, height * height / total)
		thumb:SetHeight(size)
		thumb:ClearAllPoints()
		thumb:SetPoint('TOPRIGHT', scroll, 'TOPRIGHT', 8, -(height - size) * (offset / max))
	end
end
