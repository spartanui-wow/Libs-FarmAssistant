---@class LibsFarmAssistant
local LibsFarmAssistant = LibStub('AceAddon-3.0'):GetAddon('Libs-FarmAssistant')

---@class LibsFarmAssistant.SessionHistory : AceModule, AceEvent-3.0, AceTimer-3.0
local SessionHistory = LibsFarmAssistant:NewModule('SessionHistory')
LibsFarmAssistant.SessionHistory = SessionHistory

local MAX_HISTORY = 20
local MIN_SESSION_DURATION = 60 -- seconds

function SessionHistory:OnEnable()
	-- Ensure history tables exist (backward compat)
	local char = LibsFarmAssistant.dbobj.char
	if not char.history then
		char.history = {}
	end
	if not char.bestRates then
		char.bestRates = { itemsPerHour = 0, goldPerHour = 0, honorPerHour = 0 }
	end
end

---Save the current session to history before reset
function SessionHistory:SaveSessionToHistory()
	local session = LibsFarmAssistant.session
	local duration = LibsFarmAssistant:GetSessionDuration()

	if duration < MIN_SESSION_DURATION then
		return
	end

	local _, totalItems = LibsFarmAssistant:GetItemCounts()
	local honor = session.honor or 0
	local vendorValue = LibsFarmAssistant:GetTotalVendorValue()

	if totalItems == 0 and session.money == 0 and honor == 0 then
		return
	end

	local hours = duration / 3600

	local simplifiedItems = {}
	for key, item in pairs(session.items) do
		simplifiedItems[key] = {
			name = item.name,
			count = item.count,
			quality = item.quality,
			sellPrice = item.sellPrice or 0,
		}
	end

	local simplifiedCurrencies = {}
	for name, data in pairs(session.currencies) do
		simplifiedCurrencies[name] = data.count
	end

	local snapshot = {
		timestamp = time(),
		duration = duration,
		totalItems = totalItems,
		items = simplifiedItems,
		money = session.money,
		currencies = simplifiedCurrencies,
		reputation = {},
		honor = honor,
		totalVendorValue = vendorValue,
		itemsPerHour = hours > 0 and (totalItems / hours) or 0,
		goldPerHour = hours > 0 and (session.money / hours) or 0,
		honorPerHour = hours > 0 and (honor / hours) or 0,
	}

	for faction, gained in pairs(session.reputation) do
		snapshot.reputation[faction] = gained
	end

	local history = LibsFarmAssistant.dbobj.char.history
	table.insert(history, 1, snapshot)
	while #history > MAX_HISTORY do
		table.remove(history)
	end

	self:UpdateBestRates(snapshot)

	LibsFarmAssistant:Log('Session saved to history', 'info')
end

---Update personal best rates if current snapshot exceeds them
---@param snapshot table
function SessionHistory:UpdateBestRates(snapshot)
	local bests = LibsFarmAssistant.dbobj.char.bestRates

	if snapshot.itemsPerHour > bests.itemsPerHour then
		bests.itemsPerHour = snapshot.itemsPerHour
	end
	if snapshot.goldPerHour > bests.goldPerHour then
		bests.goldPerHour = snapshot.goldPerHour
	end
	if snapshot.honorPerHour > bests.honorPerHour then
		bests.honorPerHour = snapshot.honorPerHour
	end
end

---Get historical averages across all saved sessions
---@return table averages { itemsPerHour, goldPerHour, honorPerHour, sessionCount }
function SessionHistory:GetHistoryAverages()
	local history = LibsFarmAssistant.dbobj.char.history
	local result = { itemsPerHour = 0, goldPerHour = 0, honorPerHour = 0, sessionCount = #history }

	if #history == 0 then
		return result
	end

	local totalItemRate = 0
	local totalGoldRate = 0
	local totalHonorRate = 0

	for _, snap in ipairs(history) do
		totalItemRate = totalItemRate + (snap.itemsPerHour or 0)
		totalGoldRate = totalGoldRate + (snap.goldPerHour or 0)
		totalHonorRate = totalHonorRate + (snap.honorPerHour or 0)
	end

	result.itemsPerHour = totalItemRate / #history
	result.goldPerHour = totalGoldRate / #history
	result.honorPerHour = totalHonorRate / #history

	return result
end

-- Bridge methods on main addon
function LibsFarmAssistant:SaveSessionToHistory()
	if self.SessionHistory then
		self.SessionHistory:SaveSessionToHistory()
	end
end

function LibsFarmAssistant:GetHistoryAverages()
	if self.SessionHistory then
		return self.SessionHistory:GetHistoryAverages()
	end
	return { itemsPerHour = 0, goldPerHour = 0, honorPerHour = 0, sessionCount = 0 }
end
