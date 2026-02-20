---@class LibsFarmAssistant
local LibsFarmAssistant = LibStub('AceAddon-3.0'):GetAddon('Libs-FarmAssistant')

---@class LibsFarmAssistant.Notifications : AceModule, AceEvent-3.0, AceTimer-3.0
local Notifications = LibsFarmAssistant:NewModule('Notifications')
LibsFarmAssistant.Notifications = Notifications

function Notifications:OnEnable()
	self.lastNotificationTime = GetTime()
end

---Check if a session notification should be sent
---Called from UpdateDisplay() which fires every 60s and after tracking events
function Notifications:CheckSessionNotification()
	local settings = LibsFarmAssistant.db.sessionNotifications
	if not settings or not settings.enabled then
		return
	end

	if not LibsFarmAssistant:IsSessionActive() then
		return
	end

	local now = GetTime()
	local frequencySeconds = (settings.frequencyMinutes or 15) * 60

	if (now - self.lastNotificationTime) < frequencySeconds then
		return
	end

	self.lastNotificationTime = now

	local duration = LibsFarmAssistant:GetSessionDuration()
	local _, totalItems = LibsFarmAssistant:GetItemCounts()

	local parts = {}
	table.insert(parts, string.format('You have been farming for %s.', LibsFarmAssistant:FormatDuration(duration)))
	if totalItems > 0 then
		table.insert(parts, string.format('Items: %s', LibsFarmAssistant:FormatNumber(totalItems)))
	end
	if LibsFarmAssistant.session.money > 0 then
		table.insert(parts, string.format('Money: %s', LibsFarmAssistant:FormatMoney(LibsFarmAssistant.session.money)))
	end
	local honor = LibsFarmAssistant.session.honor or 0
	if honor > 0 then
		table.insert(parts, string.format('Honor: %s', LibsFarmAssistant:FormatNumber(honor)))
	end

	LibsFarmAssistant:Print('|cffffcc00Session Reminder:|r ' .. table.concat(parts, ' '))
end

-- Bridge method
function LibsFarmAssistant:CheckSessionNotification()
	if self.Notifications then
		self.Notifications:CheckSessionNotification()
	end
end
