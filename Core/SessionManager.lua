---@class LibsFarmAssistant
local LibsFarmAssistant = LibStub('AceAddon-3.0'):GetAddon('Libs-FarmAssistant')

-- Local state for pause tracking
local pauseStartTime = 0

function LibsFarmAssistant:InitializeSession()
	local session = self.session

	-- If no start time, this is a fresh session
	if session.startTime == 0 then
		session.startTime = GetTime()
		session.active = true
		session.pausedDuration = 0
	end
end

---Get active session duration in seconds (excluding paused time)
---@return number seconds
function LibsFarmAssistant:GetSessionDuration()
	local session = self.session
	if session.startTime == 0 then
		return 0
	end

	local elapsed = GetTime() - session.startTime - session.pausedDuration

	-- If currently paused, subtract time since pause
	if not session.active and pauseStartTime > 0 then
		elapsed = elapsed - (GetTime() - pauseStartTime)
	end

	return math.max(0, elapsed)
end

---Get session duration in hours (for rate calculations)
---@return number hours
function LibsFarmAssistant:GetSessionHours()
	local seconds = self:GetSessionDuration()
	return seconds / 3600
end

---Check if session is actively tracking
---@return boolean
function LibsFarmAssistant:IsSessionActive()
	return self.session.active
end

---Toggle session active/paused
function LibsFarmAssistant:ToggleSession()
	local session = self.session

	if session.active then
		-- Pause
		session.active = false
		pauseStartTime = GetTime()
		self:Print('Session paused')
	else
		-- Resume
		if pauseStartTime > 0 then
			session.pausedDuration = session.pausedDuration + (GetTime() - pauseStartTime)
			pauseStartTime = 0
		end
		session.active = true
		self:Print('Session resumed')
	end

	self:UpdateDisplay()
end

---Reset session to fresh state
function LibsFarmAssistant:ResetSession()
	local session = self.session

	session.active = true
	session.startTime = GetTime()
	session.pausedDuration = 0
	wipe(session.items)
	session.money = 0
	wipe(session.currencies)
	wipe(session.reputation)
	pauseStartTime = 0

	-- Re-snapshot money for delta tracking
	self:SnapshotMoney()

	self:UpdateDisplay()
	self:Log('Session reset', 'info')
end

---Get total unique item count in session
---@return number itemCount
---@return number totalItems
function LibsFarmAssistant:GetItemCounts()
	local unique = 0
	local total = 0
	for _, item in pairs(self.session.items) do
		unique = unique + 1
		total = total + (item.count or 0)
	end
	return unique, total
end

---Print session summary to chat
function LibsFarmAssistant:PrintSummary()
	local duration = self:GetSessionDuration()
	local hours = self:GetSessionHours()

	self:Print('--- Farm Session Summary ---')
	self:Print('Duration: ' .. self:FormatDuration(duration))

	-- Items
	local _, totalItems = self:GetItemCounts()
	if totalItems > 0 then
		self:Print(string.format('Items: %d looted', totalItems))
		for _, item in pairs(self.session.items) do
			local rate = hours > 0 and string.format(' (%.0f/hr)', item.count / hours) or ''
			self:Print(string.format('  %s x%d%s', item.link or item.name, item.count, rate))
		end
	end

	-- Money
	if self.session.money > 0 then
		self:Print('Money: ' .. self:FormatMoney(self.session.money))
	end

	-- Currency
	for name, data in pairs(self.session.currencies) do
		self:Print(string.format('Currency: %s x%d', name, data.count))
	end

	-- Reputation
	for faction, gained in pairs(self.session.reputation) do
		self:Print(string.format('Rep: %s +%d', faction, gained))
	end
end

---Format seconds into readable duration
---@param seconds number
---@return string
function LibsFarmAssistant:FormatDuration(seconds)
	seconds = math.floor(seconds)
	local hours = math.floor(seconds / 3600)
	local minutes = math.floor((seconds % 3600) / 60)

	if hours > 0 then
		return string.format('%dh %dm', hours, minutes)
	else
		return string.format('%dm', minutes)
	end
end

---Format copper into gold/silver/copper string
---@param copper number Amount in copper
---@return string
function LibsFarmAssistant:FormatMoney(copper)
	copper = math.floor(copper)
	local gold = math.floor(copper / 10000)
	local silver = math.floor((copper % 10000) / 100)
	local rem = copper % 100

	if gold > 0 then
		return string.format('%dg %ds %dc', gold, silver, rem)
	elseif silver > 0 then
		return string.format('%ds %dc', silver, rem)
	else
		return string.format('%dc', rem)
	end
end
