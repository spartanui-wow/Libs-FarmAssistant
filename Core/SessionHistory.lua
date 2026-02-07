---@class LibsFarmAssistant
local LibsFarmAssistant = LibStub('AceAddon-3.0'):GetAddon('Libs-FarmAssistant')

local MAX_HISTORY = 20
local MIN_SESSION_DURATION = 60 -- seconds

function LibsFarmAssistant:InitializeSessionHistory()
	-- Ensure history tables exist (backward compat)
	local char = self.dbobj.char
	if not char.history then
		char.history = {}
	end
	if not char.bestRates then
		char.bestRates = { itemsPerHour = 0, goldPerHour = 0, honorPerHour = 0 }
	end
end

---Save the current session to history before reset
function LibsFarmAssistant:SaveSessionToHistory()
	local session = self.session
	local duration = self:GetSessionDuration()

	-- Don't save very short sessions or empty sessions
	if duration < MIN_SESSION_DURATION then
		return
	end

	local _, totalItems = self:GetItemCounts()
	local honor = session.honor or 0
	local vendorValue = self:GetTotalVendorValue()

	-- Check if session has any data worth saving
	if totalItems == 0 and session.money == 0 and honor == 0 then
		return
	end

	local hours = duration / 3600

	-- Build simplified items list (no links/icons for storage efficiency)
	local simplifiedItems = {}
	for key, item in pairs(session.items) do
		simplifiedItems[key] = {
			name = item.name,
			count = item.count,
			quality = item.quality,
			sellPrice = item.sellPrice or 0,
		}
	end

	-- Build simplified currencies list (counts only)
	local simplifiedCurrencies = {}
	for name, data in pairs(session.currencies) do
		simplifiedCurrencies[name] = data.count
	end

	-- Create snapshot
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
		-- Computed rates for easy access
		itemsPerHour = hours > 0 and (totalItems / hours) or 0,
		goldPerHour = hours > 0 and (session.money / hours) or 0,
		honorPerHour = hours > 0 and (honor / hours) or 0,
	}

	-- Copy reputation
	for faction, gained in pairs(session.reputation) do
		snapshot.reputation[faction] = gained
	end

	-- Insert at front, trim to max
	local history = self.dbobj.char.history
	table.insert(history, 1, snapshot)
	while #history > MAX_HISTORY do
		table.remove(history)
	end

	-- Update personal bests
	self:UpdateBestRates(snapshot)

	self:Log('Session saved to history', 'info')
end

---Update personal best rates if current snapshot exceeds them
---@param snapshot table
function LibsFarmAssistant:UpdateBestRates(snapshot)
	local bests = self.dbobj.char.bestRates

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
function LibsFarmAssistant:GetHistoryAverages()
	local history = self.dbobj.char.history
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
