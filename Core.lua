local addonName, addon = ...

WeirdLoot = WeirdLoot or {}
addon = WeirdLoot

addon.name = addonName or "WeirdLoot"
addon.prefix = "WeirdLoot"
addon.version = "0.1.0"
addon.callbacks = {}
addon.events = CreateFrame("Frame")

SLASH_WEIRDLOOT1 = "/weirdloot"
SLASH_WEIRDLOOT2 = "/wl"
SlashCmdList.WEIRDLOOT = function(msg)
    if WeirdLoot and WeirdLoot.HandleSlashCommand then
        WeirdLoot:HandleSlashCommand(msg)
    end
end

local function ensureDefaults(target, defaults)
    if type(target) ~= "table" then
        target = {}
    end

    for key, value in pairs(defaults) do
        if type(value) == "table" then
            target[key] = ensureDefaults(target[key], value)
        elseif target[key] == nil then
            target[key] = value
        end
    end

    return target
end

local defaultRosterImportText = table.concat({
    "volcker, warlock affliction, main",
    "volckur, mage arcane, designatedAlt",
}, "\n")

local defaultLootPriorityText = table.concat({
    "gemmed wand of the nerubians, warlock affliction > mage arcane > rest",
    "strong-handed ring, mage arcane > warlock affliction > rest",
}, "\n")

local defaultNamedItemsText = table.concat({
    "gemmed wand of the nerubians, volcker > volckur > rest",
    "strong-handed ring, volckur > volcker > rest",
}, "\n")

local function onEvent(self, event, ...)
    if addon[event] then
        addon[event](addon, ...)
    end
end

function addon:RegisterCallback(eventName, handler)
    if type(handler) ~= "function" then
        return
    end

    self.callbacks[eventName] = self.callbacks[eventName] or {}
    table.insert(self.callbacks[eventName], handler)
end

function addon:TriggerCallback(eventName, ...)
    local handlers = self.callbacks[eventName]
    if not handlers then
        return
    end

    for _, handler in ipairs(handlers) do
        handler(...)
    end
end

function addon:Print(message)
    DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffWeirdLoot|r: " .. tostring(message))
end

function addon:RefreshAll()
    self:RefreshRoster()
    self:RefreshLootAuthority()
    self:RefreshSessionItems()
    self:TriggerCallback("STATE_UPDATED")
end

function addon:PLAYER_LOGIN()
    WeirdLootDB = ensureDefaults(WeirdLootDB, {
        config = {
            rosterImportText = defaultRosterImportText,
            lootPriorityText = defaultLootPriorityText,
            namedItemsText = defaultNamedItemsText,
            roster = {},
            lootRules = {},
            namedRules = {},
            revision = 0,
        },
        ui = {
            selectedTab = "loot",
            frame = {
                x = 0,
                y = 0,
            },
        },
    })

    WeirdLootSessionDB = ensureDefaults(WeirdLootSessionDB, {
        activeSession = nil,
        history = {},
    })

    self.db = WeirdLootDB
    self.sessionDb = WeirdLootSessionDB

    local guidSeed = tonumber(string.match(UnitGUID("player") or "0", "(%d+)$")) or 0
    if type(randomseed) == "function" then
        randomseed(time() + guidSeed)
    elseif math and type(math.randomseed) == "function" then
        math.randomseed(time() + guidSeed)
    end

    self:InitializeConfig()
    self:InitializeRoster()
    self:InitializeSession()
    self:InitializeComm()
    self:InitializeResolver()
    self:InitializeUI()

    self.events:RegisterEvent("RAID_ROSTER_UPDATE")
    self.events:RegisterEvent("PARTY_MEMBERS_CHANGED")
    self.events:RegisterEvent("PARTY_LOOT_METHOD_CHANGED")
    self.events:RegisterEvent("CHAT_MSG_ADDON")
    self.events:RegisterEvent("PLAYER_ENTERING_WORLD")
    self.events:RegisterEvent("BAG_UPDATE")
    self.events:RegisterEvent("PLAYER_REGEN_ENABLED")

    self:RefreshAll()
    self:Print("Loaded. Use /weirdloot to open the window.")
end

function addon:PLAYER_ENTERING_WORLD()
    self:RefreshAll()
end

function addon:RAID_ROSTER_UPDATE()
    self:RefreshRoster()
    self:RefreshLootAuthority()
    self:TriggerCallback("ROSTER_UPDATED")
end

function addon:PARTY_MEMBERS_CHANGED()
    self:RefreshRoster()
    self:RefreshLootAuthority()
    self:TriggerCallback("ROSTER_UPDATED")
end

function addon:PARTY_LOOT_METHOD_CHANGED()
    self:RefreshLootAuthority()
    self:TriggerCallback("AUTHORITY_UPDATED")
end

function addon:BAG_UPDATE()
    self:OnBagUpdate()
end

function addon:PLAYER_REGEN_ENABLED()
    self:TriggerCallback("STATE_UPDATED")
end

function addon:HandleSlashCommand(msg)
    local command = string.lower(string.trim(msg or ""))
    if command == "start" then
        self:StartLootSession()
    elseif command == "scan" then
        self:RefreshSessionItems(true)
    else
        self:ToggleMainFrame()
    end
end

addon.events:SetScript("OnEvent", onEvent)
addon.events:RegisterEvent("PLAYER_LOGIN")
