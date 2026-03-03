---@class LibsFarmAssistant
local LibsFarmAssistant = LibStub('AceAddon-3.0'):GetAddon('Libs-FarmAssistant')
local canaccessvalue = canaccessvalue or function() return true end

---@class LibsFarmAssistant.CurrencyTracker : AceModule, AceEvent-3.0, AceTimer-3.0
local CurrencyTracker = LibsFarmAssistant:NewModule('CurrencyTracker')
LibsFarmAssistant.CurrencyTracker = CurrencyTracker

function CurrencyTracker:OnEnable()
	if LibsFarmAssistant.db.tracking.currency then
		self:RegisterEvent('CHAT_MSG_CURRENCY', 'OnCurrencyReceived')
	end
end

function CurrencyTracker:OnDisable()
	self:UnregisterAllEvents()
end

---Handle CHAT_MSG_CURRENCY event
---@param event string
---@param text string Chat message text
function CurrencyTracker:OnCurrencyReceived(event, text)
	if not LibsFarmAssistant:IsSessionActive() then
		return
	end

	if not text or not canaccessvalue(text) then
		return
	end

	local currencyLink = text:match('|c%x+|Hcurrency:%d+[:%d]*|h%[.-%]|h|r')
	if not currencyLink then
		return
	end

	local currencyName = currencyLink:match('%[(.-)%]')
	if not currencyName then
		return
	end

	local quantity = tonumber(text:match('x(%d+)')) or 1

	local currencyID = tonumber(currencyLink:match('currency:(%d+)'))
	local icon
	if currencyID then
		local info = C_CurrencyInfo.GetCurrencyInfo(currencyID)
		if info then
			icon = info.iconFileID
		end
	end

	local currencies = LibsFarmAssistant.session.currencies
	if currencies[currencyName] then
		currencies[currencyName].count = currencies[currencyName].count + quantity
	else
		currencies[currencyName] = {
			name = currencyName,
			icon = icon,
			count = quantity,
		}
	end

	LibsFarmAssistant:Log(string.format('Currency: %s x%d', currencyName, quantity), 'debug')
	LibsFarmAssistant:UpdateDisplay()

	if LibsFarmAssistant.db.chatEcho then
		LibsFarmAssistant:Print(string.format('[Farm] %s x%d', currencyName, quantity))
	end
end
