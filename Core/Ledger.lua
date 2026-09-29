---@class LibsFarmAssistant
local LibsFarmAssistant = LibStub('AceAddon-3.0'):GetAddon('Libs-FarmAssistant')

-- The ledger is the single record of everything gained. Each gain is written to four buckets
-- at once (the current session, today, this month, all time); weeks are summed from days.
-- Every bucket has the same shape, so every screen can read any time window the same way.

---@class FarmSourceStats
---@field kills number Creatures counted dead (by kill events or by looting the corpse)
---@field loots number Corpses, nodes or catches opened
---@field money number Copper looted from this source
---@field items table<number, number> itemID -> quantity
---@field drops table<number, number> itemID -> number of loots that contained it

---@class FarmBucket
---@field time number Active farming seconds
---@field kills number
---@field loots number
---@field xp number
---@field honor number
---@field money table<string, number> category -> copper gained ('loot', 'vendor', 'quest', 'mail', 'other')
---@field spent number
---@field items table<number, number> itemID -> quantity
---@field currencies table<number, number> currencyID -> amount
---@field rep table<number, number> factionID -> amount
---@field sources table<string, FarmSourceStats>

---@class LibsFarmAssistant.Ledger
local Ledger = {}
LibsFarmAssistant.Ledger = Ledger

local DAY_KEEP = 62
local SESSION_KEEP = 100

Ledger.MONEY_CATEGORIES = { 'loot', 'vendor', 'quest', 'mail', 'other' }

-- Bumped on every write so cached window sums know when to rebuild.
Ledger.version = 0

---@return FarmBucket
function Ledger.NewBucket()
	return {
		time = 0,
		kills = 0,
		loots = 0,
		xp = 0,
		honor = 0,
		money = {},
		spent = 0,
		items = {},
		currencies = {},
		rep = {},
		sources = {},
	}
end

---Fills in any field an older saved bucket is missing.
---@param bucket table
---@return FarmBucket
function Ledger.Normalize(bucket)
	local fresh = Ledger.NewBucket()
	for key, value in pairs(fresh) do
		if bucket[key] == nil then
			bucket[key] = value
		end
	end
	return bucket
end

---@param epoch? number
---@return string
function Ledger.DayKey(epoch)
	return date('%Y-%m-%d', epoch or time())
end

---@param epoch? number
---@return string
function Ledger.MonthKey(epoch)
	return date('%Y-%m', epoch or time())
end

---@param key string 'YYYY-MM-DD'
---@return number epoch Noon of that day, so daylight saving never moves it across midnight
function Ledger.DayEpoch(key)
	local y, m, d = key:match('^(%d+)-(%d+)-(%d+)$')
	if not y then
		return 0
	end
	return time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 12 })
end

----------------------------------------------------------------------------------------------------
-- Storage access
----------------------------------------------------------------------------------------------------

local function Char()
	return LibsFarmAssistant.char
end

---@return FarmBucket
function Ledger:Session()
	return Char().session or LibsFarmAssistant.SessionManager:Begin()
end

---@return FarmBucket
function Ledger:Lifetime()
	local char = Char()
	if not char.lifetime then
		char.lifetime = Ledger.NewBucket()
	end
	return char.lifetime
end

---@param key? string
---@return FarmBucket
function Ledger:Day(key)
	local days = Char().days
	key = key or Ledger.DayKey()
	if not days[key] then
		days[key] = Ledger.NewBucket()
	end
	return days[key]
end

---@param key? string
---@return FarmBucket
function Ledger:Month(key)
	local months = Char().months
	key = key or Ledger.MonthKey()
	if not months[key] then
		months[key] = Ledger.NewBucket()
	end
	return months[key]
end

local writeTargets = {}

---The buckets a gain is written into, in a reused table.
---@return FarmBucket[]
function Ledger:Targets()
	writeTargets[1] = self:Session()
	writeTargets[2] = self:Day()
	writeTargets[3] = self:Month()
	writeTargets[4] = self:Lifetime()
	return writeTargets
end

local function Touch()
	Ledger.version = Ledger.version + 1
end

---@param bucket FarmBucket
---@param key string
---@return FarmSourceStats
local function SourceIn(bucket, key)
	local stats = bucket.sources[key]
	if not stats then
		stats = { kills = 0, loots = 0, money = 0, items = {}, drops = {} }
		bucket.sources[key] = stats
	end
	return stats
end
Ledger.SourceIn = SourceIn

----------------------------------------------------------------------------------------------------
-- Writing
----------------------------------------------------------------------------------------------------

