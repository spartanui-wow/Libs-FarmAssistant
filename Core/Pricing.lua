---@class LibsFarmAssistant
local LibsFarmAssistant = LibStub('AceAddon-3.0'):GetAddon('Libs-FarmAssistant')

-- Item values: the vendor price is always known once the item is cached; auction prices come
-- from an installed pricing addon when one is present. Items that bind on pickup can never be
-- sold on the auction house, so they always use the vendor price.

---@class LibsFarmAssistant.Pricing : AceModule, AceEvent-3.0
local Pricing = LibsFarmAssistant:NewModule('Pricing')
LibsFarmAssistant.Pricing = Pricing

local Compat = LibsFarmAssistant.Compat

local BIND_ON_PICKUP = 1
local BIND_QUEST = 4

-- Auction lookups are not free, so results are held for a few minutes.
local AUCTION_TTL = 300
local auctionCache = {}
local pendingItems = {}

function Pricing:OnEnable()
	self:RegisterEvent('ITEM_DATA_LOAD_RESULT', 'OnItemDataLoaded')
	self:RegisterEvent('GET_ITEM_INFO_RECEIVED', 'OnItemDataLoaded')
end

---Caches name, quality and prices for an item so the ledger can show it offline.
---@param itemID number
---@param link? string
---@return table|nil meta
function Pricing:Remember(itemID, link)
	if not itemID then
		return nil
	end
	local meta = LibsFarmAssistant.global.itemMeta
	local entry = meta[itemID]
	local name, _, quality, sellPrice, bindType = Compat.ItemInfo(link or itemID)
	if not name then
		if not pendingItems[itemID] then
			pendingItems[itemID] = true
			Compat.RequestItem(itemID)
		end
		return entry
	end
	pendingItems[itemID] = nil
	if not entry then
		entry = {}
		meta[itemID] = entry
	end
	entry.n = name
	entry.q = quality
	entry.p = sellPrice or 0
	entry.b = bindType
	return entry
end

function Pricing:OnItemDataLoaded(_, itemID, success)
	if itemID and success ~= false and pendingItems[itemID] then
		pendingItems[itemID] = nil
		self:Remember(itemID)
		LibsFarmAssistant:SendMessage('LIBSFA_ITEM_LOADED', itemID)
	end
end

---@param itemID number
---@return table meta Never nil; fields may be missing until the item loads
function Pricing:Meta(itemID)
	local entry = LibsFarmAssistant.global.itemMeta[itemID]
	if not entry or not entry.n then
		entry = self:Remember(itemID) or entry
	end
	return entry or {}
end

---@return boolean
function Pricing:HasAuctionSource()
	return (TSM_API and TSM_API.GetCustomPriceValue) ~= nil or (Auctionator and Auctionator.API and Auctionator.API.v1 and Auctionator.API.v1.GetAuctionPriceByItemID) ~= nil
end

---@param itemID number
---@return number|nil copper
function Pricing:AuctionPrice(itemID)
	local now = GetTime()
	local cached = auctionCache[itemID]
	if cached and now - cached.at < AUCTION_TTL then
		return cached.value
	end

	local value
	if TSM_API and TSM_API.GetCustomPriceValue then
		local ok, result = pcall(TSM_API.GetCustomPriceValue, 'DBMarket', 'i:' .. itemID)
		if ok and type(result) == 'number' and result > 0 then
			value = result
		end
	end
	if not value and Auctionator and Auctionator.API and Auctionator.API.v1 and Auctionator.API.v1.GetAuctionPriceByItemID then
		local ok, result = pcall(Auctionator.API.v1.GetAuctionPriceByItemID, 'Libs-FarmAssistant', itemID)
		if ok and type(result) == 'number' and result > 0 then
			value = result
		end
	end

	auctionCache[itemID] = { at = now, value = value }
	return value
end

---Value of one of this item in copper, following the player's price setting.
---@param itemID number
---@return number|nil copper
---@return string|nil kind 'vendor' or 'auction'
function Pricing:Value(itemID)
	local meta = self:Meta(itemID)
	local vendor = meta.p or 0
	local source = LibsFarmAssistant.db.pricing.source
	if source == 'vendor' or meta.b == BIND_ON_PICKUP or meta.b == BIND_QUEST then
		return vendor, 'vendor'
	end

	local auction = self:AuctionPrice(itemID)
	if source == 'auction' then
		if auction then
			return auction, 'auction'
		end
		return vendor, 'vendor'
	end
	if auction and auction > vendor then
		return auction, 'auction'
	end
	return vendor, 'vendor'
end

---Short description of what item values mean right now, for footers and tooltips.
---@return string
function Pricing:Describe()
	local source = LibsFarmAssistant.db.pricing.source
	if source == 'vendor' or not self:HasAuctionSource() then
		return 'Item values: vendor price'
	elseif source == 'auction' then
		return 'Item values: auction price, vendor for soulbound'
	end
	return 'Item values: auction or vendor, whichever is higher'
end
