---@class LibsFarmAssistant
local LibsFarmAssistant = LibStub('AceAddon-3.0'):GetAddon('Libs-FarmAssistant')

---@class LibsFarmAssistant.MoneyTracker : AceModule, AceEvent-3.0, AceTimer-3.0
local MoneyTracker = LibsFarmAssistant:NewModule('MoneyTracker')
LibsFarmAssistant.MoneyTracker = MoneyTracker

function MoneyTracker:OnEnable()
	self.moneySnapshot = 0

	if LibsFarmAssistant.db.tracking.money then
		self:RegisterEvent('PLAYER_MONEY', 'OnMoneyChanged')
	end

	-- Take initial snapshot
	self:SnapshotMoney()
end

function MoneyTracker:OnDisable()
	self:UnregisterAllEvents()
end

---Take a snapshot of current money for delta tracking
function MoneyTracker:SnapshotMoney()
	self.moneySnapshot = GetMoney()
end

---Handle PLAYER_MONEY event
function MoneyTracker:OnMoneyChanged()
	if not LibsFarmAssistant:IsSessionActive() then
		self.moneySnapshot = GetMoney()
		return
	end

	local currentMoney = GetMoney()
	local delta = currentMoney - self.moneySnapshot

	if delta > 0 then
		LibsFarmAssistant.session.money = LibsFarmAssistant.session.money + delta
		LibsFarmAssistant:Log(string.format('Money gained: %s', LibsFarmAssistant:FormatMoney(delta)), 'debug')
		LibsFarmAssistant:UpdateDisplay()

		if LibsFarmAssistant.db.chatEcho then
			LibsFarmAssistant:Print(string.format('[Farm] +%s', LibsFarmAssistant:FormatMoney(delta)))
		end
	end

	self.moneySnapshot = currentMoney
end

-- Bridge method on main addon
function LibsFarmAssistant:SnapshotMoney()
	if self.MoneyTracker then
		self.MoneyTracker:SnapshotMoney()
	end
end
