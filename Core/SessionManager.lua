---@class LibsFarmAssistant
local LibsFarmAssistant = LibStub('AceAddon-3.0'):GetAddon('Libs-FarmAssistant')

---@class LibsFarmAssistant.SessionManager : AceModule, AceEvent-3.0, AceTimer-3.0
local SessionManager = LibsFarmAssistant:NewModule('SessionManager')
LibsFarmAssistant.SessionManager = SessionManager

function SessionManager:OnEnable()
	self.pauseStartTime = 0

	local session = LibsFarmAssistant.session

	-- If no start time, this is a fresh session
	if session.startTime == 0 then
		session.startTime = GetTime()
		session.active = true
		session.pausedDuration = 0
	end
end

---Get active session duration in seconds (excluding paused time)
---@return number seconds
function SessionManager:GetSessionDuration()
	local session = LibsFarmAssistant.session
	if session.startTime == 0 then
		return 0
	end

	local elapsed = GetTime() - session.startTime - session.pausedDuration

	-- If currently paused, subtract time since pause
	if not session.active and self.pauseStartTime > 0 then
		elapsed = elapsed - (GetTime() - self.pauseStartTime)
	end

	return math.max(0, elapsed)
end

---Get session duration in hours (for rate calculations)
---@return number hours
function SessionManager:GetSessionHours()
	local seconds = self:GetSessionDuration()
	return seconds / 3600
end

---Check if session is actively tracking
---@return boolean
function SessionManager:IsSessionActive()
	return LibsFarmAssistant.session.active
end

---Toggle session active/paused
function SessionManager:ToggleSession()
	local session = LibsFarmAssistant.session

	if session.active then
		-- Pause
		session.active = false
		self.pauseStartTime = GetTime()
		LibsFarmAssistant:Print('Session paused')
	else
		-- Resume
		if self.pauseStartTime > 0 then
			session.pausedDuration = session.pausedDuration + (GetTime() - self.pauseStartTime)
			self.pauseStartTime = 0
		end
		session.active = true
		LibsFarmAssistant:Print('Session resumed')
	end

	LibsFarmAssistant:UpdateDisplay()
end

---Reset session to fresh state
function SessionManager:ResetSession()
	-- Save current session to history before clearing
	LibsFarmAssistant:SaveSessionToHistory()

	local session = LibsFarmAssistant.session

	session.active = true
	session.startTime = GetTime()
	session.pausedDuration = 0
	wipe(session.items)
	session.money = 0
	wipe(session.currencies)
	wipe(session.reputation)
	session.honor = 0
	self.pauseStartTime = 0

	-- Reset goal completion tracking
	LibsFarmAssistant:ResetGoalCompletion()

	-- Re-snapshot money for delta tracking
	LibsFarmAssistant:SnapshotMoney()

	LibsFarmAssistant:UpdateDisplay()
	LibsFarmAssistant:Log('Session reset', 'info')
end

---Get total unique item count in session
---@return number itemCount
---@return number totalItems
function SessionManager:GetItemCounts()
	local unique = 0
	local total = 0
	for _, item in pairs(LibsFarmAssistant.session.items) do
		unique = unique + 1
		total = total + (item.count or 0)
	end
	return unique, total
end

---Get total estimated vendor value of all session items (in copper)
---@return number copper
function SessionManager:GetTotalVendorValue()
	local total = 0
	for _, item in pairs(LibsFarmAssistant.session.items) do
		total = total + (item.sellPrice or 0) * (item.count or 0)
	end
	return total
end

---Print session summary to chat
function SessionManager:PrintSummary()
	local duration = self:GetSessionDuration()
	local hours = self:GetSessionHours()

	LibsFarmAssistant:Print('--- Farm Session Summary ---')
	LibsFarmAssistant:Print('Duration: ' .. LibsFarmAssistant:FormatDuration(duration))

	-- Items
	local _, totalItems = self:GetItemCounts()
	if totalItems > 0 then
		LibsFarmAssistant:Print(string.format('Items: %s looted', LibsFarmAssistant:FormatNumber(totalItems)))
		for _, item in pairs(LibsFarmAssistant.session.items) do
			local rate = hours > 0 and string.format(' (%.0f/hr)', item.count / hours) or ''
			LibsFarmAssistant:Print(string.format('  %s x%s%s', item.link or item.name, LibsFarmAssistant:FormatNumber(item.count), rate))
		end
	end

	-- Money
	if LibsFarmAssistant.session.money > 0 then
		LibsFarmAssistant:Print('Money: ' .. LibsFarmAssistant:FormatMoney(LibsFarmAssistant.session.money))
	end

	-- Currency
	for name, data in pairs(LibsFarmAssistant.session.currencies) do
		LibsFarmAssistant:Print(string.format('Currency: %s x%s', name, LibsFarmAssistant:FormatNumber(data.count)))
	end

	-- Reputation
	for faction, gained in pairs(LibsFarmAssistant.session.reputation) do
		LibsFarmAssistant:Print(string.format('Rep: %s +%s', faction, LibsFarmAssistant:FormatNumber(gained)))
	end

	-- Honor
	local honor = LibsFarmAssistant.session.honor or 0
	if honor > 0 then
		local honorRate = hours > 0 and string.format(' (%s/hr)', LibsFarmAssistant:FormatNumber(honor / hours)) or ''
		LibsFarmAssistant:Print(string.format('Honor: %s%s', LibsFarmAssistant:FormatNumber(honor), honorRate))
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

---Format a number with comma separators
---@param number number
---@return string
function LibsFarmAssistant:FormatNumber(number)
	return BreakUpLargeNumbers(math.floor(number))
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
		return string.format('%sg %ds %dc', BreakUpLargeNumbers(gold), silver, rem)
	elseif silver > 0 then
		return string.format('%ds %dc', silver, rem)
	else
		return string.format('%dc', rem)
	end
end

-- Bridge methods on main addon
function LibsFarmAssistant:GetSessionDuration()
	return self.SessionManager:GetSessionDuration()
end

function LibsFarmAssistant:GetSessionHours()
	return self.SessionManager:GetSessionHours()
end

function LibsFarmAssistant:IsSessionActive()
	return self.SessionManager:IsSessionActive()
end

function LibsFarmAssistant:ToggleSession()
	self.SessionManager:ToggleSession()
end

function LibsFarmAssistant:ResetSession()
	self.SessionManager:ResetSession()
end

function LibsFarmAssistant:GetItemCounts()
	return self.SessionManager:GetItemCounts()
end

function LibsFarmAssistant:GetTotalVendorValue()
	return self.SessionManager:GetTotalVendorValue()
end

function LibsFarmAssistant:PrintSummary()
	self.SessionManager:PrintSummary()
end
