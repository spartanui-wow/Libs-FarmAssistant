---@class LibsFarmAssistant
local LibsFarmAssistant = LibStub('AceAddon-3.0'):GetAddon('Libs-FarmAssistant')

-- Money snapshot for delta tracking
local moneySnapshot = 0

function LibsFarmAssistant:InitializeMoneyTracker()
	if self.db.tracking.money then
		self:RegisterEvent('PLAYER_MONEY', 'OnMoneyChanged')
	end

	-- Take initial snapshot
	self:SnapshotMoney()
end

---Take a snapshot of current money for delta tracking
function LibsFarmAssistant:SnapshotMoney()
	moneySnapshot = GetMoney()
end

---Handle PLAYER_MONEY event
function LibsFarmAssistant:OnMoneyChanged()
	if not self:IsSessionActive() then
		-- Update snapshot so paused money changes don't count
		moneySnapshot = GetMoney()
		return
	end

	local currentMoney = GetMoney()
	local delta = currentMoney - moneySnapshot

	-- Only track gains, not spending
	if delta > 0 then
		self.session.money = self.session.money + delta
		self:Log(string.format('Money gained: %s', self:FormatMoney(delta)), 'debug')
		self:UpdateDisplay()
	end

	-- Always update snapshot
	moneySnapshot = currentMoney
end