---@param seconds number
function Ledger:AddTime(seconds)
	if not seconds or seconds <= 0 then
		return
	end
	for _, bucket in ipairs(self:Targets()) do
		bucket.time = bucket.time + seconds
	end
	Touch()
end

---@param sourceKey string|nil
function Ledger:AddKill(sourceKey)
	for _, bucket in ipairs(self:Targets()) do
		bucket.kills = bucket.kills + 1
		if sourceKey then
			local stats = SourceIn(bucket, sourceKey)
			stats.kills = stats.kills + 1
		end
	end
	Touch()
end

---A corpse, node, catch or container was opened.
---@param sourceKey string
function Ledger:AddLoot(sourceKey)
	for _, bucket in ipairs(self:Targets()) do
		bucket.loots = bucket.loots + 1
		local stats = SourceIn(bucket, sourceKey)
		stats.loots = stats.loots + 1
	end
	Touch()
end

---@param itemID number
---@param quantity number
---@param sourceKey string|nil
---@param isDrop boolean|nil True once per source per loot, so "1 in N" counts loots, not stack sizes
function Ledger:AddItem(itemID, quantity, sourceKey, isDrop)
	if not itemID or not quantity or quantity <= 0 then
		return
	end
	for _, bucket in ipairs(self:Targets()) do
		bucket.items[itemID] = (bucket.items[itemID] or 0) + quantity
		if sourceKey then
			local stats = SourceIn(bucket, sourceKey)
			stats.items[itemID] = (stats.items[itemID] or 0) + quantity
			if isDrop then
				stats.drops[itemID] = (stats.drops[itemID] or 0) + 1
			end
		end
	end
	Touch()
end

---@param category string One of Ledger.MONEY_CATEGORIES
---@param copper number
function Ledger:AddMoney(category, copper)
	if not copper or copper <= 0 then
		return
	end
	for _, bucket in ipairs(self:Targets()) do
		bucket.money[category] = (bucket.money[category] or 0) + copper
	end
	Touch()
end

---Coin looted from one source (the category total is written by AddMoney).
---@param sourceKey string
---@param copper number
function Ledger:AddSourceMoney(sourceKey, copper)
	if not copper or copper <= 0 then
		return
	end
	for _, bucket in ipairs(self:Targets()) do
		local stats = SourceIn(bucket, sourceKey)
		stats.money = stats.money + copper
	end
	Touch()
end

---@param copper number
function Ledger:AddSpent(copper)
	if not copper or copper <= 0 then
		return
	end
	for _, bucket in ipairs(self:Targets()) do
		bucket.spent = bucket.spent + copper
	end
	Touch()
end

---@param currencyID number
---@param amount number
function Ledger:AddCurrency(currencyID, amount)
	if not currencyID or not amount or amount <= 0 then
		return
	end
	for _, bucket in ipairs(self:Targets()) do
		bucket.currencies[currencyID] = (bucket.currencies[currencyID] or 0) + amount
	end
	Touch()
end

---@param factionID number
---@param amount number
function Ledger:AddRep(factionID, amount)
	if not factionID or not amount or amount <= 0 then
		return
	end
	for _, bucket in ipairs(self:Targets()) do
		bucket.rep[factionID] = (bucket.rep[factionID] or 0) + amount
	end
	Touch()
end

---@param amount number
function Ledger:AddXP(amount)
	if not amount or amount <= 0 then
		return
	end
	for _, bucket in ipairs(self:Targets()) do
		bucket.xp = bucket.xp + amount
	end
	Touch()
end

---@param amount number
function Ledger:AddHonor(amount)
	if not amount or amount <= 0 then
		return
	end
	for _, bucket in ipairs(self:Targets()) do
		bucket.honor = bucket.honor + amount
	end
	Touch()
end

----------------------------------------------------------------------------------------------------
-- Reading
----------------------------------------------------------------------------------------------------

local function AddInto(target, source)
	for key, value in pairs(source) do
		target[key] = (target[key] or 0) + value
	end
end

---Adds one bucket into another (used to build weeks from days).
---@param target FarmBucket
---@param source FarmBucket
function Ledger.Merge(target, source)
	target.time = target.time + (source.time or 0)
	target.kills = target.kills + (source.kills or 0)
	target.loots = target.loots + (source.loots or 0)
	target.xp = target.xp + (source.xp or 0)
	target.honor = target.honor + (source.honor or 0)
	target.spent = target.spent + (source.spent or 0)
	AddInto(target.money, source.money or {})
	AddInto(target.items, source.items or {})
	AddInto(target.currencies, source.currencies or {})
	AddInto(target.rep, source.rep or {})
	for key, stats in pairs(source.sources or {}) do
		local into = SourceIn(target, key)
		into.kills = into.kills + (stats.kills or 0)
		into.loots = into.loots + (stats.loots or 0)
		into.money = into.money + (stats.money or 0)
		AddInto(into.items, stats.items or {})
		AddInto(into.drops, stats.drops or {})
	end
	return target
