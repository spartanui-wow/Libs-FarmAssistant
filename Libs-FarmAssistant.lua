---@class LibsFarmAssistant : AceAddon
local ADDON_NAME, LibsFarmAssistant = ...

LibsFarmAssistant = LibStub('AceAddon-3.0'):NewAddon(ADDON_NAME, 'AceEvent-3.0', 'AceTimer-3.0', 'AceConsole-3.0')
_G.LibsFarmAssistant = LibsFarmAssistant

LibsFarmAssistant.version = '1.0.0'
LibsFarmAssistant.addonName = "Lib's Farm Assistant"

function LibsFarmAssistant:OnInitialize()
	-- Initialize logger
	if LibAT and LibAT.Logger then
		self.logger = LibAT.Logger.RegisterAddon('LibsFarmAssistant')
	end

	-- Database is initialized in Core/Database.lua
	self:InitializeDatabase()

	-- Register slash commands
	self:RegisterChatCommand('libsfa', 'SlashCommand')
	self:RegisterChatCommand('farmassist', 'SlashCommand')
end

function LibsFarmAssistant:OnEnable()
	-- Initialize subsystems
	self:InitializeSession()
	self:InitializeLootTracker()
	self:InitializeMoneyTracker()
	self:InitializeCurrencyTracker()
	self:InitializeReputationTracker()
	self:InitializeDataBroker()
	self:InitializeMinimapButton()
	self:InitializeOptions()

	-- Update display every 60 seconds for rate calculations
	self:ScheduleRepeatingTimer('UpdateDisplay', 60)

	self:Log("Lib's Farm Assistant loaded", 'info')
end

function LibsFarmAssistant:OnDisable()
	self:UnregisterAllEvents()
	self:CancelAllTimers()
end

function LibsFarmAssistant:SlashCommand(input)
	input = input and input:trim():lower() or ''

	if input == '' or input == 'config' or input == 'options' then
		self:OpenOptions()
	elseif input == 'reset' then
		self:ResetSession()
		self:Print('Session reset')
	elseif input == 'pause' or input == 'toggle' then
		self:ToggleSession()
	elseif input == 'summary' then
		self:PrintSummary()
	else
		self:Print('Commands: /farmassist [config|reset|pause|summary]')
	end
end

-- Logging helper
function LibsFarmAssistant:Log(message, level)
	level = level or 'info'
	if self.logger and self.logger[level] then
		self.logger[level](message)
	end
end
