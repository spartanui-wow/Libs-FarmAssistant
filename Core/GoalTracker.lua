---@class LibsFarmAssistant
local LibsFarmAssistant = LibStub('AceAddon-3.0'):GetAddon('Libs-FarmAssistant')

-- Session goals: "200 Runecloth", "500 gold", "3,000 honor". Progress is read from the current
-- session, with an estimate of the time left at the current pace.

---@class LibsFarmAssistant.GoalTracker : AceModule, AceEvent-3.0, AceTimer-3.0
local GoalTracker = LibsFarmAssistant:NewModule('GoalTracker')
LibsFarmAssistant.GoalTracker = GoalTracker

local Compat = LibsFarmAssistant.Compat
local Ledger = LibsFarmAssistant.Ledger
local Format = LibsFarmAssistant.Format

local completed = setmetatable({}, { __mode = 'k' }) -- goal -> true once announced this session

function GoalTracker:OnEnable()
	for _, goal in ipairs(LibsFarmAssistant.db.goals) do
		if goal.active then
			local current, target = self:Progress(goal)
			if target > 0 and current >= target then
				completed[goal] = true
			end
		end
	end
end

---@param goal table
---@return number|nil
local function CurrencyID(goal)
	if goal.currencyID then
		return goal.currencyID
	end
	if goal.targetName then
		for currencyID in pairs(Ledger:Session().currencies) do
			if Compat.CurrencyInfo(currencyID) == goal.targetName then
				goal.currencyID = currencyID
				return currencyID
			end
		end
	end
	return nil
end

---@param goal table
---@return number|nil
local function FactionID(goal)
	if goal.factionID then
		return goal.factionID
	end
	local tracker = LibsFarmAssistant.ReputationTracker
	if goal.targetName and tracker then
		goal.factionID = tracker:IDForName(goal.targetName)
	end
	return goal.factionID
end

---@param goal table
---@return number current, number target, number progress 0-1
function GoalTracker:Progress(goal)
	local session = Ledger:Session()
	local current = 0
	if goal.type == 'item' then
		current = session.items[goal.targetItemID] or 0
	elseif goal.type == 'money' then
		current = Ledger.Money(session)
	elseif goal.type == 'value' then
		current = Ledger.TotalValue(session)
	elseif goal.type == 'honor' then
		current = session.honor or 0
	elseif goal.type == 'kills' then
		current = session.kills or 0
	elseif goal.type == 'xp' then
		current = session.xp or 0
	elseif goal.type == 'currency' then
		local id = CurrencyID(goal)
		current = id and session.currencies[id] or 0
	elseif goal.type == 'reputation' then
		local id = FactionID(goal)
		current = id and session.rep[id] or 0
	end
	local target = goal.targetValue or 0
	return current, target, target > 0 and math.min(current / target, 1) or 0
end

---@param goal table
---@return number|nil seconds left at the session's pace
function GoalTracker:ETA(goal)
	local current, target, progress = self:Progress(goal)
	if progress >= 1 or current <= 0 then
		return nil
	end
	local perHour = Ledger.PerHour(current, Ledger:Session())
	if not perHour or perHour <= 0 then
		return nil
	end
	return (target - current) / perHour * 3600
end

---@param goal table
---@return string
function GoalTracker:Name(goal)
	if goal.type == 'item' then
		local meta = LibsFarmAssistant.Pricing:Meta(goal.targetItemID)
		return meta.n or goal.targetName or ('Item ' .. tostring(goal.targetItemID))
	elseif goal.type == 'money' then
		return 'Gold'
	elseif goal.type == 'value' then
		return 'Total value'
	elseif goal.type == 'honor' then
		return 'Honor'
	elseif goal.type == 'kills' then
		return 'Kills'
	elseif goal.type == 'xp' then
		return 'Experience'
	elseif goal.type == 'currency' then
		local id = CurrencyID(goal)
		return (id and Compat.CurrencyInfo(id)) or goal.targetName or 'Currency'
	elseif goal.type == 'reputation' then
		local id = FactionID(goal)
		return (id and Compat.FactionName(id)) or goal.targetName or 'Reputation'
	end
	return goal.targetName or goal.type
end

---@param goal table
---@param value number
---@return string
function GoalTracker:FormatValue(goal, value)
	if goal.type == 'money' or goal.type == 'value' then
		return Format.Money(value)
	end
	return Format.Number(value)
end

function GoalTracker:CheckCompletion()
	for _, goal in ipairs(LibsFarmAssistant.db.goals) do
		if goal.active and not completed[goal] then
			local current, target = self:Progress(goal)
			if target > 0 and current >= target then
				completed[goal] = true
				LibsFarmAssistant:Print(string.format('Goal reached: %s %s.', self:FormatValue(goal, target), self:Name(goal)))
				if LibsFarmAssistant.db.goalSound then
					PlaySound(SOUNDKIT and SOUNDKIT.READY_CHECK or 8960)
				end
			end
		end
	end
end

function GoalTracker:ResetCompletion()
	wipe(completed)
end

-- Bridges
function LibsFarmAssistant:CheckGoalCompletion()
	self.GoalTracker:CheckCompletion()
end

function LibsFarmAssistant:ResetGoalCompletion()
	self.GoalTracker:ResetCompletion()
end