end

---First day key of the current week: the weekly reset when the client has one, otherwise Monday.
---@return string
function Ledger.WeekStartKey()
	local reset = LibsFarmAssistant.Compat.LastWeeklyReset()
	if reset then
		return Ledger.DayKey(reset)
	end
	local now = date('*t')
	local sinceMonday = (now.wday + 5) % 7
	return Ledger.DayKey(time() - sinceMonday * 86400)
end

local windowCache = {}

Ledger.WINDOWS = { 'session', 'today', 'week', 'month', 'all' }

---@param name string 'session', 'today', 'week', 'month' or 'all'
---@return FarmBucket
function Ledger:Window(name)
	if name == 'session' then
		return self:Session()
	elseif name == 'today' then
		return self:Day()
	elseif name == 'month' then
		return self:Month()
	elseif name == 'all' then
		return self:Lifetime()
	end

	local cached = windowCache[name]
	if cached and cached.version == self.version and cached.day == Ledger.DayKey() then
		return cached.bucket
	end

	local bucket = Ledger.NewBucket()
	local startKey = Ledger.WeekStartKey()
	for key, day in pairs(Char().days) do
		if key >= startKey then
			Ledger.Merge(bucket, day)
		end
	end
	windowCache[name] = { version = self.version, day = Ledger.DayKey(), bucket = bucket }
	return bucket
end

---Per-hour rate, or nil until there is at least a minute of farming to measure.
---@param amount number
---@param bucket FarmBucket
---@return number|nil
function Ledger.PerHour(amount, bucket)
	local seconds = bucket and bucket.time or 0
	if seconds < 60 then
		return nil
	end
	return amount * 3600 / seconds
end

---@param bucket FarmBucket
---@return number total, number unique
function Ledger.ItemCounts(bucket)
	local total, unique = 0, 0
	for _, count in pairs(bucket.items) do
		total = total + count
		unique = unique + 1
	end
	return total, unique
end

---@param bucket FarmBucket
---@param category? string
---@return number copper
function Ledger.Money(bucket, category)
	if category then
		return bucket.money[category] or 0
	end
	local total = 0
	for _, copper in pairs(bucket.money) do
		total = total + copper
	end
	return total
end

---@param bucket FarmBucket
---@return number copper Estimated value of every item in the bucket
function Ledger.ItemValue(bucket)
	local Pricing = LibsFarmAssistant.Pricing
	local total = 0
	for itemID, count in pairs(bucket.items) do
		total = total + (Pricing:Value(itemID) or 0) * count
	end
	return total
end

---Everything the time produced: looted coin, quest gold, and the value of looted items. Vendor
---sales are left out because the items sold were already counted when looted.
---@param bucket FarmBucket
---@return number copper
function Ledger.TotalValue(bucket)
	return Ledger.Money(bucket, 'loot') + Ledger.Money(bucket, 'quest') + Ledger.ItemValue(bucket)
end

---@param bucket FarmBucket
---@return number
function Ledger.RepTotal(bucket)
	local total = 0
	for _, amount in pairs(bucket.rep) do
		total = total + amount
	end
	return total
end

---@class FarmItemSource
---@field key string
---@field kills number Attempts: kills for creatures, loots for everything else
---@field drops number
---@field quantity number
---@field rate number|nil drops / attempts

---Sources that dropped the item in this bucket, best rate first.
---@param bucket FarmBucket
---@param itemID number
---@return FarmItemSource[]
function Ledger.ItemSources(bucket, itemID)
	local list = {}
	for key, stats in pairs(bucket.sources) do
		local drops = stats.drops[itemID]
		if drops and drops > 0 then
			local attempts = Ledger.Attempts(key, stats)
			list[#list + 1] = {
				key = key,
				kills = attempts,
				drops = drops,
				quantity = stats.items[itemID] or 0,
				rate = attempts > 0 and math.min(1, drops / attempts) or nil,
			}
		end
	end
	table.sort(list, function(a, b)
		if (a.rate or 0) ~= (b.rate or 0) then
			return (a.rate or 0) > (b.rate or 0)
		end
		return a.drops > b.drops
	end)
	return list
end

