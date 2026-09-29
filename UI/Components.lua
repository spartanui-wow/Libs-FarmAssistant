---@class LibsFarmAssistant
local LibsFarmAssistant = LibStub('AceAddon-3.0'):GetAddon('Libs-FarmAssistant')

-- Rows that more than one page shows: a standing with its bar, and a hunt with its count.

local T = LibsFarmAssistant.Theme
local W = LibsFarmAssistant.Widgets
local C = T.color
local Format = LibsFarmAssistant.Format
local Ledger = LibsFarmAssistant.Ledger

---Color for a faction's current step: the standing ladder for normal factions, the quality
---ladder for renown and friendship.
---@param p FarmFactionProgress
---@return table color
function W.StandingColor(p)
	if p.rewardPending then
		return C.claim
	end
	if p.kind == 'standard' then
		return T.standing[p.level] or T.standing[4]
	end
	return T.quality[p.quality] or T.quality[1]
end

---@param gain FarmRepGain
---@return string
function W.RepPace(gain)
	local p = gain.progress
	if p.capped then
		return 'Maxed'
	end
	if p.rewardPending then
		return 'Reward waiting'
	end
	if gain.seconds then
		return Format.Duration(gain.seconds) .. ' to ' .. gain.nextLabel
	end
	return Format.Number(gain.remaining) .. ' to ' .. gain.nextLabel
end

---A reputation row: name and gain, a bar in the standing's color, standing and pace.
---@param parent Frame
---@return Frame card with :Set(gain)
function W.RepCard(parent)
	local card = CreateFrame('Frame', nil, parent)
	card:SetHeight(44)
	card:EnableMouse(true)

	card.name = T.Text(card, 12, C.text)
	card.name:SetPoint('TOPLEFT', 0, -5)
	card.name:SetPoint('RIGHT', -70, 0)
	card.gain = T.Text(card, 12, C.good, 'figures')
	card.gain:SetPoint('TOPRIGHT', 0, -4)
	card.gain:SetJustifyH('RIGHT')

	card.bar = W.Bar(card, 5)
	card.bar:SetPoint('TOPLEFT', 0, -21)
	card.bar:SetPoint('RIGHT')

	card.standing = T.Text(card, 10, C.muted)
	card.standing:SetPoint('TOPLEFT', card.bar, 'BOTTOMLEFT', 0, -4)
	card.value = T.Text(card, 10, C.muted, 'figures')
	card.value:SetPoint('TOP', card.bar, 'BOTTOM', 0, -4)
	card.pace = T.Text(card, 10, C.muted, 'figures')
	card.pace:SetPoint('TOPRIGHT', card.bar, 'BOTTOMRIGHT', 0, -4)
	card.pace:SetJustifyH('RIGHT')
	card.perKill = T.Text(card, 10, C.faint, 'figures')
	card.perKill:SetPoint('TOPLEFT', card.standing, 'BOTTOMLEFT', 0, -3)
	card.killsLeft = T.Text(card, 10, C.faint, 'figures')
	card.killsLeft:SetPoint('TOPRIGHT', card.pace, 'BOTTOMRIGHT', 0, -3)
	card.killsLeft:SetJustifyH('RIGHT')

	---Taller rows add the per-kill line.
	---@param tall boolean
	function card:SetTall(tall)
		self.tall = tall
		self:SetHeight(tall and 58 or 44)
	end

	local rule = T.Rule(card)
	rule:SetPoint('BOTTOMLEFT')
	rule:SetPoint('BOTTOMRIGHT')

	---@param gain FarmRepGain
	function card:Set(gain)
		self.data = gain
		local p = gain.progress
		local color = W.StandingColor(p)
		self.name:SetText(p.name)
		self.gain:SetText('+' .. Format.Number(gain.gained))
		self.bar:SetValue(p.max > 0 and (p.value / p.max) or 0, color)
		self.standing:SetText(p.rewardPending and 'Reward waiting' or p.label)
		T.Color(self.standing, color)
		self.value:SetText(p.capped and '' or (Format.Number(p.value) .. ' / ' .. Format.Number(p.max)))
		self.pace:SetText(p.rewardPending and (p.kind == 'paragon' and 'Paragon' or '') or W.RepPace(gain))
		local showKills = self.tall and gain.kills ~= nil and not p.capped
		local perKill = gain.perKill
		self.perKill:SetText(showKills and perKill and (Format.Rate(perKill) .. ' per kill') or '')
		self.killsLeft:SetText(showKills and ('about ' .. Format.Number(gain.kills) .. ' kills to go') or '')
	end

	card:SetScript('OnEnter', function(self)
		local gain = self.data
		if not gain then
			return
		end
		local p = gain.progress
		GameTooltip:SetOwner(self, 'ANCHOR_RIGHT')
		GameTooltip:SetText(p.name, 1, 1, 1)
		GameTooltip:AddDoubleLine('Standing', p.label, C.muted[1], C.muted[2], C.muted[3], 1, 1, 1)
		GameTooltip:AddDoubleLine('Gained', Format.Number(gain.gained), C.muted[1], C.muted[2], C.muted[3], 1, 1, 1)
		if gain.perHour then
			GameTooltip:AddDoubleLine('Per hour', Format.Number(gain.perHour), C.muted[1], C.muted[2], C.muted[3], 1, 1, 1)
		end
		if not p.capped and gain.remaining > 0 then
			GameTooltip:AddDoubleLine('Left to ' .. gain.nextLabel, Format.Number(gain.remaining), C.muted[1], C.muted[2], C.muted[3], 1, 1, 1)
			if gain.seconds then
				GameTooltip:AddDoubleLine('At this pace', Format.Duration(gain.seconds), C.muted[1], C.muted[2], C.muted[3], 1, 1, 1)
			end
			if gain.kills then
				GameTooltip:AddDoubleLine('About', Format.Number(gain.kills) .. ' kills', C.muted[1], C.muted[2], C.muted[3], 1, 1, 1)
			end
		end
		GameTooltip:Show()
	end)
	card:SetScript('OnLeave', function()
		GameTooltip:Hide()
	end)
	return card
