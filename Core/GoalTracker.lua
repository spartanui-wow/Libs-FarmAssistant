---@class LibsFarmAssistant
local LibsFarmAssistant = LibStub('AceAddon-3.0'):GetAddon('Libs-FarmAssistant')

---@class LibsFarmAssistant.GoalTracker : AceModule, AceEvent-3.0, AceTimer-3.0
local GoalTracker = LibsFarmAssistant:NewModule('GoalTracker')
LibsFarmAssistant.GoalTracker = GoalTracker

-- Runtime tracking of which goals completed this session (not saved)
local completedGoals = {}

function GoalTracker:OnEnable()
	-- Ensure goals table exists (backward compat)
	if not LibsFarmAssistant.db.goals then
		LibsFarmAssistant.db.goals = {}
	end
	if LibsFarmAssistant.db.goalSound == nil then
		LibsFarmAssistant.db.goalSound = true
	end

	-- Pre-check which goals are already completed (handles /rl)
	for i, goal in ipairs(LibsFarmAssistant.db.goals) do
		if goal.active then
			local current, target = self:GetGoalProgress(goal)
			if target > 0 and current >= target then
				completedGoals[i] = true
			end
		end
	end
end

---Get current progress for a goal
---@param goal table
---@return number current
---@return number target
---@return number progress 0-1
function GoalTracker:GetGoalProgress(goal)
	local current = 0
	local target = goal.targetValue or 0

	if goal.type == 'item' then
		local key = tostring(goal.targetItemID)
		local item = LibsFarmAssistant.session.items[key]
		current = item and item.count or 0
	elseif goal.type == 'money' then
		current = LibsFarmAssistant.session.money
	elseif goal.type == 'honor' then
		current = LibsFarmAssistant.session.honor or 0
	elseif goal.type == 'currency' then
		local data = LibsFarmAssistant.session.currencies[goal.targetName or '']
		current = data and data.count or 0
	elseif goal.type == 'reputation' then
		current = LibsFarmAssistant.session.reputation[goal.targetName or ''] or 0
	end

	local progress = target > 0 and math.min(current / target, 1) or 0
	return current, target, progress
end

---Calculate estimated time remaining for a goal
---@param goal table
---@return string|nil eta Formatted time string or nil
function GoalTracker:GetGoalETA(goal)
	local current, target, progress = self:GetGoalProgress(goal)
	if progress >= 1 then
		return nil
	end

	local hours = LibsFarmAssistant:GetSessionHours()
	if hours <= 0 or current <= 0 then
		return nil
	end

	local rate = current / hours
	local remaining = target - current
	local remainingHours = remaining / rate
	local remainingSeconds = remainingHours * 3600

	return LibsFarmAssistant:FormatDuration(remainingSeconds)
end

---Build a text progress bar
---@param progress number 0-1
---@param width number Number of bar characters
---@return string
function GoalTracker:BuildProgressBar(progress, width)
	local filled = math.floor(progress * width + 0.5)
	local empty = width - filled
	-- Use || for literal pipe in WoW escape sequences
	return '|cff00ff00' .. string.rep('||', filled) .. '|r|cff404040' .. string.rep('||', empty) .. '|r'
end

---Check all active goals for completion
---Called from UpdateDisplay()
function GoalTracker:CheckGoalCompletion()
	if not LibsFarmAssistant.db.goals then
		return
	end

	for i, goal in ipairs(LibsFarmAssistant.db.goals) do
		if goal.active and not completedGoals[i] then
			local current, target = self:GetGoalProgress(goal)
			if target > 0 and current >= target then
				completedGoals[i] = true

				-- Notification
				local goalName = goal.targetName or goal.type
				if goal.type == 'item' then
					local item = LibsFarmAssistant.session.items[tostring(goal.targetItemID)]
					goalName = (item and item.link) or (item and item.name) or goalName
				elseif goal.type == 'money' then
					goalName = LibsFarmAssistant:FormatMoney(goal.targetValue)
				end

				LibsFarmAssistant:Print(string.format('|cff00ff00Goal Complete!|r %s reached %s', goalName, LibsFarmAssistant:FormatNumber(target)))

				-- Play sound
				if LibsFarmAssistant.db.goalSound then
					PlaySound(888) -- SOUNDKIT.READY_CHECK
				end
			end
		end
	end
end

---Reset goal completion tracking for a new session
function GoalTracker:ResetGoalCompletion()
	wipe(completedGoals)
end

---Format a goal's current value for display
---@param goal table
---@param current number
---@return string
function GoalTracker:FormatGoalValue(goal, current)
	if goal.type == 'money' then
		return LibsFarmAssistant:FormatMoney(current)
	end
	return LibsFarmAssistant:FormatNumber(current)
end

---Format a goal's target value for display
---@param goal table
---@return string
function GoalTracker:FormatGoalTarget(goal)
	if goal.type == 'money' then
		return LibsFarmAssistant:FormatMoney(goal.targetValue)
	end
	return LibsFarmAssistant:FormatNumber(goal.targetValue)
end

-- Bridge methods
function LibsFarmAssistant:GetGoalProgress(goal)
	if self.GoalTracker then
		return self.GoalTracker:GetGoalProgress(goal)
	end
	return 0, 0, 0
end

function LibsFarmAssistant:GetGoalETA(goal)
	if self.GoalTracker then
		return self.GoalTracker:GetGoalETA(goal)
	end
	return nil
end

function LibsFarmAssistant:BuildProgressBar(progress, width)
	if self.GoalTracker then
		return self.GoalTracker:BuildProgressBar(progress, width)
	end
	return ''
end

function LibsFarmAssistant:CheckGoalCompletion()
	if self.GoalTracker then
		self.GoalTracker:CheckGoalCompletion()
	end
end

function LibsFarmAssistant:ResetGoalCompletion()
	if self.GoalTracker then
		self.GoalTracker:ResetGoalCompletion()
	end
end

function LibsFarmAssistant:FormatGoalValue(goal, current)
	if self.GoalTracker then
		return self.GoalTracker:FormatGoalValue(goal, current)
	end
	return '0'
end

function LibsFarmAssistant:FormatGoalTarget(goal)
	if self.GoalTracker then
		return self.GoalTracker:FormatGoalTarget(goal)
	end
	return '0'
end
