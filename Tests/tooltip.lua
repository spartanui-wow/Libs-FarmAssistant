-- The broker tooltip, drawn into the harness's LibQTip-2.0 stand-in. Run from Tests/run.lua.
return function(H, A)
	local Tip = A.BrokerTooltip
	local Ledger = A.Ledger

	local function Click(row, column, button)
		row:GetCell(column or 1):Fire('OnMouseUp', button or 'LeftButton')
	end

	-- Top loot lines are the only ones whose count reads "x3"
	local function LootLines(tip)
		local n = 0
		for _, row in ipairs(tip:Lines()) do
			local cell = row.cells[2]
			if cell and cell.text and cell.text:match('^x%d') then
				n = n + 1
			end
		end
		return n
	end

	H.test('broker tooltip', function()
		if not A:IsSessionActive() then
			A:ToggleSession()
		end
		A.db.tracking.mode = 'all'
		local guid = H.kill(7440, 'Winterfall Den Watcher', 7001)
		H.loot({ { itemID = 14344, quantity = 1, guid = guid }, { itemID = 14047, quantity = 3, guid = guid } })
		H.advance(120)

		local anchor = H.NewFrame('Button')
		H.ok(A.dataObject.OnTooltipShow == nil, 'broker draws its own tooltip')
		A.dataObject.OnEnter(anchor)
		local tip = Tip.qtip
		H.ok(tip and tip.shown, 'tooltip shown at the broker')
		H.eq(tip.anchor, anchor, 'anchored to the broker')
		H.eq(tip.autoHideFrame, anchor, 'stays open while the mouse is on the broker')
		H.eq(tip.columns, 3, 'three columns')
		H.ok(tip.maxHeight, 'height capped so long lists scroll')
		H.ok(tip:Find('Farm Assistant') and tip:Find('Farming'), 'title with state')
		H.ok(tip:Find('Total value'), 'session summary')
		H.ok(tip:Find('Click: window'), 'broker click hints')

		-- Item lines: hover shows the item beside the tooltip, shift-click links it
		local shard = tip:Find('Large Brilliant Shard')
		H.ok(shard, 'looted item listed')
		shard:GetCell(1):Fire('OnEnter')
		H.eq(GameTooltip:GetOwner(), tip, 'item shown beside the tooltip')
		shard:GetCell(1):Fire('OnLeave')
		local linked
		IsModifiedClick = function()
			return true
		end
		HandleModifiedItemClick = function(link)
			linked = link
		end
		Click(shard, 2)
		IsModifiedClick, HandleModifiedItemClick = nil, nil
		H.ok(linked and linked:find('Large Brilliant Shard', 1, true), 'shift-click links the item')
		H.ok(Tip:IsShown(), 'linking keeps the tooltip open')

		-- Sections fold and remember it
		Click(tip:Find('Top loot'))
		H.eq(A.db.display.collapsed.loot, true, 'fold saved')
		tip = Tip.qtip
		H.ok(tip:Find('Top loot'), 'folded header stays')
		H.eq(LootLines(tip), 0, 'folded section hides its lines')
		Click(tip:Find('Top loot'), 3)
		H.eq(A.db.display.collapsed.loot, nil, 'unfolding clears the saved fold')
		tip = Tip.qtip
		H.ok(LootLines(tip) > 0, 'lines back after unfolding')

		-- Drop rates use loots per try from the best source
		local found
		for _, row in ipairs(Tip.DropRows(Ledger:Session())) do
			if row.id == 14344 then
				found = row
			end
		end
		H.ok(found and found.key == 'c:7440', 'drop rate tied to its source')
		H.eq(Tip.DropRows(Ledger:Session())[1].quality >= 2, true, 'only uncommon or better, or hunted')
		H.ok(tip:Find('Drop rates'), 'drop rates section')

		-- Reputation, currency, honor and experience
		Ledger:AddRep(576, 250)
		Ledger:AddCurrency(1166, 5)
		Ledger:AddHonor(12)
		Ledger:AddXP(500)
		Tip:Redraw()
		tip = Tip.qtip
		H.ok(tip:Find('Reputation') and tip:Find('Timbermaw Hold'), 'reputation section')
		H.ok(tip:Find('Currency') and tip:Find('Timewarped Badge') and tip:Find(HONOR or 'Honor', 1), 'currency and honor')
		H.ok(tip:Find('Experience') and tip:Find('Gained'), 'experience section')
		tip:Find('Timewarped Badge'):GetCell(1):Fire('OnEnter')
		H.eq(GameTooltip:GetOwner(), tip, 'currency shown beside the tooltip')
		Click(tip:Find('Timbermaw Hold'))
		H.eq(A.Window.page, 'progress', 'reputation line opens Progress')
		A.dataObject.OnEnter(anchor)
		tip = Tip.qtip

		-- Clicking a line opens the window on that page and selects it
		Click(tip:Find('Large Brilliant Shard'))
		H.eq(A.Window.page, 'loot', 'item line opens Loot')
		H.eq(A.Pages.loot.selected, 14344, 'item selected')
		H.ok(not Tip:IsShown(), 'tooltip closes when the window opens')

		A.dataObject.OnEnter(anchor)
		Click(Tip.qtip:Find('Winterfall Den Watcher', 1))
		H.eq(A.Window.page, 'sources', 'source line opens Sources')
		H.eq(A.Pages.sources.selected, 'c:7440', 'source selected')

		A.dataObject.OnEnter(anchor)
		Click(Tip.qtip:Find('Total value'), 3)
		H.eq(A.Window.page, 'overview', 'summary opens Overview')

		A.dataObject.OnEnter(anchor)
		Click(Tip.qtip:Find('Kills'), 1, 'RightButton')
		H.eq(A.Window.page, 'overview', 'only left-click opens a page')

		-- A line missing from the window's time range switches it to this session
		A.Window:SetRange('today')
		A.char.days[Ledger.DayKey()].sources['c:7440'] = nil
		Click(Tip.qtip:Find('Winterfall Den Watcher', 1))
		H.eq(A.Window.range, 'session', 'range follows the tooltip')

		-- Pause, resume and new session from the tooltip
		A.dataObject.OnEnter(anchor)
		Click(Tip.qtip:Find('Pause tracking'))
		H.eq(A:IsSessionActive(), false, 'paused from the tooltip')
		H.ok(Tip.qtip:Find('Resume tracking') and Tip.qtip:Find('Paused'), 'redrawn as paused')
		Click(Tip.qtip:Find('Resume tracking'))
		H.eq(A:IsSessionActive(), true, 'resumed from the tooltip')
		H.lastPopup = nil
		Click(Tip.qtip:Find('New session'), 3)
		H.eq(H.lastPopup, 'LIBSFA_NEW_SESSION', 'new session asks first')

		-- New data redraws, but never under the mouse
		H.mouseOverQTip = true
		local before = H.released
		A.DataBroker:UpdateDisplay()
		H.eq(H.released, before, 'no redraw while the mouse is on it')
		H.mouseOverQTip = false
		A.DataBroker:UpdateDisplay()
		H.ok(H.released > before, 'redraw on new data')

		H.advance(2)
		H.ok(Tip.clockTimer, 'clock ticks while shown')
		Tip:Hide()
		H.ok(not Tip:IsShown(), 'hidden')
		H.eq(Tip.clockTimer, nil, 'clock stops when hidden')

		-- Empty session
		A:ResetSession()
		A.dataObject.OnEnter(anchor)
		H.ok(Tip.qtip:Find('Nothing farmed yet'), 'empty state')
		H.eq(Tip.qtip:Find('Total value'), nil, 'no summary when empty')
		Tip:Hide()

		-- Menu entry hints
		Tip:Show(anchor, Tip.HINTS.compartment)
		H.ok(Tip.qtip:Find('Right-click: settings'), 'menu entry hints')
		Tip:Hide()

		-- The same content in a plain GameTooltip
		local lines = {}
		local function Add(_, left, right)
			lines[#lines + 1] = tostring(left) .. ' | ' .. tostring(right or '')
		end
		GameTooltip.AddLine, GameTooltip.AddDoubleLine = Add, Add
		A:BuildTooltip(GameTooltip)
		GameTooltip.AddLine, GameTooltip.AddDoubleLine = nil, nil
		H.ok(#lines >= 3 and lines[1]:find('Farm Assistant', 1, true), 'plain tooltip lines: ' .. #lines)
	end)
end
