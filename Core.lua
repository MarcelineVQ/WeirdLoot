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

addon.defaultRosterEntries = {
    { name = "achera", className = "death knight", specName = "frost", status = "designatedalt" },
    { name = "aest", className = "mage", specName = "fire", status = "main" },
    { name = "aldeberron", className = "mage", specName = "arcane", status = "main" },
    { name = "cfg", className = "warlock", specName = "affliction", status = "main" },
    { name = "dehumanizing", className = "warrior", specName = "fury", status = "main" },
    { name = "barnyard", className = "shaman", specName = "restoration", status = "main" },
    { name = "bisket", className = "warlock", specName = "affliction", status = "main" },
    { name = "friendhelper", className = "druid", specName = "balance", status = "main" },
    { name = "nitt", className = "rogue", specName = "combat", status = "main" },
    { name = "notdewbie", className = "rogue", specName = "assassination", status = "main" },
    { name = "valamas", className = "death knight", specName = "unholy", status = "main" },
    { name = "styrza", className = "warrior", specName = "fury", status = "main" },
    { name = "lexissa", className = "warlock", specName = "demonology", status = "main" },
    { name = "zaneran", className = "warrior", specName = "fury", status = "main" },
    { name = "heisthegoat", className = "warrior", specName = "fury", status = "designatedalt" },
    { name = "command", className = "death knight", specName = "frost", status = "designatedalt" },
    { name = "onaqui", className = "death knight", specName = "blood", status = "main" },
    { name = "seme", className = "druid", specName = "restoration", status = "designatedalt" },
    { name = "tumtum", className = "shaman", specName = "enhancement", status = "main" },
    { name = "scozetti", className = "druid", specName = "balance", status = "main" },
    { name = "fellera", className = "priest", specName = "discipline", status = "main" },
    { name = "sweetde", className = "paladin", specName = "retribution", status = "nil" },
    { name = "zannahdee", className = "mage", specName = "arcane", status = "main" },
    { name = "welkin", className = "shaman", specName = "elemental", status = "nil" },
    { name = "nothara", className = "hunter", specName = "survival", status = "main" },
    { name = "owlation", className = "hunter", specName = "survival", status = "main" },
    { name = "dewbie", className = "paladin", specName = "retribution", status = "nil" },
    { name = "uzragol", className = "shaman", specName = "elemental", status = "main" },
    { name = "helvi", className = "priest", specName = "shadow", status = "main" },
    { name = "zenkahi", className = "death knight", specName = "frost", status = "main" },
    { name = "sweezy", className = "death knight", specName = "unholy", status = "main" },
    { name = "runereaver", className = "death knight", specName = "frost", status = "main" },
    { name = "volckerr", className = "warlock", specName = "affliction", status = "main" },
    { name = "volckurr", className = "hunter", specName = "survival", status = "designatedalt" },
    { name = "illithris", className = "paladin", specName = "holy", status = "main" },
    { name = "stickboard", className = "paladin", specName = "holy", status = "main" },
    { name = "sticknight", className = "death knight", specName = "unholy", status = "designatedalt" },
    { name = "mitsuki", className = "paladin", specName = "retribution", status = "main" },
    { name = "yumie", className = "death knight", specName = "frost", status = "designatedalt" },
    { name = "scozette", className = "mage", specName = "arcane", status = "designatedalt" },
    { name = "thalamier", className = "druid", specName = "feral", status = "main" },
    { name = "hellhound", className = "death knight", specName = "frost", status = "designatedalt" },
    { name = "shapiffany", className = "paladin", specName = "holy", status = "main" },
    { name = "gromnash", className = "death knight", specName = "blood", status = "main" },
    { name = "scarletrage", className = "mage", specName = "arcane", status = "main" },
    { name = "lehran", className = "paladin", specName = "protection", status = "main" },
    { name = "dezmar", className = "warlock", specName = "affliction", status = "main" },
    { name = "ivala", className = "shaman", specName = "enhancement", status = "nil" },
    { name = "iseut", className = "paladin", specName = "retribution", status = "main" },
    { name = "allannon", className = "paladin", specName = "protection", status = "main" },
    { name = "sayri", className = "mage", specName = "fire", status = "designatedalt" },
    { name = "halosylvan", className = "priest", specName = "discipline", status = "main" },
    { name = "kleedus", className = "druid", specName = "restoration", status = "main" },
    { name = "verdalax", className = "druid", specName = "balance", status = "nil" },
    { name = "rigul", className = "rogue", specName = "assassination", status = "main" },
    { name = "naioraa", className = "priest", specName = "discipline", status = "main" },
    { name = "plainam", className = "death knight", specName = "frost", status = "nil" },
    { name = "clemency", className = "paladin", specName = "unknown", status = "nil" },
    { name = "coh", className = "rogue", specName = "unknown", status = "main" },
    { name = "douchenasty", className = "rogue", specName = "unknown", status = "main" },
    { name = "electrocuti", className = "shaman", specName = "unknown", status = "nil" },
    { name = "deathbycuti", className = "death knight", specName = "unknown", status = "nil" },
    { name = "magusar", className = "druid", specName = "unknown", status = "main" },
    { name = "scartin", className = "warrior", specName = "fury", status = "main" },
    { name = "sidecar", className = "druid", specName = "unknown", status = "main" },
    { name = "sosqua", className = "mage", specName = "unknown", status = "nil" },
    { name = "araea", className = "death knight", specName = "unknown", status = "nil" },
    { name = "assaris", className = "druid", specName = "unknown", status = "nil" },
    { name = "bospongi", className = "death knight", specName = "frost", status = "nil" },
    { name = "cheezburgah", className = "druid", specName = "unknown", status = "nil" },
    { name = "fischoeder", className = "druid", specName = "restoration", status = "nil" },
    { name = "dragonfang", className = "hunter", specName = "unknown", status = "nil" },
    { name = "dlnero", className = "warlock", specName = "unknown", status = "main" },
    { name = "gungrisa", className = "warlock", specName = "unknown", status = "nil" },
    { name = "keirb", className = "priest", specName = "unknown", status = "nil" },
    { name = "lawgiver", className = "paladin", specName = "protection", status = "nil" },
    { name = "potatosmashr", className = "warrior", specName = "fury", status = "nil" },
    { name = "psychotic", className = "druid", specName = "unknown", status = "nil" },
    { name = "shecute", className = "death knight", specName = "unknown", status = "nil" },
    { name = "tsea", className = "paladin", specName = "retribution", status = "nil" },
    { name = "vsco", className = "priest", specName = "unknown", status = "nil" },
    { name = "ironklad", className = "paladin", specName = "protection", status = "main" },
    { name = "anagke", className = "paladin", specName = "unknown", status = "nil" },
    { name = "burgah", className = "druid", specName = "unknown", status = "nil" },
    { name = "fuuta", className = "warrior", specName = "unknown", status = "nil" },
    { name = "lizal", className = "priest", specName = "discipline", status = "nil" },
    { name = "remos", className = "death knight", specName = "blood", status = "nil" },
    { name = "rigpal", className = "paladin", specName = "unknown", status = "nil" },
    { name = "volcker", className = "warlock", specName = "affliction", status = "main" },
    { name = "volckur", className = "warlock", specName = "demonology", status = "main" },
}

addon.legacySampleRosterImportText = table.concat({
    "volcker, warlock affliction, main",
    "volckur, mage arcane, designatedAlt",
}, "\n")

local defaultRosterImportText = ""

local defaultLootPriorityText = table.concat({
    "gemmed wand of the nerubians, warlock affliction > warlock demonology > rest",
    "strong-handed ring, warlock demonology > warlock affliction > rest",
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
            rosterEntries = addon.defaultRosterEntries,
            lootPriorityText = defaultLootPriorityText,
            namedItemsText = defaultNamedItemsText,
            roster = {},
            lootRules = {},
            namedRules = {},
            revision = 0,
        },
        ui = {
            selectedTab = "loot",
            lootSortMode = "name",
            lootUsabilitySort = false,
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
    if self:IsAuthorizedLootMaster() then
        self:AutoBroadcastSession(true)
    else
        self:RequestSessionSync()
    end
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
    if self:OnBagUpdate() then
        self:AutoBroadcastSession(false)
    end
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
