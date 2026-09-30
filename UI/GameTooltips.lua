---@class LibsFarmAssistant
local LibsFarmAssistant = LibStub('AceAddon-3.0'):GetAddon('Libs-FarmAssistant')

-- Optional lines on the game's own tooltips. Items: how many were farmed and where they drop
-- best. Creatures: how many were killed and what they drop. Nothing is added when there is no
-- data, so tooltips stay clean for things the player never farmed.

---@class LibsFarmAssistant.GameTooltips : AceModule, AceEvent-3.0
local GameTooltips = LibsFarmAssistant:NewModule('GameTooltips')
LibsFarmAssistant.GameTooltips = GameTooltips

local T = LibsFarmAssistant.Theme
local C = T.color
local Ledger = LibsFarmAssistant.Ledger
local Format = LibsFarmAssistant.Format
local Compat = LibsFarmAssistant.Compat

local MIN_TRIES = 3
local handled = setmetatable({}, { __mode = 'k' }) -- tooltip -> true once our lines are in

local LABEL = { 0.55, 0.78, 1 }

local function Line(tooltip, left, right, rightColor)
	rightColor = rightColor or C.text
	tooltip:AddDoubleLine(left, right, LABEL[1], LABEL[2], LABEL[3], rightColor[1], rightColor[2], rightColor[3])
end

