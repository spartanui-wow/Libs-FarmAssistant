---@class LibsFarmAssistant
local LibsFarmAssistant = LibStub('AceAddon-3.0'):GetAddon('Libs-FarmAssistant')

local lastNotificationTime = 0

function LibsFarmAssistant:InitializeNotifications()
	-- Reset notification timer on load
	lastNotificationTime = GetTime()
end

---Check if a session notification should be sent
---Called from UpdateDisplay() which fires every 60s and after tracking events
function LibsFarmAssistant:CheckSessionNotification()
	local settings = self.db.sessionNotifications
	if not settings or not settings.enabled then
		return
	end

	if not self:IsSessionActive() then
		return
	end

	local now = GetTime()
	local frequencySeconds = (settings.frequencyMinutes or 15) * 60

	if (now - lastNotificationTime) < frequencySeconds then
		return
	end

	lastNotificationTime = now

	local duration = self:GetSessionDuration()
	local _, totalItems = self:GetItemCounts()

	local parts = {}
	table.insert(parts, string.format('You have been farming for %s.', self:FormatDuration(duration)))
	if totalItems > 0 then
		table.insert(parts, string.format('Items: %s', self:FormatNumber(totalItems)))
	end
	if self.session.money > 0 then
		table.insert(parts, string.format('Money: %s', self:FormatMoney(self.session.money)))
	end
	local honor = self.session.honor or 0
	if honor > 0 then
		table.insert(parts, string.format('Honor: %s', self:FormatNumber(honor)))
	end

	self:Print('|cffffcc00Session Reminder:|r ' .. table.concat(parts, ' '))
end
