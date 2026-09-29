---@class LibsFarmAssistant
local LibsFarmAssistant = LibStub('AceAddon-3.0'):GetAddon('Libs-FarmAssistant')

-- Gold is measured by watching the purse change, which works in every language. What was open
-- at that moment decides where it came from: a loot window means looted coin, a merchant means a
-- vendor sale, the mailbox means auctions and mail, a quest window means a quest reward.

---@class LibsFarmAssistant.MoneyTracker : AceModule, AceEvent-3.0, AceTimer-3.0
local MoneyTracker = LibsFarmAssistant:NewModule('MoneyTracker')
LibsFarmAssistant.MoneyTracker = MoneyTracker

local Ledger = LibsFarmAssistant.Ledger
local Compat = LibsFarmAssistant.Compat

local GRACE = 2

function MoneyTracker:OnEnable()
	self.last = GetMoney()
	self.open = {} -- context -> true while its window is open
	self.closedAt = {} -- context -> GetTime() it closed

	self:RegisterEvent('PLAYER_MONEY', 'OnMoney')
	self:RegisterEvent('MERCHANT_SHOW', 'Open', 'vendor')
	self:RegisterEvent('MERCHANT_CLOSED', 'Close', 'vendor')
	self:RegisterEvent('MAIL_SHOW', 'Open', 'mail')
	self:RegisterEvent('MAIL_CLOSED', 'Close', 'mail')
	self:RegisterEvent('QUEST_COMPLETE', 'Open', 'quest')
	self:RegisterEvent('QUEST_FINISHED', 'Close', 'quest')
	self:RegisterEvent('TRADE_SHOW', 'Open', 'trade')
	self:RegisterEvent('TRADE_CLOSED', 'Close', 'trade')
	Compat.RegisterEvent(self, 'AUCTION_HOUSE_SHOW', 'Open', 'auction')
	Compat.RegisterEvent(self, 'AUCTION_HOUSE_CLOSED', 'Close', 'auction')
	Compat.RegisterEvent(self, 'QUEST_TURNED_IN', 'OnQuestTurnedIn')
	self:RegisterMessage('LIBSFA_SESSION_STARTED', 'Snapshot')
end

function MoneyTracker:Snapshot()
	self.last = GetMoney()
end

function MoneyTracker:Open(context)
	self.open[context] = true
end

function MoneyTracker:Close(context)
	self.open[context] = nil
	self.closedAt[context] = GetTime()
end

function MoneyTracker:OnQuestTurnedIn()
	self.closedAt.quest = GetTime()
end

---@param context string
---@return boolean
function MoneyTracker:IsRecent(context)
	return self.open[context] or (GetTime() - (self.closedAt[context] or 0)) < GRACE
end

---True while buying, trading or at the mailbox or auction house, when items arriving in bags
---are purchases or deliveries, not rewards.
---@return boolean
function MoneyTracker:IsShoppingOrTrading()
	return self:IsRecent('vendor') or self:IsRecent('mail') or self:IsRecent('trade') or self:IsRecent('auction') or false
end

---@return string category
function MoneyTracker:Category()
	local loot = LibsFarmAssistant.LootTracker
	-- A window that is open right now outranks one that closed a moment ago.
	if loot and loot:IsWindowOpen() then
		return 'loot'
	elseif self.open.vendor then
		return 'vendor'
	elseif self.open.mail or self.open.auction then
		return 'mail'
	elseif self.open.trade then
		return 'other'
	elseif self.open.quest then
		return 'quest'
	elseif loot and loot:RecentlyLooting() then
		return 'loot'
	elseif self:IsRecent('quest') then
		return 'quest'
	elseif self:IsRecent('vendor') then
		return 'vendor'
	elseif self:IsRecent('mail') then
		return 'mail'
	end
	return 'other'
end

function MoneyTracker:OnMoney()
	local now = GetMoney()
	local delta = now - (self.last or now)
	self.last = now

	if delta == 0 or not LibsFarmAssistant:IsSessionActive() or not LibsFarmAssistant.db.tracking.money then
		return
	end

	if delta > 0 then
		local category = self:Category()
		Ledger:AddMoney(category, delta)
		if LibsFarmAssistant.db.chatEcho and category == 'loot' then
			LibsFarmAssistant:Print('+' .. LibsFarmAssistant.Format.Money(delta))
		end
	else
		Ledger:AddSpent(-delta)
	end
	LibsFarmAssistant:UpdateDisplay()
end

function LibsFarmAssistant:SnapshotMoney()
	if self.MoneyTracker then
		self.MoneyTracker:Snapshot()
	end
end
