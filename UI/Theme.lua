---@class LibsFarmAssistant
local LibsFarmAssistant = LibStub('AceAddon-3.0'):GetAddon('Libs-FarmAssistant')

-- Visual tokens, shared with the Lib's family: flat near-black panes, square corners, 1px
-- hairlines. Saturated color only where it means something in the game: item quality, standing,
-- gold. Friz carries words; Arial Narrow carries figures, the way the game's own number fonts do.

---@class LibsFarmAssistant.Theme
local T = {}
LibsFarmAssistant.Theme = T

local WHITE = 'Interface\\Buttons\\WHITE8X8'
T.WHITE = WHITE

T.FONT_WORDS = STANDARD_TEXT_FONT or 'Fonts\\FRIZQT__.TTF'
T.FONT_FIGURES = 'Fonts\\ARIALN.TTF'

T.color = {
	plate = { 0.047, 0.051, 0.059, 0.92 },
	plate2 = { 0.078, 0.086, 0.102, 0.94 },
	well = { 0, 0, 0, 0.35 },
	line = { 1, 1, 1, 0.09 },
	lineStrong = { 1, 1, 1, 0.18 },
	hover = { 1, 1, 1, 0.06 },
	selected = { 1, 1, 1, 0.11 },
	text = { 0.91, 0.90, 0.88 },
	muted = { 0.61, 0.61, 0.64 },
	faint = { 0.45, 0.45, 0.47 },
	gold = { 1, 0.82, 0 },
	good = { 0.25, 0.84, 0.42 },
	bad = { 0.88, 0.35, 0.31 },
	warn = { 0.91, 0.77, 0.28 },
	track = { 1, 1, 1, 0.07 },
	xp = { 0.54, 0.33, 0.84 },
	rested = { 0.31, 0.55, 1, 0.45 },
	claim = { 0.1, 1, 0.1 },
}

T.size = {
	body = 12,
	small = 10,
	nav = 12,
	figure = 13,
	title = 14,
	big = 24,
	row = 20,
	header = 34,
	footer = 22,
	nav_width = 136,
	pad = 12,
}

-- Standing and quality share one ladder, the one players already read on items.
T.quality = {
	[0] = { 0.62, 0.62, 0.62 },
	[1] = { 1, 1, 1 },
	[2] = { 0.12, 1, 0 },
	[3] = { 0, 0.44, 0.87 },
	[4] = { 0.64, 0.21, 0.93 },
	[5] = { 1, 0.5, 0 },
	[6] = { 0.9, 0.8, 0.5 },
	[7] = { 0, 0.8, 1 },
	[8] = { 0, 0.8, 1 },
}

T.standing = {
	[1] = { 0.8, 0.13, 0.13 },
	[2] = { 0.8, 0.25, 0 },
	[3] = { 0.75, 0.27, 0 },
	[4] = { 0.46, 0.49, 0.56 },
	[5] = { 0.04, 0.92, 0.30 },
	[6] = { 0.10, 0.55, 1 },
	[7] = { 0.64, 0.21, 0.93 },
	[8] = { 1, 0.5, 0 },
}

---@param quality number|nil
---@return number r, number g, number b
function T.QualityRGB(quality)
	local c = T.quality[quality or 1] or T.quality[1]
	return c[1], c[2], c[3]
end

---@param quality number|nil
---@return string hex 'ffrrggbb'
function T.QualityHex(quality)
	local r, g, b = T.QualityRGB(quality)
	return string.format('ff%02x%02x%02x', r * 255, g * 255, b * 255)
end

---@param color table
---@return string
function T.Hex(color)
	return string.format('ff%02x%02x%02x', color[1] * 255, color[2] * 255, color[3] * 255)
end

---@param text string
---@param color table
---@return string
function T.Wrap(text, color)
	return '|c' .. T.Hex(color) .. text .. '|r'
end

---One physical pixel in the frame's own units.
---@param frame? Frame
---@return number
function T.Pixel(frame)
	local _, height = GetPhysicalScreenSize and GetPhysicalScreenSize()
	local scale = (frame or UIParent):GetEffectiveScale()
	if not height or height == 0 or not scale or scale == 0 then
		return 1
	end
	return 768 / height / scale
end

---@param parent Frame
---@param color table
---@param layer? string
---@param sublevel? number
---@return Texture
function T.Fill(parent, color, layer, sublevel)
	local tex = parent:CreateTexture(nil, layer or 'BACKGROUND', nil, sublevel)
	tex:SetTexture(WHITE)
	tex:SetVertexColor(color[1], color[2], color[3], color[4] or 1)
	tex:SetAllPoints(parent)
	return tex
end

---@param tex Texture
---@param color table
function T.Tint(tex, color)
	tex:SetVertexColor(color[1], color[2], color[3], color[4] or 1)
end

---A 1px border as four textures. Returns the list so it can be recolored.
---@param frame Frame
---@param color table
---@param layer? string
---@return Texture[]
function T.Border(frame, color, layer)
	local lines = {}
	for i, side in ipairs({ 'TOP', 'BOTTOM', 'LEFT', 'RIGHT' }) do
		local tex = frame:CreateTexture(nil, layer or 'BORDER')
		tex:SetTexture(WHITE)
		tex:SetVertexColor(color[1], color[2], color[3], color[4] or 1)
		tex.side = side
		lines[i] = tex
	end
	T.LayoutBorder(frame, lines)
	return lines
