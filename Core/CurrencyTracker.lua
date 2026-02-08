---@class LibsFarmAssistant
local LibsFarmAssistant = LibStub('AceAddon-3.0'):GetAddon('Libs-FarmAssistant')

function LibsFarmAssistant:InitializeCurrencyTracker()
	if self.db.tracking.currency then
		self:RegisterEvent('CHAT_MSG_CURRENCY', 'OnCurrencyReceived')
	end
end

---Handle CHAT_MSG_CURRENCY event
---@param event string
---@param text string Chat message text
function LibsFarmAssistant:OnCurrencyReceived(event, text)
	if not self:IsSessionActive() then
		return
	end

	-- Currency messages contain currency links: |cff...|Hcurrency:ID:AMOUNT|h[Name]|h|r
	local currencyLink = text:match('|c%x+|Hcurrency:%d+[:%d]*|h%[.-%]|h|r')
	if not currencyLink then
		return
	end

	-- Extract name from link
	local currencyName = currencyLink:match('%[(.-)%]')
	if not currencyName then
		return
	end

	-- Extract quantity
	local quantity = tonumber(text:match('x(%d+)')) or 1

	-- Extract currency icon if possible
	local currencyID = tonumber(currencyLink:match('currency:(%d+)'))
	local icon
	if currencyID then
		local info = C_CurrencyInfo.GetCurrencyInfo(currencyID)
		if info then
			icon = info.iconFileID
		end
	end

	-- Record
	local currencies = self.session.currencies
	if currencies[currencyName] then
		currencies[currencyName].count = currencies[currencyName].count + quantity
	else
		currencies[currencyName] = {
			name = currencyName,
			icon = icon,
			count = quantity,
		}
	end

	self:Log(string.format('Currency: %s x%d', currencyName, quantity), 'debug')
	self:UpdateDisplay()

	if self.db.chatEcho then
		self:Print(string.format('[Farm] %s x%d', currencyName, quantity))
	end
end
