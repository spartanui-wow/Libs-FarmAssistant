local root = arg[0]:match('^(.*)[/\\]Tests[/\\]') or '.'
local H = dofile(root .. '/Tests/harness.lua')
H.root = root

local coreOnly = arg[1] == 'core'

-- Items used by the scenarios
H.state.items[14047] = { name = 'Runecloth', quality = 1, sellPrice = 400 }
H.state.items[21383] = { name = 'Winterfall Spirit Beads', quality = 1, sellPrice = 550 }
H.state.items[8170] = { name = 'Rugged Leather', quality = 1, sellPrice = 375 }
H.state.items[14344] = { name = 'Large Brilliant Shard', quality = 3, sellPrice = 0, bindType = 0 }
H.state.items[16254] = { name = 'Formula: Enchant Weapon - Lifestealing', quality = 3, sellPrice = 5000, bindType = 1 }
H.state.items[4306] = { name = 'Broken Tooth', quality = 0, sellPrice = 12 }
H.state.items[13888] = { name = 'Darkclaw Lobster', quality = 1, sellPrice = 30 }
H.state.factions[576] = { name = 'Timbermaw Hold', reaction = 6, bottom = 9000, top = 21000, value = 14000 }
H.state.factions[577] = { name = 'Everlook', reaction = 5, bottom = 3000, top = 9000, value = 4000 }
H.state.currencies[1166] = { name = 'Timewarped Badge', quantity = 100 }

local A = H.boot({ coreOnly = coreOnly })
local Ledger = A.Ledger
local Format = A.Format
local Compat = A.Compat

H.test('boot', function()
	H.ok(A.char.session, 'session exists')
	H.eq(A:IsSessionActive(), true, 'session active')
	H.eq(A.char.session.version, 2, 'session version')
end)

H.test('format patterns', function()
	local p = Compat.FormatToPattern(LOOT_ITEM_SELF_MULTIPLE)
	local link, n = ('You receive loot: ' .. H.Link(14047) .. 'x5.'):match(p)
	H.eq(link, H.Link(14047), 'multiple link')
	H.eq(n, '5', 'multiple count')
	local rp = Compat.FormatToPattern(FACTION_STANDING_INCREASED_BONUS)
	local name, amount, bonus = ('Reputation with Timbermaw Hold increased by 20. (+2.5 Recruit A Friend bonus)'):match(rp)
	H.eq(name, 'Timbermaw Hold', 'rep name')
	H.eq(amount, '20', 'rep amount')
	H.eq(bonus, '2.5', 'rep bonus')
	H.eq(Compat.FormatToPattern('%1$s gains %2$d'), '^(.+) gains ([%d,%.]+)', 'positional args')
end)

H.test('number formats', function()
	H.eq(Format.Money(1258799), '125g 87s', 'money')
	H.eq(Format.Money(1258799, false, true), '125g 87s 99c', 'money full')
	H.eq(Format.Money(4550), '45s 50c', 'money silver')
	H.eq(Format.Odds(1 / 14), '1 in 14', 'odds')
	H.eq(Format.Odds(0.72), '72%', 'odds percent')
	H.eq(Format.Odds(1 / 6.4), '1 in 6.4', 'odds decimal')
	H.eq(Format.Clock(6138), '1:42:18', 'clock')
	H.eq(Format.Duration(6138), '1h 42m', 'duration')
	H.eq(Format.Rate(0.6), '0.6', 'slow rate')
end)

