local addon = WeirdLoot
local util = addon.util

local configClassAliases = {
    ["death knight"] = "death knight",
    deathknight = "death knight",
    dk = "death knight",
    druid = "druid",
    hunter = "hunter",
    mage = "mage",
    paladin = "paladin",
    priest = "priest",
    rogue = "rogue",
    shaman = "shaman",
    warlock = "warlock",
    warrior = "warrior",
}

local orderedClassNames = {
    "death knight",
    "paladin",
    "priest",
    "warlock",
    "warrior",
    "hunter",
    "shaman",
    "druid",
    "rogue",
    "mage",
}

function addon:InitializeConfig()
    self.config = self.db.config
    self:NormalizeAllConfig()
end

function addon:NormalizeClassName(value)
    local normalized = util:NormalizeKey(value)
    return configClassAliases[normalized] or normalized
end

function addon:NormalizeStatus(value)
    local normalized = util:NormalizeKey(value)
    if normalized == "alt" or normalized == "designated alt" then
        normalized = "designatedalt"
    end
    if normalized ~= "main" and normalized ~= "designatedalt" then
        normalized = "nil"
    end
    return normalized
end

function addon:ParseClassSpecToken(token)
    token = util:NormalizeKey(token)
    if token == "" or token == "rest" then
        return {
            isRest = true,
            raw = "rest",
        }
    end

    local className
    local specName = ""

    for _, candidateClass in ipairs(orderedClassNames) do
        local prefix = candidateClass .. " "
        local suffix = " " .. candidateClass

        if token == candidateClass then
            className = candidateClass
            specName = ""
            break
        elseif string.sub(token, 1, string.len(prefix)) == prefix then
            className = candidateClass
            specName = string.sub(token, string.len(prefix) + 1)
            break
        elseif string.sub(token, -string.len(suffix)) == suffix then
            className = candidateClass
            specName = string.sub(token, 1, string.len(token) - string.len(suffix))
            break
        end
    end

    specName = util:NormalizeKey(specName)

    return {
        raw = token,
        className = className,
        specName = specName,
        matchKeys = {
            util:NormalizeKey((className or "") .. " " .. (specName or "")),
            util:NormalizeKey((specName or "") .. " " .. (className or "")),
        },
    }
end

function addon:ParseRosterImport(text)
    local rosterEntries = {}
    for _, line in ipairs(util:SplitLines(text)) do
        local parts = util:Split(line, ",")
        local rawName = string.trim(parts[1] or "")
        local descriptor = string.trim(parts[2] or "")
        local status = self:NormalizeStatus(parts[3] or "")
        if rawName ~= "" then
            local parsed = self:ParseClassSpecToken(descriptor)
            rosterEntries[#rosterEntries + 1] = {
                name = rawName,
                className = parsed.className,
                specName = parsed.specName,
                status = status,
                descriptor = descriptor,
            }
        end
    end
    return rosterEntries
end

function addon:NormalizeRosterEntries(entries)
    local normalizedEntries = {}
    local seen = {}

    for _, entry in ipairs(entries or {}) do
        local name = string.trim(entry.name or "")
        if name ~= "" then
            local key = util:NormalizeKey(name)
            if not seen[key] then
                local className = self:NormalizeClassName(entry.className or "")
                local specName = util:NormalizeKey(entry.specName or "")
                local status = self:NormalizeStatus(entry.status or "")
                normalizedEntries[#normalizedEntries + 1] = {
                    name = name,
                    className = className,
                    specName = specName,
                    status = status,
                    descriptor = util:NormalizeKey((className or "") .. " " .. (specName or "")),
                }
                seen[key] = true
            end
        end
    end

    table.sort(normalizedEntries, function(left, right)
        return util:NormalizeKey(left.name) < util:NormalizeKey(right.name)
    end)

    return normalizedEntries
end

function addon:BuildRosterMap(entries)
    local roster = {}
    for _, entry in ipairs(entries or {}) do
        roster[util:NormalizeKey(entry.name)] = {
            name = entry.name,
            className = entry.className,
            specName = entry.specName,
            status = entry.status,
            descriptor = entry.descriptor or util:NormalizeKey((entry.className or "") .. " " .. (entry.specName or "")),
        }
    end
    return roster
end