end

---@param frame Frame
---@param lines Texture[]
function T.LayoutBorder(frame, lines)
	local px = T.Pixel(frame)
	for _, tex in ipairs(lines) do
		tex:ClearAllPoints()
		local side = tex.side
		if side == 'TOP' or side == 'BOTTOM' then
			tex:SetPoint(side .. 'LEFT', frame, side .. 'LEFT')
			tex:SetPoint(side .. 'RIGHT', frame, side .. 'RIGHT')
			tex:SetHeight(px)
		else
			tex:SetPoint('TOP' .. side, frame, 'TOP' .. side)
			tex:SetPoint('BOTTOM' .. side, frame, 'BOTTOM' .. side)
			tex:SetWidth(px)
		end
	end
end

---@param lines Texture[]
---@param color table
function T.ColorBorder(lines, color)
	for _, tex in ipairs(lines) do
		tex:SetVertexColor(color[1], color[2], color[3], color[4] or 1)
	end
end

---A horizontal hairline under (or over) a region.
---@param parent Frame
---@param color? table
---@param layer? string
---@return Texture
function T.Rule(parent, color, layer)
	local tex = parent:CreateTexture(nil, layer or 'BORDER')
	tex:SetTexture(WHITE)
	color = color or T.color.line
	tex:SetVertexColor(color[1], color[2], color[3], color[4] or 1)
	tex:SetHeight(T.Pixel(parent))
	return tex
end

---@param parent Frame
---@param size? number
---@param color? table
---@param kind? string 'words' (default) or 'figures'
---@param layer? string
---@return FontString
function T.Text(parent, size, color, kind, layer)
	local fs = parent:CreateFontString(nil, layer or 'OVERLAY')
	T.SetFont(fs, size or T.size.body, kind)
	fs:SetShadowColor(0, 0, 0, 0.8)
	fs:SetShadowOffset(1, -1)
	color = color or T.color.text
	fs:SetTextColor(color[1], color[2], color[3], color[4] or 1)
	fs:SetWordWrap(false)
	fs:SetJustifyH('LEFT')
	return fs
end

---@param fs FontString|EditBox
---@param size number
---@param kind? string
function T.SetFont(fs, size, kind)
	local face = kind == 'figures' and T.FONT_FIGURES or T.FONT_WORDS
	-- Arial Narrow reads a size smaller than Friz; nudge it so columns line up optically.
	fs:SetFont(face, kind == 'figures' and size + 1 or size, '')
end

---@param fs FontString
---@param color table
function T.Color(fs, color)
	fs:SetTextColor(color[1], color[2], color[3], color[4] or 1)
end

---Square item icon with the inner bevel trimmed away.
---@param parent Frame
---@param size number
---@return Texture
function T.Icon(parent, size)
	local tex = parent:CreateTexture(nil, 'ARTWORK')
	tex:SetSize(size, size)
	tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	-- A dark 1px edge keeps icons from floating on the pane.
	local edge = parent:CreateTexture(nil, 'BORDER')
	edge:SetTexture(WHITE)
	edge:SetVertexColor(0, 0, 0, 0.8)
	edge:SetPoint('TOPLEFT', tex, 'TOPLEFT', -1, 1)
	edge:SetPoint('BOTTOMRIGHT', tex, 'BOTTOMRIGHT', 1, -1)
	tex.edge = edge
	return tex
end

---@param name string
---@return boolean
function T.HasAtlas(name)
	return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) ~= nil or false
end

---A small chevron from two hairlines, pointing UP, DOWN, LEFT or RIGHT.
---@param parent Frame
---@param color table
---@return table chevron
function T.Chevron(parent, color)
	local chevron = {}
	for _, key in ipairs({ 'a', 'b' }) do
		local tex = parent:CreateTexture(nil, 'OVERLAY', nil, 6)
		tex:SetTexture(WHITE)
		tex:SetVertexColor(color[1], color[2], color[3], color[4] or 1)
		tex:SetSize(5, 1.5)
		chevron[key] = tex
	end

	local ROTATION = { UP = 0, RIGHT = -math.pi / 2, DOWN = math.pi, LEFT = math.pi / 2 }

	function chevron:SetDirection(direction, anchor, x, y)
		local turn = ROTATION[direction] or 0
		local dx, dy = 1.6 * math.cos(turn), 1.6 * math.sin(turn)
		self.a:ClearAllPoints()
		self.b:ClearAllPoints()
		self.a:SetPoint('CENTER', anchor or parent, 'CENTER', (x or 0) - dx, (y or 0) - dy)
		self.b:SetPoint('CENTER', anchor or parent, 'CENTER', (x or 0) + dx, (y or 0) + dy)
		if self.a.SetRotation then
			self.a:SetRotation(turn + math.pi / 4)
			self.b:SetRotation(turn - math.pi / 4)
		end
	end
	function chevron:SetShown(shown)
		self.a:SetShown(shown)
		self.b:SetShown(shown)
	end
	function chevron:SetColor(c)
		self.a:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
		self.b:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
	end
	chevron:SetDirection('UP')
	return chevron
end