H.test('kill and loot a creature', function()
	local guid = H.kill(7440, 'Winterfall Den Watcher', 1)
	local session = Ledger:Session()
	H.eq(session.kills, 1, 'kill counted from PARTY_KILL')
	H.loot({
		{ itemID = 14047, quantity = 2, guid = guid },
		{ itemID = 21383, quantity = 1, guid = guid },
		{ type = 2, quantity = 312, guid = guid },
	})
	H.eq(session.items[14047], 2, 'runecloth recorded once despite chat line')
	H.eq(session.items[21383], 1, 'beads recorded')
	H.eq(session.kills, 1, 'looting the corpse does not add a kill')
	local stats = session.sources['c:7440']
	H.ok(stats, 'source stats exist')
	H.eq(stats.kills, 1, 'source kills')
	H.eq(stats.loots, 1, 'source loots')
	H.eq(stats.drops[14047], 1, 'drop event counted once, not per stack')
	H.eq(stats.items[14047], 2, 'quantity from source')
	H.eq(stats.money, 312, 'coin from source')
	H.eq(Ledger.Money(session, 'loot'), 312, 'looted coin category')
	H.eq(A.global.sourceMeta['c:7440'].n, 'Winterfall Den Watcher', 'source name remembered')

	-- Skinning the same corpse opens a second loot window on the same GUID.
	H.loot({ { itemID = 8170, quantity = 1, guid = guid } })
	H.eq(session.kills, 1, 'skinning does not add a kill')
	H.eq(stats.loots, 1, 'skinning does not add a loot')
	H.eq(session.items[8170], 1, 'leather recorded')
end)

H.test('group kill counted from the corpse', function()
	local guid = H.CreatureGUID(7442, 2)
	H.state.units.target = { guid = guid, name = 'Winterfall Shaman', dead = true }
	H.fire('PLAYER_TARGET_CHANGED')
	local before = Ledger:Session().kills
	H.loot({ { itemID = 21383, quantity = 1, guid = guid } })
	H.eq(Ledger:Session().kills, before + 1, 'looting an uncounted corpse counts the kill')
	H.fire('PARTY_KILL', 'Player-1-2', guid)
	H.eq(Ledger:Session().kills, before + 1, 'late kill event is not counted twice')
end)

H.test('area loot split across corpses', function()
	local g1 = H.kill(7440, 'Winterfall Den Watcher', 3)
	local g2 = H.kill(7442, 'Winterfall Shaman', 4)
	local s = Ledger:Session()
	local before = s.items[14047] or 0
	H.loot({ { itemID = 14047, quantity = 5, sources = { { g1, 2 }, { g2, 3 } } } })
	H.eq(s.items[14047], before + 5, 'split slot total')
	H.eq(s.sources['c:7442'].items[14047], 3, 'second corpse share')
end)

H.test('items left on the corpse do not count', function()
	local guid = H.kill(7440, 'Winterfall Den Watcher', 5)
	local s = Ledger:Session()
	local before = s.items[4306] or 0
	H.loot({ { itemID = 4306, quantity = 1, guid = guid } }, { leave = { [1] = true } })
	H.eq(s.items[4306] or 0, before, 'untaken slot ignored')
end)

H.test('quality filter', function()
	A.db.tracking.qualities[0] = false
	local guid = H.kill(7440, 'Winterfall Den Watcher', 6)
	local s = Ledger:Session()
	H.loot({ { itemID = 4306, quantity = 1, guid = guid } })
	H.eq(s.items[4306], nil, 'poor item filtered')
	A.db.tracking.qualities[0] = true
end)

H.test('vendor sale and spending', function()
	H.fire('MERCHANT_SHOW')
	H.state.money = H.state.money + 5000
	H.fire('PLAYER_MONEY')
	H.state.money = H.state.money - 2000
	H.fire('PLAYER_MONEY')
	H.fire('MERCHANT_CLOSED')
	H.advance(5)
	local s = Ledger:Session()
	H.eq(Ledger.Money(s, 'vendor'), 5000, 'vendor category')
	H.eq(s.spent, 2000, 'spending tracked')
end)

H.test('time and rates', function()
	H.advance(3600)
	local s = Ledger:Session()
	H.ok(s.time >= 3600 and s.time <= 3700, 'session time about an hour: ' .. s.time)
	local rate = Ledger.PerHour(s.kills, s)
	H.ok(rate and rate > 0, 'kills per hour')
	H.ok(Ledger:Day().time >= 3600, 'day bucket time')
	H.ok(Ledger:Lifetime().time >= 3600, 'lifetime time')
end)