end

---Luck color: green while on pace, amber once most players would have it, red when very unlucky.
---@param byNow number 0-1
---@return table
function W.LuckColor(byNow)
	if byNow < 0.5 then
		return C.good
	elseif byNow < 0.85 then
		return C.warn
	end
	return C.bad
end

---A hunt row: icon, name in its quality color, attempts, and odds or time.
---@param parent Frame
---@param opts? table { onClick = fn(hunt) }
---@return Button card with :Set(hunt, selected)
function W.HuntCard(parent, opts)
	opts = opts or {}
	local card = CreateFrame('Button', nil, parent)
	card:SetHeight(46)
	card.bg = T.Fill(card, { 0, 0, 0, 0 })
	card.icon = T.Icon(card, 30)
	card.icon:SetPoint('LEFT', 4, 0)
	card.name = T.Text(card, 12, C.text)
	card.name:SetPoint('TOPLEFT', card.icon, 'TOPRIGHT', 8, -1)
	card.name:SetPoint('RIGHT', -4, 0)
	card.count = T.Text(card, 14, C.text, 'figures')
	card.count:SetPoint('TOPLEFT', card.name, 'BOTTOMLEFT', 0, -3)
	card.unit = T.Text(card, 11, C.muted)
	card.unit:SetPoint('BOTTOMLEFT', card.count, 'BOTTOMRIGHT', 4, 1)
	card.right = T.Text(card, 11, C.muted, 'figures')
	card.right:SetPoint('RIGHT', card, 'RIGHT', -4, 0)
	card.right:SetPoint('BOTTOM', card.count, 'BOTTOM', 0, 0)
	card.right:SetJustifyH('RIGHT')
	card.bar = W.Bar(card, 3)
	card.bar:SetPoint('TOPLEFT', card.count, 'BOTTOMLEFT', 0, -3)
	card.bar:SetPoint('RIGHT', -4, 0)
	local rule = T.Rule(card)
	rule:SetPoint('BOTTOMLEFT')
	rule:SetPoint('BOTTOMRIGHT')

	---@param hunt FarmHunt
	---@param selected? boolean
	function card:Set(hunt, selected)
		self.hunt = hunt
		local Hunts = LibsFarmAssistant.Hunts
		local meta = LibsFarmAssistant.Pricing:Meta(hunt.id)
		self.icon:SetTexture(LibsFarmAssistant.Compat.ItemIcon(hunt.id))
		self.name:SetText(meta.n or ('Item ' .. hunt.id))
		self.name:SetTextColor(T.QualityRGB(meta.q))
		local collected = Hunts:IsCollected(hunt)
		self:SetAlpha((collected or hunt.paused) and 0.55 or 1)

		if collected then
			local last = hunt.found[#hunt.found]
			self.count:SetText('')
			self.unit:SetText(last and ('Collected after ' .. Format.Number(last.attempts)) or 'Collected')
			self.right:SetText('')
			self.bar:Hide()
		else
			self.count:SetText(Format.Number(hunt.attempts or 0))
			local anyKill = hunt.mode == 'any' or not Hunts:HasSources(hunt)
			local word = (hunt.attempts == 1) and 'attempt' or (anyKill and 'kills' or 'attempts')
			self.unit:SetText(hunt.paused and (word .. ', paused') or word)
			if hunt.chance then
				self.right:SetText(Format.Odds(hunt.chance))
				local byNow = Hunts.ChanceByNow(hunt.chance, hunt.attempts or 0)
				self.bar:SetValue(math.max(byNow, 0.02), W.LuckColor(byNow))
				self.bar:Show()
			else
				self.right:SetText(Format.Duration(hunt.time or 0))
				self.bar:Hide()
			end
			local status, reset = LibsFarmAssistant.Lockouts:MyStatus(hunt)
			if status == 'done' and reset then
				self.right:SetText('saved ' .. Format.Duration(reset - time()))
			end
		end
		T.Tint(self.bg, selected and C.selected or (self.hover and C.hover or { 0, 0, 0, 0 }))
		self.selected = selected
	end

	card:SetScript('OnEnter', function(self)
		self.hover = true
		if self.hunt then
			self:Set(self.hunt, self.selected)
			W.ShowItemTooltip(self, self.hunt.id)
		end
	end)
	card:SetScript('OnLeave', function(self)
		self.hover = false
		if self.hunt then
			self:Set(self.hunt, self.selected)
		end
		GameTooltip:Hide()
	end)
	card:RegisterForClicks('AnyUp')
	card:SetScript('OnClick', function(self)
		if self.hunt and not W.ModifiedItemClick(self.hunt.id) and opts.onClick then
			opts.onClick(self.hunt)
		end
	end)
	return card
end

---Every item in the bucket with its count, pace and value.
---@param bucket FarmBucket
---@return table[]
function W.ItemRows(bucket)
	local Pricing = LibsFarmAssistant.Pricing
	local rows = {}
	for itemID, count in pairs(bucket.items) do
		local meta = Pricing:Meta(itemID)
		local unit = Pricing:Value(itemID) or 0
		rows[#rows + 1] = {
			id = itemID,
			name = meta.n or ('Item ' .. itemID),
			quality = meta.q,
			count = count,
			perHour = Ledger.PerHour(count, bucket),
			value = unit * count,
		}
	end
	return rows
end