function addon:SerializeRosterEntries(entries)
    local lines = {}
    for _, entry in ipairs(entries or {}) do
        local status = entry.status == "designatedalt" and "designatedAlt" or (entry.status == "main" and "main" or "unknown")
        local descriptor = string.trim((entry.className or "") .. " " .. (entry.specName or ""))
        lines[#lines + 1] = string.format("%s, %s, %s", entry.name or "", descriptor, status)
    end
    return table.concat(lines, "\n")
end

function addon:ParseTieredRuleText(text, parser)
    local rules = {}

    for _, line in ipairs(util:SplitLines(text)) do
        local parts = util:Split(line, ",")
        local itemName = string.trim(parts[1] or "")
        local ruleText = string.trim(parts[2] or "")
        if itemName ~= "" and ruleText ~= "" then
            local tiers = {}

            for tierIndex, tierText in ipairs(util:Split(ruleText, ">")) do
                local entries = {}
                tierText = string.trim(tierText)
                for _, token in ipairs(util:Split(tierText, "/")) do
                    local parsed = parser(self, token)
                    if parsed then
                        if parsed.isRest then
                            table.insert(entries, {
                                raw = "rest",
                                isRest = true,
                            })
                        else
                            table.insert(entries, parsed)
                        end
                    end
                end

                if #entries > 0 then
                    tiers[#tiers + 1] = {
                        index = tierIndex,
                        raw = tierText,
                        entries = entries,
                    }
                end
            end

            local key = util:NormalizeKey(itemName)
            rules[key] = {
                itemName = itemName,
                tiers = tiers,
                raw = ruleText,
                key = key,
            }
        end
    end

    return rules
end

function addon:ParseNamedToken(token)
    token = util:NormalizeKey(token)
    if token == "" then
        return nil
    end
    if token == "rest" then
        return {
            isRest = true,
            raw = "rest",
        }
    end
    return {
        raw = token,
        playerKey = util:NormalizeKey(token),
    }
end

function addon:NormalizeAllConfig()
    local rosterEntries = self.config.rosterEntries
    local rosterImportText = self.config.rosterImportText or ""
    local shouldUseDefaultRoster = rosterImportText == "" or rosterImportText == (self.legacySampleRosterImportText or "")

    if shouldUseDefaultRoster and (type(rosterEntries) ~= "table" or #rosterEntries <= 2) then
        rosterEntries = util:CloneTable(self.defaultRosterEntries or {})
    elseif type(rosterEntries) ~= "table" or #rosterEntries == 0 then
        rosterEntries = self:ParseRosterImport(self.config.rosterImportText or "")
    end
    if type(rosterEntries) ~= "table" or #rosterEntries == 0 then
        rosterEntries = util:CloneTable(self.defaultRosterEntries or {})
    end

    self.config.rosterEntries = self:NormalizeRosterEntries(rosterEntries)
    self.config.roster = self:BuildRosterMap(self.config.rosterEntries)
    self.config.rosterImportText = self:SerializeRosterEntries(self.config.rosterEntries)
    self.config.lootRules = self:ParseTieredRuleText(self.config.lootPriorityText or "", self.ParseClassSpecToken)
    self.config.namedRules = self:ParseTieredRuleText(self.config.namedItemsText or "", self.ParseNamedToken)
end

function addon:SaveImports(rosterText, lootText, namedText)
    if rosterText ~= nil then
        self.config.rosterEntries = self:ParseRosterImport(rosterText or "")
        self.config.rosterImportText = rosterText or ""
    end
    self.config.lootPriorityText = lootText or self.config.lootPriorityText or ""
    self.config.namedItemsText = namedText or self.config.namedItemsText or ""
    self.config.revision = (self.config.revision or 0) + 1
    self:NormalizeAllConfig()
    self:RefreshRoster()
    self:TriggerCallback("CONFIG_UPDATED")
    self:Print("Configuration saved.")
end

function addon:GetRosterProfile(playerName)
    if not playerName then
        return nil
    end
    return self.config.roster[util:NormalizeKey(playerName)]
end

function addon:GetLootRule(itemName)
    return self.config.lootRules[util:NormalizeKey(itemName or "")]
end

function addon:GetNamedRule(itemName)
    return self.config.namedRules[util:NormalizeKey(itemName or "")]
end

function addon:GetRosterEntries()
    return self.config.rosterEntries or {}
end