H.test('hunt counts attempts and learns sources', function()
	local hunt = A.Hunts:Add(16254)
	H.ok(hunt, 'hunt added')
	H.eq(A.Hunts:HasSources(hunt), false, 'no sources yet')
	for i = 1, 4 do
		H.kill(7440, 'Winterfall Den Watcher', 100 + i)
	end
	H.eq(hunt.attempts, 4, 'counts every kill before any source is known')
	local guid = H.kill(1839, 'Scarlet Spellbinder', 200)
	H.eq(hunt.attempts, 5, 'fifth attempt')
	H.loot({ { itemID = 16254, quantity = 1, guid = guid } })
	H.eq(#hunt.found, 1, 'drop recorded')
	H.eq(hunt.found[1].attempts, 5, 'attempts at drop')
	H.eq(hunt.attempts, 0, 'count restarts')
	H.eq(hunt.sources['c:1839'], true, 'source learned')
	H.kill(7440, 'Winterfall Den Watcher', 300)
	H.eq(hunt.attempts, 0, 'other mobs no longer count')
	H.kill(1839, 'Scarlet Spellbinder', 301)
	H.eq(hunt.attempts, 1, 'the source counts')
	A.Hunts:SetChance(16254, 2)
	local text, byNow = A.Hunts:LuckText(hunt)
	H.ok(text and byNow > 0, 'luck text')
	H.ok(math.abs(A.Hunts.ChanceByNow(0.01, 100) - 0.634) < 0.001, 'chance by now math')
end)

H.test('personal loot from chat goes to the last kill', function()
	H.kill(10184, 'Onyxia', 400)
	H.fire('CHAT_MSG_LOOT', string.format(LOOT_ITEM_SELF, H.Link(14344)), 'Tester')
	local s = Ledger:Session()
	H.eq(s.items[14344], 1, 'chat-only loot recorded')
	H.eq(s.sources['c:10184'].drops[14344], 1, 'attributed to the recent kill')
	H.fire('CHAT_MSG_LOOT', string.format(LOOT_ITEM_CREATED_SELF, H.Link(14344)), 'Tester')
	H.eq(s.items[14344], 1, 'crafted items ignored by default')
	H.fire('CHAT_MSG_LOOT', 'Someone receives loot: ' .. H.Link(14344) .. '.', 'Someone')
	H.eq(s.items[14344], 1, 'other players loot ignored')
end)

H.test('reputation measured by difference', function()
	local f = H.state.factions[576]
	f.value = f.value + 25
	H.fire('FACTION_STANDING_CHANGED', 576, f.value)
	H.eq(Ledger:Session().rep[576], 25, 'gain from standing change')
	f.value = f.value + 20
	H.fire('CHAT_MSG_COMBAT_FACTION_CHANGE', 'Reputation with Timbermaw Hold increased by 20.')
	H.advance(1)
	H.eq(Ledger:Session().rep[576], 45, 'gain from chat hint')
	H.fire('UPDATE_FACTION')
	H.advance(1)
	H.eq(Ledger:Session().rep[576], 45, 'no double count')
	-- A faction the tracker never read: the chat amount is used.
	H.state.factions[999] = { name = 'Hidden Circle', reaction = 4, bottom = 0, top = 3000, value = 50 }
	H.fire('CHAT_MSG_COMBAT_FACTION_CHANGE', 'Reputation with Hidden Circle increased by 50.')
	H.advance(1)
	H.eq(Ledger:Session().rep[999], 50, 'first gain from chat amount')
end)

H.test('experience across a level-up', function()
	H.state.xp = 90000
	H.fire('PLAYER_XP_UPDATE', 'player')
	local before = Ledger:Session().xp
	H.eq(before, 90000, 'xp gained')
	H.state.level = 71
	H.fire('PLAYER_LEVEL_UP', 71)
	H.state.xp = 5000
	H.state.xpMax = 110000
	H.fire('PLAYER_XP_UPDATE', 'player')
	H.eq(Ledger:Session().xp, before + 15000, 'overflow into next level counted')
end)

H.test('currency', function()
	H.state.currencies[1166].quantity = 105
	H.fire('CURRENCY_DISPLAY_UPDATE', 1166, 105, 5)
	H.eq(Ledger:Session().currencies[1166], 5, 'currency change')
	H.fire('CURRENCY_DISPLAY_UPDATE', 1792, 100, 30)
	H.eq(Ledger:Session().honor, 30, 'honor currency goes to honor')
	H.eq(Ledger:Session().currencies[1792], nil, 'honor not listed as currency')
end)

H.test('fishing', function()
	H.loot({ { itemID = 13888, quantity = 1, guid = H.ObjectGUID(35591, 9) } }, { fishing = true })
	local key = 'f:Winterspring'
	local stats = Ledger:Session().sources[key]
	H.ok(stats, 'fishing source')
	H.eq(stats.loots, 1, 'one catch')
	H.eq(stats.items[13888], 1, 'catch recorded')
end)

H.test('item sources ranked', function()
	local list = Ledger.ItemSources(Ledger:Session(), 21383)
	H.ok(#list >= 2, 'two sources for beads')
	H.ok(list[1].rate >= list[2].rate, 'sorted by rate')
end)

H.test('pause stops tracking', function()
	A.SessionManager:SetPaused(true, true)
	local s = Ledger:Session()
	local kills = s.kills
	H.kill(7440, 'Winterfall Den Watcher', 500)
	H.eq(s.kills, kills, 'no kills while paused')
	local t = s.time
	H.advance(600)
	H.eq(s.time, t, 'clock stopped while paused')
	A.SessionManager:SetPaused(false, true)
end)

H.test('afk pauses and resumes', function()
	H.state.afk = true
	H.fire('PLAYER_FLAGS_CHANGED', 'player')
	H.eq(A:IsSessionActive(), false, 'paused when away')
	H.state.afk = false
	H.fire('PLAYER_FLAGS_CHANGED', 'player')
	H.eq(A:IsSessionActive(), true, 'resumed when back')
end)

H.test('goals', function()
	A.db.goals[1] = { type = 'item', targetItemID = 14047, targetValue = 5, active = true }
	local current, target = A.GoalTracker:Progress(A.db.goals[1])
	H.ok(current >= 5 and target == 5, 'item goal progress')
	A:UpdateDisplay()
	H.advance(1)
	local announced = false
	for _, line in ipairs(H.chat) do
		if tostring(line):find('Goal reached') then
			announced = true
		end
	end
	H.ok(announced, 'goal announced')
end)

H.test('new session archives the old one', function()
	local old = Ledger:Session()
	A.SessionManager:NewSession(true)
	H.ok(Ledger:Session() ~= old, 'fresh session')
	local summary = A.char.sessions[1]
	H.ok(summary, 'archived')
	H.ok(summary.kills > 0 and summary.time >= 3600, 'summary has totals')
	H.eq(summary.zone, 'Winterspring', 'summary zone')
	H.ok(Ledger:Lifetime().kills >= summary.kills, 'lifetime keeps everything')
end)

H.test('week sums days', function()
	local days = A.char.days
	local today = Ledger.DayKey()
	local yesterday = Ledger.DayKey(time() - 86400)
	days[yesterday] = Ledger.NewBucket()
	days[yesterday].kills = 7
	days[yesterday].time = 100
	Ledger.version = Ledger.version + 1
	local week = Ledger:Window('week')
	H.eq(week.kills, (days[today].kills or 0) + 7, 'week includes yesterday and today')
	days['2020-01-01'] = Ledger.NewBucket()
	Ledger:Prune()
	H.eq(days['2020-01-01'], nil, 'old days pruned')
end)

H.test('long logout starts a fresh session', function()
	local session = Ledger:Session()
	H.kill(7440, 'Winterfall Den Watcher', 600)
	session.lastSeen = time() - 7200
	A.SessionManager:OnEnable()
	H.ok(Ledger:Session() ~= session, 'new session after two hours away')
end)

H.test('secret away flag is ignored', function()
	H.state.afk = H.SECRET
	H.fire('PLAYER_FLAGS_CHANGED', 'player')
	H.eq(A:IsSessionActive(), true, 'no pause and no error on a secret flag')
	H.state.afk = false
end)

H.test('group loot rolls count only for the winner', function()
	H.inGroup = true
	H.lootMethod = Enum.LootMethod.Group
	local s = Ledger:Session()
	local before = s.items[14344] or 0
	local guid = H.kill(7440, 'Winterfall Den Watcher', 700)
	H.loot({ { itemID = 14344, quantity = 1, guid = guid } })
	H.eq(s.items[14344], before + 1, 'won roll counted once (from chat)')
	guid = H.kill(7440, 'Winterfall Den Watcher', 701)
	H.loot({ { itemID = 14344, quantity = 1, guid = guid, noChat = true } })
	H.eq(s.items[14344], before + 1, 'lost roll not counted')
	H.inGroup = false
	H.lootMethod = Enum.LootMethod.Freeforall
end)

H.test('pickpocket and gathering get their own sources', function()
	local s = Ledger:Session()
	local kills = s.kills
	local guid = H.CreatureGUID(7440, 800)
	H.fire('UNIT_SPELLCAST_SENT', 'player', 'Winterfall Den Watcher', 'Cast-1', 921)
	H.loot({ { itemID = 14047, quantity = 1, guid = guid } })
	H.eq(s.kills, kills, 'pickpocketing a live mob is not a kill')
	H.ok(s.sources['p:7440'] and s.sources['p:7440'].items[14047] == 1, 'pickpocket source')
	H.advance(10)
	H.kill(7440, 'Winterfall Den Watcher', 801)
	guid = H.CreatureGUID(7440, 801)
	H.loot({ { itemID = 14047, quantity = 1, guid = guid } })
	local creatureLeather = s.sources['c:7440'].items[8170] or 0
	H.loot({ { itemID = 8170, quantity = 2, guid = guid } })
	H.eq(s.sources['c:7440'].items[8170] or 0, creatureLeather, 'skinning is not a creature drop')
	H.ok((s.sources['g:7440'].items[8170] or 0) >= 2, 'skinning goes to the gathering source')
	H.eq(A.global.sourceMeta['g:7440'].n, 'Winterfall Den Watcher (gathered)', 'gathering source name')
end)

H.test('hunts: one find per drop, rewards do not end a count', function()
	local hunt = A.Hunts:Add(13888)
	local found = #hunt.found
	local g1 = H.kill(7440, 'Winterfall Den Watcher', 900)
	local g2 = H.kill(7442, 'Winterfall Shaman', 901)
	H.loot({ { itemID = 13888, quantity = 2, sources = { { g1, 1 }, { g2, 1 } } } })
	H.eq(#hunt.found, found + 1, 'split loot is one find')
	H.kill(7440, 'Winterfall Den Watcher', 902)
	local attempts = hunt.attempts
	H.fire('CHAT_MSG_LOOT', string.format(LOOT_ITEM_PUSHED_SELF, H.Link(13888)), 'Tester')
	H.eq(hunt.attempts, attempts, 'a reward does not reset the count')
	H.eq(#hunt.found, found + 1, 'a reward is not a find')
end)

H.test('a boss kill is one attempt', function()
	local hunt = A.Hunts:Add(99999)
	hunt.mode = 'any'
	local before = hunt.attempts
	H.kill(10184, 'Onyxia', 950)
	H.fire('ENCOUNTER_END', 1084, 'Onyxia', 1, 40, 1)
	H.fire('BOSS_KILL', 1084, 'Onyxia')
	H.eq(hunt.attempts, before + 1, 'creature and encounter count once')
	A.Hunts:AddSource(99999, 'e:1084')
	hunt.mode = 'sources'
	H.advance(30)
	H.kill(10184, 'Onyxia', 951)
	H.fire('ENCOUNTER_END', 1084, 'Onyxia', 1, 40, 1)
	H.eq(hunt.attempts, before + 2, 'encounter source counts')
	A.Hunts:Remove(99999)
end)

H.test('loot hidden during lockdown is read later', function()
	local s = Ledger:Session()
	local before = s.items[14047] or 0
	H.chatLines[77] = string.format(LOOT_ITEM_SELF_MULTIPLE, H.Link(14047), 3)
	H.fire('CHAT_MSG_LOOT', H.SECRET, 'Tester', '', '', '', '', 0, 0, '', 0, 77)
	H.eq(s.items[14047] or 0, before, 'not counted while hidden')
	H.fire('PLAYER_REGEN_ENABLED')
	H.eq(s.items[14047], before + 3, 'counted after lockdown')
end)

H.test('purchases are not rewards', function()
	local s = Ledger:Session()
	local before = s.items[4306] or 0
	H.fire('MERCHANT_SHOW')
	H.fire('CHAT_MSG_LOOT', string.format(LOOT_ITEM_PUSHED_SELF, H.Link(4306)), 'Tester')
	H.fire('MERCHANT_CLOSED')
	H.eq(s.items[4306] or 0, before, 'bought item not counted')
	H.advance(5)
end)

if not coreOnly then
	H.test('ui smoke', function()
		A:ToggleWindow()
		for _, page in ipairs({ 'overview', 'loot', 'hunts', 'sources', 'progress', 'history' }) do
			A.Window:ShowPage(page)
			for _, range in ipairs(Ledger.WINDOWS) do
				A.Window:SetRange(range)
			end
		end
		A:ToggleTracker()
		A:SendMessage('LIBSFA_UPDATE')
		A:BuildTooltip(GameTooltip)
		for _, format in ipairs({ 'value', 'gold', 'items', 'kills', 'hunt' }) do
			A.db.display.format = format
			A.DataBroker:UpdateDisplay()
			H.ok(A.dataObject.text ~= nil, 'broker text ' .. format)
		end
		H.advance(2)
	end)

	H.test('ui detail panes', function()
		A.Window:SetRange('all')
		local loot = A.Pages.loot
		loot.selected = 21383
		A.Window:ShowPage('loot')
		H.ok(loot.detailName.text == 'Winterfall Spirit Beads', 'loot detail shows the item')
		H.ok(loot.note.text and loot.note.text:find('as often') , 'loot detail compares sources: ' .. tostring(loot.note.text))
		local hunts = A.Pages.hunts
		hunts.selected = 16254
		A.Window:ShowPage('hunts')
		H.eq(hunts.attempts.text, '1', 'hunt attempts shown')
		H.ok(hunts.luckText.text and hunts.luckText.text:find('players'), 'luck text shown')
		hunts.chanceBox.onSubmit('0.5')
		H.eq(A.Hunts:Get(16254).chance, 0.005, 'chance box sets chance')
		hunts.addBox.onSubmit(H.Link(14344))
		H.ok(A.Hunts:Get(14344), 'shift-clicked link starts a hunt')
		local sources = A.Pages.sources
		sources.selected = 'c:7440'
		A.Window:ShowPage('sources')
		H.eq(sources.name.text, 'Winterfall Den Watcher', 'source detail name')
		A.Window:ShowPage('progress')
		A.Window:ShowPage('history')
		H.ok(#A.Pages.history.sessions.rows >= 1, 'history lists sessions')
		GameTooltip.lines = {}
		function GameTooltip:AddDoubleLine(l, r)
			self.lines[#self.lines + 1] = tostring(l) .. ' | ' .. tostring(r)
		end
		A.GameTooltips:AddItemLines(GameTooltip, 21383)
		H.ok(#GameTooltip.lines >= 2, 'item tooltip lines: ' .. table.concat(GameTooltip.lines, '; '))
		GameTooltip.lines = {}
		A.GameTooltips:AddUnitLines(GameTooltip, H.CreatureGUID(7440, 999))
		H.ok(#GameTooltip.lines >= 2, 'unit tooltip lines: ' .. table.concat(GameTooltip.lines, '; '))
		local lines = A.Tracker:Lines()
		H.ok(#lines >= 1, 'tracker has lines')
		A:SlashCommand('hunt ' .. H.Link(4306))
		H.ok(A.Hunts:Get(4306), 'slash hunt')
	end)
end

io.write(string.format('%d passed, %d failed\n', H.passed, H.failed))
if H.failed > 0 then
	os.exit(1)
end