---@param tooltip GameTooltip
---@param itemID number
function GameTooltips:AddItemLines(tooltip, itemID)
	if not LibsFarmAssistant.db.tooltips.items or not itemID then
		return
	end
	local lifetime = Ledger:Lifetime()
	local total = lifetime.items[itemID]
	local hunt = LibsFarmAssistant.Hunts:Get(itemID)
	if not total and not hunt then
		return
	end

	if total then
		local session = Ledger:Session().items[itemID] or 0
		local today = Ledger:Day().items[itemID] or 0
		local parts = {}
		if session > 0 then
			parts[#parts + 1] = Format.Number(session) .. ' this session'
		elseif today > 0 then
			parts[#parts + 1] = Format.Number(today) .. ' today'
		end
		parts[#parts + 1] = Format.Number(total) .. ' all time'
		Line(tooltip, 'Farmed', table.concat(parts, ', '))

		for _, src in ipairs(Ledger.ItemSources(lifetime, itemID)) do
			if src.kills >= MIN_TRIES and src.rate then
				Line(tooltip, 'Best source', Ledger.SourceName(src.key) .. '  ' .. Format.Odds(src.rate))
				break
			end
		end
	end

	if hunt then
		local text = Format.Number(hunt.attempts or 0) .. ' attempts'
		if hunt.chance then
			text = text .. ', ' .. Format.Percent(LibsFarmAssistant.Hunts.ChanceByNow(hunt.chance, hunt.attempts or 0)) .. ' of players have it by now'
		end
		Line(tooltip, 'Hunting', text)
		local Lockouts = LibsFarmAssistant.Lockouts
		if Lockouts:HasBosses(hunt) then
			local summary = Lockouts:Summary(hunt)
			if summary.characters > 1 then
				Line(tooltip, 'This week', string.format('%d of %d characters can still try', summary.open, summary.characters))
			else
				local status, reset = Lockouts:MyStatus(hunt)
				Line(tooltip, 'This week', status == 'done' and ('done, resets in ' .. Format.Duration((reset or time()) - time())) or 'you can still try')
			end
		end
	end
	tooltip:Show()
end

---@param tooltip GameTooltip
---@param guid string
function GameTooltips:AddUnitLines(tooltip, guid)
	if not LibsFarmAssistant.db.tooltips.units then
		return
	end
	local key = LibsFarmAssistant.Sources:KeyForGUID(guid)
	if not key or key:sub(1, 2) ~= 'c:' then
		return
	end
	local stats = Ledger:Lifetime().sources[key]
	if not stats then
		return
	end
	local tries = Ledger.Attempts(key, stats)
	if tries == 0 then
		return
	end

	local killed = Format.Number(stats.kills) .. ' killed'
	if stats.loots > 0 and stats.loots ~= stats.kills then
		killed = killed .. ', ' .. Format.Number(stats.loots) .. ' looted'
	end
	Line(tooltip, 'Farmed', killed)
	local xpEach = LibsFarmAssistant.ExperienceTracker:SourcePerKill(key)
	if xpEach and LibsFarmAssistant.Compat.CanGainXP() then
		Line(tooltip, 'Experience', Format.Number(math.floor(xpEach + 0.5)) .. ' per kill')
	end

	local drops = {}
	for itemID, count in pairs(stats.drops) do
		drops[#drops + 1] = { id = itemID, rate = count / tries }
	end
	table.sort(drops, function(a, b)
		local qa = LibsFarmAssistant.Pricing:Meta(a.id).q or 1
		local qb = LibsFarmAssistant.Pricing:Meta(b.id).q or 1
		if qa ~= qb then
			return qa > qb
		end
		return a.rate > b.rate
	end)
	for i = 1, math.min(3, #drops) do
		local meta = LibsFarmAssistant.Pricing:Meta(drops[i].id)
		local r, g, b = T.QualityRGB(meta.q)
		tooltip:AddDoubleLine('  ' .. (meta.n or ('Item ' .. drops[i].id)), Format.Odds(drops[i].rate), r, g, b, C.text[1], C.text[2], C.text[3])
	end

	for _, hunt in ipairs(LibsFarmAssistant.Hunts:List()) do
		if hunt.sources[key] and not hunt.paused then
			Line(tooltip, 'Counts for', LibsFarmAssistant.Pricing:Meta(hunt.id).n or ('Item ' .. hunt.id))
		end
	end
	tooltip:Show()
end

---@param tooltip GameTooltip
local function Clear(tooltip)
	handled[tooltip] = nil
end

---@param tooltip GameTooltip
---@param itemID number|nil
local function OnItem(tooltip, itemID)
	if handled[tooltip] or not itemID then
		return
	end
	handled[tooltip] = true
	GameTooltips:AddItemLines(tooltip, itemID)
end

---@param tooltip GameTooltip
---@param guid string|nil
local function OnUnit(tooltip, guid)
	if handled[tooltip] or not guid or not Compat.CanAccess(guid) then
		return
	end
	handled[tooltip] = true
	GameTooltips:AddUnitLines(tooltip, guid)
end

local function Wanted(tooltip)
	return tooltip == GameTooltip or tooltip == ItemRefTooltip
end

function GameTooltips:OnEnable()
	-- Modern clients describe tooltips with data; the Classic tooltip scripts still fire on some
	-- flavors (Mists) that have the data processor, so both paths are wired and deduplicated.
	if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
			if Wanted(tooltip) and data then
				OnItem(tooltip, Compat.Readable(data.id))
			end
		end)
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip, data)
			if Wanted(tooltip) and data then
				OnUnit(tooltip, Compat.Readable(data.guid))
			end
		end)
	end

	for _, tooltip in ipairs({ GameTooltip, ItemRefTooltip }) do
		if tooltip and tooltip.HookScript then
			if tooltip:HasScript('OnTooltipSetItem') then
				tooltip:HookScript('OnTooltipSetItem', function(tt)
					local _, link = tt:GetItem()
					OnItem(tt, Compat.ItemIDFromLink(link))
				end)
			end
			if tooltip:HasScript('OnTooltipSetUnit') then
				tooltip:HookScript('OnTooltipSetUnit', function(tt)
					local ok, _, unit = pcall(tt.GetUnit, tt)
					if ok and unit then
						OnUnit(tt, Compat.UnitGUID(unit))
					end
				end)
			end
			if tooltip:HasScript('OnTooltipCleared') then
				tooltip:HookScript('OnTooltipCleared', Clear)
			end
			tooltip:HookScript('OnHide', Clear)
		end
	end
end
