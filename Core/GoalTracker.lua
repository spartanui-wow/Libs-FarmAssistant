---@class LibsFarmAssistant
local LibsFarmAssistant = LibStub('AceAddon-3.0'):GetAddon('Libs-FarmAssistant')

-- Runtime tracking of which goals completed this session (not saved)
local completedGoals = {}

function LibsFarmAssistant:InitializeGoalTracker()
	-- Ensure goals table exists (backward compat)
	if not self.db.goals then
		self.db.goals = {}
	end
	if self.db.goalSound == nil then
		self.db.goalSound = true
	end

	-- Pre-check which goals are already completed (handles /rl)
	for i, goal in ipairs(self.db.goals) do
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
function LibsFarmAssistant:GetGoalProgress(goal)
	local current = 0
	local target = goal.targetValue or 0

	if goal.type == 'item' then
		local key = tostring(goal.targetItemID)
		local item = self.session.items[key]
		current = item and item.count or 0
	elseif goal.type == 'money' then
		current = self.session.money
	elseif goal.type == 'honor' then
		current = self.session.honor or 0
	elseif goal.type == 'currency' then
		local data = self.session.currencies[goal.targetName or '']
		current = data and data.count or 0
	elseif goal.type == 'reputation' then
		current = self.session.reputation[goal.targetName or ''] or 0
	end

	local progress = target > 0 and math.min(current / target, 1) or 0
	return current, target, progress
end

---Calculate estimated time remaining for a goal
---@param goal table
---@return string|nil eta Formatted time string or nil
function LibsFarmAssistant:GetGoalETA(goal)
	local current, target, progress = self:GetGoalProgress(goal)
	if progress >= 1 then
		return nil
	end

	local hours = self:GetSessionHours()
	if hours <= 0 or current <= 0 then
		return nil
	end

	local rate = current / hours
	local remaining = target - current
	local remainingHours = remaining / rate
	local remainingSeconds = remainingHours * 3600

	return self:FormatDuration(remainingSeconds)
end

---Build a text progress bar
---@param progress number 0-1
---@param width number Number of bar characters
---@return string
function LibsFarmAssistant:BuildProgressBar(progress, width)
	local filled = math.floor(progress * width + 0.5)
	local empty = width - filled
	-- Use || for literal pipe in WoW escape sequences
	return '|cff00ff00' .. string.rep('||', filled) .. '|r|cff404040' .. string.rep('||', empty) .. '|r'
end

---Check all active goals for completion
---Called from UpdateDisplay()
function LibsFarmAssistant:CheckGoalCompletion()
	if not self.db.goals then
		return
	end

	for i, goal in ipairs(self.db.goals) do
		if goal.active and not completedGoals[i] then
			local current, target = self:GetGoalProgress(goal)
			if target > 0 and current >= target then
				completedGoals[i] = true

				-- Notification
				local goalName = goal.targetName or goal.type
				if goal.type == 'item' then
					local item = self.session.items[tostring(goal.targetItemID)]
					goalName = (item and item.link) or (item and item.name) or goalName
				elseif goal.type == 'money' then
					goalName = self:FormatMoney(goal.targetValue)
				end

				self:Print(string.format('|cff00ff00Goal Complete!|r %s reached %s', goalName, self:FormatNumber(target)))

				-- Play sound
				if self.db.goalSound then
					PlaySound(888) -- SOUNDKIT.READY_CHECK
				end
			end
		end
	end
end

---Reset goal completion tracking for a new session
function LibsFarmAssistant:ResetGoalCompletion()
	wipe(completedGoals)
end

---Format a goal's current value for display
---@param goal table
---@param current number
---@return string
function LibsFarmAssistant:FormatGoalValue(goal, current)
	if goal.type == 'money' then
		return self:FormatMoney(current)
	end
	return self:FormatNumber(current)
end

---Format a goal's target value for display
---@param goal table
---@return string
function LibsFarmAssistant:FormatGoalTarget(goal)
	if goal.type == 'money' then
		return self:FormatMoney(goal.targetValue)
	end
	return self:FormatNumber(goal.targetValue)
end
