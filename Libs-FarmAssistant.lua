---@class LibsFarmAssistant : AceAddon, AceEvent-3.0, AceTimer-3.0, AceConsole-3.0
local ADDON_NAME, LibsFarmAssistant = ...

LibsFarmAssistant = LibStub('AceAddon-3.0'):NewAddon(ADDON_NAME, 'AceEvent-3.0', 'AceTimer-3.0', 'AceConsole-3.0')
_G.LibsFarmAssistant = LibsFarmAssistant

LibsFarmAssistant:SetDefaultModuleLibraries('AceEvent-3.0', 'AceTimer-3.0')

LibsFarmAssistant.version = '2.0.0'
LibsFarmAssistant.addonName = "Lib's Farm Assistant"
LibsFarmAssistant.icon = 'Interface/Addons/Libs-FarmAssistant/Logo-Icon'

-- Screens refresh from one throttled message instead of on every loot, kill and coin.
local UPDATE_THROTTLE = 0.25

function LibsFarmAssistant:OnInitialize()
	if LibAT and LibAT.Logger then
		self.logger = LibAT.Logger.RegisterAddon('LibsFarmAssistant')
	end

	-- Before the Database module creates the saved settings, so the setup window can tell a new
	-- install from an existing one
	if self.RegisterSetup then
		self:RegisterSetup()
	end

	self:RegisterChatCommand('farm', 'SlashCommand')
	self:RegisterChatCommand('libsfa', 'SlashCommand')
	self:RegisterChatCommand('farmassist', 'SlashCommand')
end

function LibsFarmAssistant:OnEnable()
	if AddonCompartmentFrame and AddonCompartmentFrame.RegisterAddon then
		AddonCompartmentFrame:RegisterAddon({
			text = self.addonName,
			icon = self.icon,
			registerForAnyClick = true,
			notCheckable = true,
			func = function(_, _, _, _, mouseButton)
				if mouseButton == 'RightButton' then
					self:OpenOptions()
				else
					self:ToggleWindow()
				end
			end,
			funcOnEnter = function(button)
				self.BrokerTooltip:Show(button or AddonCompartmentFrame, self.BrokerTooltip.HINTS.compartment)
			end,
		})
	end

	self:Log("Lib's Farm Assistant loaded", 'info')
end

function LibsFarmAssistant:OnDisable()
	self:UnregisterAllEvents()
	self:CancelAllTimers()
end

local HELP = {
	'/farm - open the window',
	'/farm tracker - show or hide the compact tracker',
	'/farm pause - pause or resume tracking',
	'/farm new - start a new session',
	'/farm hunt <item link or ID> - start hunting an item',
	'/farm summary - print this session to chat',
	'/farm options - open settings',
}

function LibsFarmAssistant:SlashCommand(input)
	input = input and strtrim(input) or ''
	local command, rest = input:match('^(%S*)%s*(.-)$')
	command = (command or ''):lower()

	if command == '' or command == 'show' or command == 'window' or command == 'popup' or command == 'dashboard' then
		self:ToggleWindow()
	elseif command == 'options' or command == 'config' then
		self:OpenOptions()
	elseif command == 'tracker' then
		self:ToggleTracker()
	elseif command == 'pause' or command == 'toggle' or command == 'resume' then
		self:ToggleSession()
	elseif command == 'new' or command == 'reset' then
		self:ResetSession()
	elseif command == 'summary' then
		self:PrintSummary()
	elseif command == 'hunt' then
		local itemID = self.Compat.ItemIDFromLink(rest) or tonumber(rest)
		if not itemID then
			self:Print('Usage: /farm hunt [item link or ID]')
			return
		end
		local _, added = self.Hunts:Add(itemID)
		self:Print(added and 'Hunt started. Attempts count from now.' or 'Already hunting that item.')
	else
		for _, line in ipairs(HELP) do
			self:Print(line)
		end
	end
end

function LibsFarmAssistant:Log(message, level)
	level = level or 'info'
	if self.logger and self.logger[level] then
		self.logger[level](message)
	end
end

---Asks every screen to redraw, at most four times a second.
function LibsFarmAssistant:UpdateDisplay()
	if self.updatePending then
		return
	end
	self.updatePending = true
	C_Timer.After(UPDATE_THROTTLE, function()
		self.updatePending = false
		if self.CheckSessionNotification then
			self:CheckSessionNotification()
		end
		if self.CheckGoalCompletion then
			self:CheckGoalCompletion()
		end
		self:SendMessage('LIBSFA_UPDATE')
	end)
end

function LibsFarmAssistant:OpenOptions()
	if self.Options then
		self.Options:OpenOptions()
	end
end

function LibsFarmAssistant:ToggleWindow(page)
	if self.Window then
		self.Window:Toggle(page)
	end
end

function LibsFarmAssistant:ToggleTracker()
	if self.Tracker then
		self.Tracker:Toggle()
	end
end