---How many chances a source gave: kills for creatures, opens for nodes, chests and catches.
---@param key string
---@param stats FarmSourceStats
---@return number
function Ledger.Attempts(key, stats)
	if key:sub(1, 2) == 'c:' then
		return math.max(stats.kills or 0, stats.loots or 0)
	end
	return math.max(stats.loots or 0, stats.kills or 0)
end

----------------------------------------------------------------------------------------------------
-- Sessions and housekeeping
----------------------------------------------------------------------------------------------------

---Stores a short summary of the finished session. Sessions under a minute with nothing gained
---are dropped.
---@param session table
function Ledger:Archive(session)
	if not session or (session.time or 0) < 60 then
		return
	end
	local itemTotal = Ledger.ItemCounts(session)
	if itemTotal == 0 and Ledger.Money(session) == 0 and session.kills == 0 and session.xp == 0 and Ledger.RepTotal(session) == 0 then
		return
	end

	local top = {}
	for itemID, count in pairs(session.items) do
		top[#top + 1] = { id = itemID, count = count }
	end
	table.sort(top, function(a, b)
		return a.count > b.count
	end)
	for i = #top, 6, -1 do
		top[i] = nil
	end

	local sessions = Char().sessions
	table.insert(sessions, 1, {
		start = session.started or time(),
		stop = session.lastSeen or time(),
		time = session.time,
		zone = session.zone,
		kills = session.kills,
		items = itemTotal,
		loot = Ledger.Money(session, 'loot'),
		value = Ledger.TotalValue(session),
		xp = session.xp,
		rep = Ledger.RepTotal(session),
		honor = session.honor,
		top = top,
	})
	for i = #sessions, SESSION_KEEP + 1, -1 do
		sessions[i] = nil
	end
end

---Best value per hour across archived sessions of at least ten minutes.
---@return number|nil perHour, table|nil session
function Ledger:BestSession()
	local best, bestSession
	for _, s in ipairs(Char().sessions) do
		if (s.time or 0) >= 600 then
			local rate = (s.value or 0) * 3600 / s.time
			if not best or rate > best then
				best, bestSession = rate, s
			end
		end
	end
	return best, bestSession
end

---Average value per hour across archived sessions of at least ten minutes.
---@return number|nil
function Ledger:AverageRate()
	local value, seconds = 0, 0
	for _, s in ipairs(Char().sessions) do
		if (s.time or 0) >= 600 then
			value = value + (s.value or 0)
			seconds = seconds + s.time
		end
	end
	if seconds < 600 then
		return nil
	end
	return value * 3600 / seconds
end

---Drops day buckets older than two months. Months and all-time keep their totals.
function Ledger:Prune()
	local cutoff = Ledger.DayKey(time() - DAY_KEEP * 86400)
	local days = Char().days
	for key in pairs(days) do
		if key < cutoff then
			days[key] = nil
		end
	end
	-- Past months keep their totals; per-source drop tables live on in all-time.
	local current = Ledger.MonthKey()
	for key, month in pairs(Char().months) do
		if key < current and month.sources and next(month.sources) then
			month.sources = {}
		end
	end
end

----------------------------------------------------------------------------------------------------
-- Names
----------------------------------------------------------------------------------------------------

local SOURCE_KIND_LABEL = {
	c = 'creature',
	g = 'gathering',
	o = 'object',
	f = 'fishing',
	i = 'container',
	e = 'boss',
	p = 'pickpocket',
	q = 'reward',
}

---@param key string
---@return string kind
function Ledger.SourceKind(key)
	return SOURCE_KIND_LABEL[key:sub(1, 1)] or 'other'
end

---@param key string
---@return string name
function Ledger.SourceName(key)
	local meta = LibsFarmAssistant.global.sourceMeta[key]
	if meta and meta.n then
		return meta.n
	end
	local prefix, id = key:match('^(%a):(.*)$')
	if prefix == 'c' then
		return 'Creature ' .. id
	elseif prefix == 'o' then
		return 'Object ' .. id
	elseif prefix == 'f' then
		return 'Fishing'
	elseif key == 'i' then
		return 'Containers'
	elseif key == 'q' then
		return 'Rewards and other'
	end
	return key
end

---@param key string
---@param name string|nil
---@param kind? string
function Ledger.RememberSource(key, name, kind)
	if not name or name == '' then
		return
	end
	local meta = LibsFarmAssistant.global.sourceMeta
	local entry = meta[key]
	if not entry then
		entry = {}
		meta[key] = entry
	end
	entry.n = name
	entry.k = kind or entry.k
end
