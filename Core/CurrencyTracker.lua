---@class LibsFarmAssistant
local LibsFarmAssistant = LibStub('AceAddon-3.0'):GetAddon('Libs-FarmAssistant')

-- Currency gains come from CURRENCY_DISPLAY_UPDATE, which names the currency by ID and (on most
-- clients) carries the change. When the change is missing, the new total is compared with the
-- last one seen. Honor is kept on its own line because it means PvP on every client.

---@class LibsFarmAssistant.CurrencyTracker : AceModule, AceEvent-3.0, AceTimer-3.0
local CurrencyTracker = LibsFarmAssistant:NewModule('CurrencyTracker')
LibsFarmAssistant.CurrencyTracker = CurrencyTracker

local Compat = LibsFarmAssistant.Compat
local Ledger = LibsFarmAssistant.Ledger

-- Honor as a currency: Retail (1792), the Classic clients (1901) and the legacy Mists ID (392).
-- Counted as honor, never twice.
local HONOR_CURRENCIES = { [1792] = true, [1901] = true, [392] = true }

local honorPatterns

local function BuildHonorPatterns()
	honorPatterns = {}
	for _, key in ipairs({ 'COMBATLOG_HONORGAIN', 'COMBATLOG_HONORGAIN_NO_RANK', 'COMBATLOG_HONORAWARD', 'COMBATLOG_HONORGAIN_EXHAUSTION1' }) do
		local pattern = Compat.FormatToPattern(_G[key])
		if pattern then
			honorPatterns[#honorPatterns + 1] = pattern
		end
	end
end

function CurrencyTracker:OnEnable()
	self.known = {} -- currencyID -> last quantity seen
	-- Clients that pay honor as a currency are measured from it; the rest only announce it in chat.
	self.honorFromCurrency = Compat.IsRetail or Compat.CurrencyInfo(1901) ~= nil
	BuildHonorPatterns()

	self:RegisterEvent('CURRENCY_DISPLAY_UPDATE', 'OnCurrencyUpdate')
	self:RegisterEvent('CHAT_MSG_COMBAT_HONOR_GAIN', 'OnHonorChat')
end

function CurrencyTracker:OnCurrencyUpdate(_, currencyID, quantity, quantityChange)
	currencyID = Compat.Readable(currencyID)
	if not currencyID then
		return
	end
	quantity = Compat.Readable(quantity)
	quantityChange = Compat.Readable(quantityChange)

	local _, _, current = Compat.CurrencyInfo(currencyID)
	current = quantity or current
	local previous = self.known[currencyID]
	if current then
		self.known[currencyID] = current
	end

	local gained = quantityChange
	if gained == nil and previous and current then
		gained = current - previous
	end
	if not gained or gained <= 0 then
		return
	end
	if not LibsFarmAssistant:IsSessionActive() then
		return
	end

	if HONOR_CURRENCIES[currencyID] then
		self.honorFromCurrency = true
		if LibsFarmAssistant.db.tracking.honor then
			Ledger:AddHonor(gained)
		end
	elseif LibsFarmAssistant.db.tracking.currency then
		Ledger:AddCurrency(currencyID, gained)
	else
		return
	end
	LibsFarmAssistant:SendMessage('LIBSFA_CURRENCY_GAINED', currencyID, gained)
	LibsFarmAssistant:UpdateDisplay()
end

---Parses honor from chat only on clients where honor is not a currency.
---@param text string
---@return number|nil
function CurrencyTracker:ParseHonor(text)
	if not honorPatterns then
		BuildHonorPatterns()
	end
	for _, pattern in ipairs(honorPatterns) do
		local a, b, c = text:match(pattern)
		-- The honor figure is the last number in every honor line's format.
		local figure = c or b or a
		if figure then
			local amount = Compat.ParseNumber(figure)
			if amount then
				return amount
			end
		end
	end
	return nil
end

function CurrencyTracker:OnHonorChat(_, text)
	if self.honorFromCurrency or type(text) ~= 'string' or not Compat.CanAccess(text) then
		return
	end
	if not LibsFarmAssistant:IsSessionActive() or not LibsFarmAssistant.db.tracking.honor then
		return
	end
	local amount = self:ParseHonor(text)
	if amount and amount > 0 then
		Ledger:AddHonor(amount)
		LibsFarmAssistant:UpdateDisplay()
	end
end
