local addon = WeirdLoot
local util = addon.util

function addon:InitializeRoster()
    self.roster = {
        attendees = {},
        attendeesByName = {},
        rosterDisplay = {},
        isLootMaster = false,
        lootMasterName = nil,
    }
end

function addon:RefreshRoster()
    local attendees = {}
    local attendeesByName = {}
    local count = GetNumRaidMembers() or 0

    for index = 1, count do
        local name, _, _, _, classLocalized, classFileName = GetRaidRosterInfo(index)
        name = name and string.match(name, "^[^-]+") or name
        if name then
            local profile = self:GetRosterProfile(name) or {}
            local className = profile.className or self:NormalizeClassName(classFileName or classLocalized or "")
            local specName = profile.specName or ""
            local status = profile.status or "nil"

            local attendee = {
                index = index,
                name = name,
                className = className,
                specName = specName,
                status = status,
                descriptor = util:NormalizeKey((className or "") .. " " .. (specName or "")),
            }
            attendees[#attendees + 1] = attendee
            attendeesByName[util:NormalizeKey(name)] = attendee
        end
    end

    util:SortByName(attendees, "name")

    self.roster.attendees = attendees
    self.roster.attendeesByName = attendeesByName
    self.roster.rosterDisplay = self:BuildRosterDisplay(attendeesByName)

    self:TriggerCallback("ROSTER_UPDATED")
end

function addon:BuildRosterDisplay(attendeesByName)
    local display = {}
    local seen = {}

    for _, entry in ipairs(self:GetRosterEntries()) do
        local key = util:NormalizeKey(entry.name)
        local attendee = attendeesByName[key]
        display[#display + 1] = {
            name = entry.name,
            className = entry.className,
            specName = entry.specName,
            status = entry.status,
            present = attendee ~= nil,
            descriptor = entry.descriptor,
            source = "configured",
        }
        seen[key] = true
    end

    for key, attendee in pairs(attendeesByName or {}) do
        if not seen[key] then
            display[#display + 1] = {
                name = attendee.name,
                className = attendee.className,
                specName = attendee.specName,
                status = attendee.status or "nil",
                present = true,
                descriptor = attendee.descriptor,
                source = "unconfigured",
            }
        end
    end

    table.sort(display, function(left, right)
        if left.present ~= right.present then
            return left.present
        end
        if left.source ~= right.source then
            return left.source == "configured"
        end
        return util:NormalizeKey(left.name) < util:NormalizeKey(right.name)
    end)

    return display
end

function addon:GetAttendees()
    return self.roster.attendees or {}
end

function addon:GetAttendee(name)
    return self.roster.attendeesByName[util:NormalizeKey(name or "")]
end

function addon:GetRosterDisplayList()
    return self.roster.rosterDisplay or {}
end

function addon:RefreshLootAuthority()
    local lootMasterName
    local lootMethod, _, raidIndex = GetLootMethod()

    if lootMethod == "master" and raidIndex then
        local name = GetRaidRosterInfo(raidIndex)
        lootMasterName = name and string.match(name, "^[^-]+") or name
    end

    local playerName = util:GetPlayerName("player")
    local isLeader = false
    local isOfficer = false
    local isLootMaster = false

    for index = 1, (GetNumRaidMembers() or 0) do
        local name, rank = GetRaidRosterInfo(index)
        name = name and string.match(name, "^[^-]+") or name
        if playerName and name and util:NormalizeKey(name) == util:NormalizeKey(playerName) then
            isLeader = rank == 2
            isOfficer = rank == 1
            break
        end
    end

    if lootMasterName and playerName then
        isLootMaster = util:NormalizeKey(lootMasterName) == util:NormalizeKey(playerName)
    end

    if not lootMasterName and (isLeader or isOfficer) then
        lootMasterName = playerName
    end

    if not isLootMaster and (isLeader or isOfficer) and lootMethod ~= "master" then
        isLootMaster = true
    end

    self.roster.lootMasterName = lootMasterName
    self.roster.isLootMaster = isLootMaster

    self:TriggerCallback("AUTHORITY_UPDATED")
end

function addon:IsAuthorizedLootMaster()
    return self.roster.isLootMaster
end

function addon:GetLootMasterName()
    return self.roster.lootMasterName
end

function addon:GetPlayerDescriptor(playerName)
    local attendee = self:GetAttendee(playerName) or self:GetRosterProfile(playerName)
    if not attendee then
        return ""
    end

    local className = attendee.className or ""
    local specName = attendee.specName or ""
    return util:NormalizeKey(className .. " " .. specName)
end
