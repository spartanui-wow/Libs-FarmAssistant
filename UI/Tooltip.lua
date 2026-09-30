---@class LibsFarmAssistant
local LibsFarmAssistant = LibStub('AceAddon-3.0'):GetAddon('Libs-FarmAssistant')

-- The broker and minimap tooltip: this session in the same order as the Overview page.

local T = LibsFarmAssistant.Theme
local C = T.color
local Ledger = LibsFarmAssistant.Ledger
local Format = LibsFarmAssistant.Format

local TOP_ITEMS = 6

local function Line(tooltip, left, right, color, rightColor)
	color = color or C.muted
	rightColor = rightColor or C.text
	tooltip:AddDoubleLine(left, right, color[1], color[2], color[3], rightColor[1], rightColor[2], rightColor[3])
end

local function Heading(tooltip, text)
	tooltip:AddLine(' ')
	tooltip:AddLine(text, C.gold[1], C.gold[2], C.gold[3])
end

---@param tooltip GameTooltip
function LibsFarmAssistant:BuildTooltip(tooltip)
	local bucket = Ledger:Session()
	local active = self:IsSessionActive()

	tooltip:AddDoubleLine(
		'Farm Assistant',
		(active and '' or 'Paused  ') .. Format.Clock(self:GetSessionDuration()),
		1,
		1,
		1,
		active and C.text[1] or C.warn[1],
		active and C.text[2] or C.warn[2],
		active and C.text[3] or C.warn[3]
	)

	local value = Ledger.TotalValue(bucket)
	local rate = Ledger.PerHour(value, bucket)
	Line(tooltip, 'Value', Format.Money(value) .. (rate and ('   ' .. Format.Money(rate) .. ' /hr') or ''), C.muted, C.gold)
	local gold = Ledger.Money(bucket, 'loot')
	if gold > 0 then
		Line(tooltip, 'Gold looted', Format.Money(gold))
	end
	if bucket.kills > 0 then
		local killRate = Ledger.PerHour(bucket.kills, bucket)
		Line(tooltip, 'Kills', Format.Number(bucket.kills) .. (killRate and ('   ' .. Format.Rate(killRate) .. ' /hr') or ''))
	end
	if bucket.xp > 0 then
		local seconds, kills = self.ExperienceTracker:TimeToLevel(bucket)
		Line(tooltip, 'Experience', Format.Short(bucket.xp) .. (seconds and ('   level in ' .. Format.Duration(seconds)) or ''))
		local perKill = self.ExperienceTracker:PerKill()
		if perKill then
			Line(tooltip, 'Per kill', Format.Number(math.floor(perKill + 0.5)) .. (kills and ('   ' .. Format.Number(kills) .. ' kills to level') or ''))
		end
	end
	if bucket.honor > 0 then
		Line(tooltip, 'Honor', Format.Number(bucket.honor))
	end

	local items = LibsFarmAssistant.Widgets.ItemRows(bucket)
	if #items > 0 then
		table.sort(items, function(a, b)
			if a.value ~= b.value then
				return a.value > b.value
			end
			return a.count > b.count
		end)
		Heading(tooltip, 'Top loot')
		for i = 1, math.min(TOP_ITEMS, #items) do
			local row = items[i]
			Line(tooltip, row.name, Format.Number(row.count), T.quality[row.quality or 1])
		end
		if #items > TOP_ITEMS then
			tooltip:AddLine(string.format('and %d more', #items - TOP_ITEMS), C.faint[1], C.faint[2], C.faint[3])
		end
	end

	local hunts = {}
	for _, hunt in ipairs(self.Hunts:List()) do
		if not hunt.paused and not self.Hunts:IsCollected(hunt) then
			hunts[#hunts + 1] = hunt
		end
	end
	if #hunts > 0 then
		Heading(tooltip, 'Hunts')
		for _, hunt in ipairs(hunts) do
			local meta = self.Pricing:Meta(hunt.id)
			local right = Format.Number(hunt.attempts or 0) .. ' attempts'
			if hunt.chance then
				right = right .. '   ' .. Format.Percent(self.Hunts.ChanceByNow(hunt.chance, hunt.attempts or 0)) .. ' of players have it by now'
			end
			if self.Lockouts:MyStatus(hunt) == 'done' then
				right = right .. '   saved'
			end
			Line(tooltip, meta.n or ('Item ' .. hunt.id), right, T.quality[meta.q or 1])
		end
	end

	local gains = self.ReputationTracker:Gains(bucket)
	if #gains > 0 then
		Heading(tooltip, 'Standing')
		for i = 1, math.min(3, #gains) do
			local gain = gains[i]
			Line(tooltip, gain.progress.name .. '  +' .. Format.Number(gain.gained), LibsFarmAssistant.Widgets.RepPace(gain), C.text, LibsFarmAssistant.Widgets.StandingColor(gain.progress))
		end
	end

	local goals = {}
	for _, goal in ipairs(self.db.goals) do
		if goal.active then
			goals[#goals + 1] = goal
		end
	end
	if #goals > 0 then
		Heading(tooltip, 'Goals')
		for _, goal in ipairs(goals) do
			local current, target, progress = self.GoalTracker:Progress(goal)
			local eta = self.GoalTracker:ETA(goal)
			local right = self.GoalTracker:FormatValue(goal, current) .. ' / ' .. self.GoalTracker:FormatValue(goal, target)
			if progress >= 1 then
				right = right .. '   done'
			elseif eta then
				right = right .. '   ' .. Format.Duration(eta)
			end
			Line(tooltip, self.GoalTracker:Name(goal), right, C.text, progress >= 1 and C.good or C.text)
		end
	end

	tooltip:AddLine(' ')
	tooltip:AddLine('Click: window   Right-click: pause   Middle-click: tracker', C.faint[1], C.faint[2], C.faint[3])
	tooltip:AddLine('Shift-click: new session   Scroll: change the text shown', C.faint[1], C.faint[2], C.faint[3])
	tooltip:Show()
end
