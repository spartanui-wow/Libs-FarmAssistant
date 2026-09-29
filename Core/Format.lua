---@class LibsFarmAssistant
local LibsFarmAssistant = LibStub('AceAddon-3.0'):GetAddon('Libs-FarmAssistant')

-- Number, money and time formats shared by the window, tracker, tooltips and chat, so the same
-- figure always reads the same way everywhere.

---@class LibsFarmAssistant.Format
local Format = {}
LibsFarmAssistant.Format = Format

local floor = math.floor

local GOLD = 'ffd100'
local SILVER = 'c7c7cf'
local COPPER = 'eda55f'

---@param number number
---@return string
function Format.Number(number)
	number = floor((number or 0) + 0.5)
	if BreakUpLargeNumbers then
		return BreakUpLargeNumbers(number)
	end
	local text = tostring(number)
	local k
	repeat
		text, k = text:gsub('^(-?%d+)(%d%d%d)', '%1,%2')
	until k == 0
	return text
end

---Rates under 10 keep one decimal so slow drops do not all read as 0.
---@param number number|nil
---@return string
function Format.Rate(number)
	if not number then
		return '-'
	end
	if number > 0 and number < 10 then
		return string.format('%.1f', number)
	end
	return Format.Number(number)
end

---Large numbers shortened for narrow places: 1,234 / 12.3k / 1.23M.
---@param number number
---@return string
function Format.Short(number)
	number = number or 0
	local abs = math.abs(number)
	if abs >= 1e6 then
		return string.format('%.2fM', number / 1e6)
	elseif abs >= 1e4 then
		return string.format('%.1fk', number / 1e3)
	end
	return Format.Number(number)
end

---@param copper number
---@param colored? boolean Coin-colored figures for the window
---@param full? boolean Always show silver and copper
---@return string
function Format.Money(copper, colored, full)
	copper = floor((copper or 0) + 0.5)
	local gold = floor(copper / 10000)
	local silver = floor((copper % 10000) / 100)
	local rem = copper % 100

	local parts = {}
	local function Part(amount, suffix, color, pad)
		local figure = pad and string.format('%02d', amount) or Format.Number(amount)
		if colored then
			parts[#parts + 1] = string.format('|cff%s%s%s|r', color, figure, suffix)
		else
			parts[#parts + 1] = figure .. suffix
		end
	end

	if gold > 0 then
		Part(gold, 'g', GOLD)
		if full or gold < 1000 then
			Part(silver, 's', SILVER, true)
		end
		if full then
			Part(rem, 'c', COPPER, true)
		end
	elseif silver > 0 then
		Part(silver, 's', SILVER)
		Part(rem, 'c', COPPER, true)
	else
		Part(rem, 'c', COPPER)
	end
	return table.concat(parts, ' ')
end

---"1h 42m", "12m", "45s"
---@param seconds number
---@return string
function Format.Duration(seconds)
	seconds = floor(seconds or 0)
	local days = floor(seconds / 86400)
	local hours = floor((seconds % 86400) / 3600)
	local minutes = floor((seconds % 3600) / 60)
	if days > 0 then
		return string.format('%dd %dh', days, hours)
	elseif hours > 0 then
		return string.format('%dh %dm', hours, minutes)
	elseif minutes > 0 then
		return string.format('%dm', minutes)
	end
	return string.format('%ds', seconds)
end

---"1:42:18" for a running clock
---@param seconds number
---@return string
function Format.Clock(seconds)
	seconds = floor(seconds or 0)
	local hours = floor(seconds / 3600)
	local minutes = floor((seconds % 3600) / 60)
	local secs = seconds % 60
	if hours > 0 then
		return string.format('%d:%02d:%02d', hours, minutes, secs)
	end
	return string.format('%d:%02d', minutes, secs)
end

---"1 in 14" for drop rates; percentages above 1 in 2 read better as "72%".
---@param rate number|nil drops per attempt
---@return string
function Format.Odds(rate)
	if not rate or rate <= 0 then
		return '-'
	end
	if rate >= 0.5 then
		return string.format('%d%%', floor(rate * 100 + 0.5))
	end
	local n = 1 / rate
	if n < 10 then
		return string.format('1 in %.1f', n)
	end
	return '1 in ' .. Format.Number(n)
end

---@param percent number 0-1
---@return string
function Format.Percent(percent)
	percent = (percent or 0) * 100
	if percent > 0 and percent < 1 then
		return string.format('%.1f%%', percent)
	end
	return string.format('%d%%', floor(percent + 0.5))
end

---"Today 19:02", "Yesterday 21:10", "Sep 25 18:44"
---@param epoch number
---@return string
function Format.When(epoch)
	local day = date('%Y-%m-%d', epoch)
	local today = date('%Y-%m-%d')
	local yesterday = date('%Y-%m-%d', time() - 86400)
	if day == today then
		return 'Today ' .. date('%H:%M', epoch)
	elseif day == yesterday then
		return 'Yesterday ' .. date('%H:%M', epoch)
	end
	return date('%b %d %H:%M', epoch)
end

-- Kept for the options and older callers.
function LibsFarmAssistant:FormatNumber(number)
	return Format.Number(number)
end

function LibsFarmAssistant:FormatMoney(copper)
	return Format.Money(copper)
end

function LibsFarmAssistant:FormatDuration(seconds)
	return Format.Duration(seconds)
end
