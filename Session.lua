local addon = WeirdLoot
local util = addon.util

local MAX_BAG_ID = 4

function addon:InitializeSession()
    self.session = self.sessionDb.activeSession or {
        id = nil,
        active = false,
        startedAt = nil,
        startSnapshot = {},
        currentSnapshot = {},
        scanMode = "delta",
        items = {},
        responses = {},
        results = {},
        attendees = {},
    }

    self.sessionDb.activeSession = self.session
end

function addon:BuildBagSnapshot()
    local snapshot = {}

    for bag = 0, MAX_BAG_ID do
        local slots = GetContainerNumSlots(bag) or 0
        for slot = 1, slots do
            local link = GetContainerItemLink(bag, slot)
            local _, count, _, quality = GetContainerItemInfo(bag, slot)
            if link and count and quality and quality >= 4 then
                snapshot[link] = (snapshot[link] or 0) + count
            end
        end
    end

    return snapshot
end

function addon:StartLootSession()
    if not self:IsAuthorizedLootMaster() then
        self:Print("Only the loot master can start a loot session.")
        return
    end

    local sessionId = tostring(time())
    self.session.id = sessionId
    self.session.active = true
    self.session.startedAt = time()
    self.session.startSnapshot = self:BuildBagSnapshot()
    self.session.currentSnapshot = util:CloneTable(self.session.startSnapshot)
    self.session.scanMode = "delta"
    self.session.items = {}
    self.session.responses = {}
    self.session.results = {}
    self.session.attendees = util:CloneTable(self:GetAttendees())

    self.sessionDb.history = self.sessionDb.history or {}

    self:TriggerCallback("SESSION_UPDATED")
    self:Print("Loot session started.")
end

function addon:ClearSession()
    self.session.active = false
    self.session.scanMode = "delta"
    self.session.items = {}
    self.session.responses = {}
    self.session.results = {}
    self:TriggerCallback("SESSION_UPDATED")
end

function addon:GetCurrentSession()
    return self.session
end

function addon:BuildSessionItemList(includeAllEpics)
    local session = self:GetCurrentSession()
    if not session.active then
        return {}
    end

    local currentSnapshot = self:BuildBagSnapshot()
    session.currentSnapshot = currentSnapshot

    local counts = {}
    for link, totalCount in pairs(currentSnapshot) do
        if includeAllEpics then
            counts[link] = totalCount
        else
            local startCount = session.startSnapshot[link] or 0
            local delta = totalCount - startCount
            if delta > 0 then
                counts[link] = delta
            end
        end
    end

    local sortedLinks = {}
    for link, count in pairs(counts) do
        local itemName, _, quality, _, _, _, _, _, _, texture = GetItemInfo(link)
        sortedLinks[#sortedLinks + 1] = {
            link = link,
            count = count,
            name = itemName or link,
            icon = texture or "Interface\\Icons\\INV_Misc_QuestionMark",
        }
    end

    table.sort(sortedLinks, function(left, right)
        if left.name == right.name then
            return left.link < right.link
        end
        return left.name < right.name
    end)

    local items = {}
    for linkIndex, entry in ipairs(sortedLinks) do
        items[#items + 1] = {
            id = string.format("%s:%d", session.id, linkIndex),
            link = entry.link,
            name = entry.name,
            icon = entry.icon,
            quantity = entry.count,
        }
    end

    return items
end

function addon:RefreshSessionItems(forceRefresh)
    local session = self:GetCurrentSession()
    if not session.active and not forceRefresh then
        return
    end
    if not session.active and forceRefresh then
        self:StartLootSession()
        session = self:GetCurrentSession()
    end

    if forceRefresh then
        session.scanMode = "all"
    elseif session.scanMode ~= "all" then
        session.scanMode = "delta"
    end

    session.items = self:BuildSessionItemList(session.scanMode == "all")
    session.attendees = util:CloneTable(self:GetAttendees())

    local validIds = {}
    for _, item in ipairs(session.items) do
        validIds[item.id] = true
        session.responses[item.id] = session.responses[item.id] or {}
    end

    for itemId in pairs(session.responses) do
        if not validIds[itemId] then
            session.responses[itemId] = nil
        end
    end

    self:TriggerCallback("SESSION_UPDATED")
end

function addon:OnBagUpdate()
    local session = self:GetCurrentSession()
    if not session.active then
        return
    end
    if session.scanMode == "all" then
        self:RefreshSessionItems(true)
    else
        self:RefreshSessionItems()
    end
end

function addon:SetPlayerResponse(itemId, playerName, shouldRoll)
    local session = self:GetCurrentSession()
    if not session.responses[itemId] then
        session.responses[itemId] = {}
    end
    session.responses[itemId][util:NormalizeKey(playerName)] = shouldRoll and true or false
    self:TriggerCallback("SESSION_UPDATED")
end

function addon:GetPlayerResponse(itemId, playerName)
    local session = self:GetCurrentSession()
    local responses = session.responses[itemId] or {}
    return responses[util:NormalizeKey(playerName)] == true
end

function addon:GetItemById(itemId)
    for _, item in ipairs(self.session.items or {}) do
        if item.id == itemId then
            return item
        end
    end
    return nil
end
