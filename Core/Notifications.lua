---@class LibsFarmAssistant
local LibsFarmAssistant = LibStub('AceAddon-3.0'):GetAddon('Libs-FarmAssistant')

---@class LibsFarmAssistant.Notifications : AceModule, AceEvent-3.0, AceTimer-3.0
local Notifications = LibsFarmAssistant:NewModule('Notifications')
LibsFarmAssistant.Notifications = Notifications

local Ledger = LibsFarmAssistant.Ledger
local Format = LibsFarmAssistant.Format

function Notifications:OnEnable()
	self.lastNotificationTime = GetTime()
end

---Periodic chat reminder with the session so far. Called from UpdateDisplay.
function Notifications:CheckSessionNotification()
	local settings = LibsFarmAssistant.db.sessionNotifications
	if not settings or not settings.enabled or not LibsFarmAssistant:IsSessionActive() then
		return
	end

	local now = GetTime()
	if (now - self.lastNotificationTime) < (settings.frequencyMinutes or 15) * 60 then
		return
	end
	self.lastNotificationTime = now

	local session = Ledger:Session()
	local value = Ledger.TotalValue(session)
	local parts = { string.format('Farming for %s.', Format.Duration(LibsFarmAssistant:GetSessionDuration())) }
	if value > 0 then
		local perHour = Ledger.PerHour(value, session)
		parts[#parts + 1] = string.format('Value %s%s.', Format.Money(value), perHour and (' (' .. Format.Money(perHour) .. ' per hour)') or '')
	end
	if session.kills > 0 then
		parts[#parts + 1] = string.format('Kills %s.', Format.Number(session.kills))
	end
	LibsFarmAssistant:Print(table.concat(parts, ' '))
end

function LibsFarmAssistant:CheckSessionNotification()
	self.Notifications:CheckSessionNotification()
end
