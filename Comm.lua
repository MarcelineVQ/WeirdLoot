local addon = WeirdLoot
local util = addon.util

function addon:InitializeComm()
    self.comm = {
        autoSync = {
            lastSignature = nil,
            lastAt = 0,
        },
    }

    -- AceComm-3.0 owns chunking + reassembly and paces every send through
    -- ChatThrottleLib, so a full session broadcast can't trip the server's
    -- addon-message flood limit. It registers its own CHAT_MSG_ADDON frame and
    -- fires OnCommReceived with the fully-reassembled logical message.
    local AceComm = LibStub and LibStub("AceComm-3.0", true)
    if AceComm then
        AceComm:Embed(self)
        self:RegisterComm(self.prefix, "OnCommReceived")
    else
        self:Print("AceComm-3.0 not found; raid sync disabled.")
    end
end

-- One logical message per call. AceComm splits anything over ~254 bytes into
-- ordered multipart chunks and throttles them; keep a single priority so the
-- session burst (SESSION_BEGIN -> ATTENDEE -> ITEM ...) stays in sequence.
function addon:SendLargeMessage(command, values, distribution, target)
    if not self.SendCommMessage then
        return
    end
    local logical = command .. "|" .. util:JoinEncoded(values or {})
    self:SendCommMessage(self.prefix, logical, distribution, target, "NORMAL")
end

-- responses map <-> compact string. Player keys are normalized (no '|'/':'/','/'='), so a
-- "player=tier" list joined by ',' rides safely inside one encoded field.
local function encodeResponses(responses)
    local parts = {}
    for player, tier in pairs(responses or {}) do
        parts[#parts + 1] = tostring(player) .. "=" .. tostring(tier)
    end
    return table.concat(parts, ",")
end

local function decodeResponses(str)
    local out = {}
    for pair in string.gmatch(str or "", "[^,]+") do
        local player, tier = string.match(pair, "^(.-)=(.+)$")
        if player then out[player] = tier end
    end
    return out
end

-- One snapshot of the whole core ledger, replacing the old per-ITEM / per-LOCK / per-RESULT
-- message storm. Sent as SNAP_BEGIN -> LOT* -> SNAP_END; the raider stages the lots and
-- applies them atomically via core:ApplyRemote.
function addon:BroadcastSession()
    if not self:IsAuthorizedLootMaster() then
        self:Print("Only the loot master can broadcast the session.")
        return
    end

    local session = self:GetCurrentSession()
    if not session.active then
        self:Print("Start a loot session first.")
        return
    end

    local core = self.lootCore

    self:SendLargeMessage("SNAP_BEGIN", {
        session.id or "",
        self:GetLootMasterName() or "",
        tostring(core.seq or 0),
    }, "RAID")

    for _, attendee in ipairs(session.attendees or {}) do
        self:SendLargeMessage("ATTENDEE", {
            session.id or "",
            attendee.name or "",
            attendee.className or "",
            attendee.specName or "",
            attendee.status or "nil",
        }, "RAID")
    end

    for _, lot in ipairs(core:All()) do
        if lot.state == core.STATE.RESOLVED or core:LiveCount(lot.id) > 0 then
            local rec = lot.record
            self:SendLargeMessage("LOT", {
                session.id or "",
                lot.id,
                tostring(lot.itemId or 0),
                lot.state,
                tostring(core:LiveCount(lot.id)),
                encodeResponses(lot.responses),
                rec and (rec.winnersText or rec.winner or "") or "",
                rec and rec.summary or "",
                rec and rec.detailText or "",
            }, "RAID")
        end
    end

    self:SendLargeMessage("SNAP_END", { session.id or "" }, "RAID")
end

function addon:BuildSessionSyncSignature()
    local core = self.lootCore
    local parts = { tostring(core.seq or 0) }
    for _, lot in ipairs(core:All()) do
        local n = 0
        for _ in pairs(lot.responses or {}) do n = n + 1 end
        parts[#parts + 1] = table.concat({ lot.id, lot.state, tostring(core:LiveCount(lot.id)), tostring(n) }, "~")
    end
    return table.concat(parts, "|")
end

function addon:AutoBroadcastSession(force)
    local session = self:GetCurrentSession()
    if not self:IsAuthorizedLootMaster() or not session.active then
        return
    end

    local signature = self:BuildSessionSyncSignature()
    local now = (type(GetTime) == "function" and GetTime()) or time()
    local autoSync = self.comm.autoSync or {}

    if not force and autoSync.lastSignature == signature then
        return
    end

    if not force and autoSync.lastAt and (now - autoSync.lastAt) < 0.5 then
        return
    end

    autoSync.lastSignature = signature
    autoSync.lastAt = now
    self.comm.autoSync = autoSync
    self:BroadcastSession()
end

function addon:BroadcastResults(results)
    local session = self:GetCurrentSession()
    for _, result in ipairs(results or {}) do
        self:SendLargeMessage("RESULT", {
            session.id or "",
            result.itemId or "",
            result.itemName or "",
            result.itemLink or "",
            result.itemIcon or result.icon or "",
            tostring(result.quantity or 1),
            result.winnersText or result.winner or "",
            result.summary or "",
            result.detailText or "",
        }, "RAID")
    end
    self:SendLargeMessage("RESULTS_DONE", { session.id or "" }, "RAID")
end

function addon:BroadcastSelectionState(itemId, playerName, choice)
    local session = self:GetCurrentSession()
    if not self:IsAuthorizedLootMaster() or not session.id then
        return
    end

    self:SendLargeMessage("SELECTION_SYNC", {
        session.id or "",
        itemId or "",
        playerName or "",
        choice or "pass",
    }, "RAID")
end

function addon:SendSelection(itemId, choice)
    local session = self:GetCurrentSession()
    if not session.id then
        return
    end

    local playerName = util:GetPlayerName("player")
    local lootMasterName = self:GetLootMasterName()
    if not lootMasterName then
        return
    end

    if util:NormalizeKey(playerName or "") == util:NormalizeKey(lootMasterName or "") then
        return
    end

    self:SendLargeMessage("SELECTION", {
        session.id,
        itemId,
        playerName or "",
        choice or "pass",
    }, "WHISPER", lootMasterName)
end

function addon:RequestSessionSync()
    local lootMasterName = self:GetLootMasterName()
    if not lootMasterName then
        self:Print("No loot master detected for session sync.")
        return
    end

    if self:IsAuthorizedLootMaster() then
        self:BroadcastSession()
        return
    end

    self:SendLargeMessage("REQUEST_SESSION_SYNC", {
        util:GetPlayerName("player") or "",
    }, "WHISPER", lootMasterName)
    self:Print("Requested session sync from loot master.")
end

function addon:BroadcastNamedItems()
    if not self:IsAuthorizedLootMaster() then
        self:Print("Only the loot master can broadcast named items.")
        return
    end

    self:SendLargeMessage("NAMED_ITEMS_SYNC", {
        self:GetLootMasterName() or "",
        self.config.namedItemsText or "",
    }, "RAID")

    self:Print("Broadcast named items sent to raid.")
end

-- AceComm receive callback: prefix-filtered and already reassembled. We still
-- never receive our own RAID/PARTY messages (the client drops them), but keep the
-- self-skip defensively in case of a self-WHISPER echo.
function addon:OnCommReceived(prefix, message, distribution, sender)
    if prefix ~= self.prefix then
        return
    end

    if util:NormalizeKey(util:GetPlayerName("player") or "") == util:NormalizeKey(sender or "") then
        return
    end

    self:HandleCommMessage(sender, message)
end

function addon:HandleCommMessage(sender, logical)
    local fields = util:SplitEncoded(logical)
    local command = table.remove(fields, 1)

    if command == "SNAP_BEGIN" then
        local sessionId, lootMasterName, seq = fields[1], fields[2], tonumber(fields[3]) or 0
        self.session.id = sessionId
        self.session.active = true
        self.session.attendees = {}
        self.roster.lootMasterName = (lootMasterName ~= "" and lootMasterName) or self.roster.lootMasterName
        if self.ui then self.ui.selectedResult = nil end
        self.comm.incoming = { seq = seq, lots = {} } -- stage lots until SNAP_END
    elseif command == "ATTENDEE" then
        self.session.attendees[#self.session.attendees + 1] = {
            name = fields[2],
            className = fields[3],
            specName = fields[4],
            status = fields[5],
        }
        self:TriggerCallback("SESSION_UPDATED")
    elseif command == "LOT" then
        local inc = self.comm.incoming
        if not inc then return end
        local lot = {
            id = fields[2],
            itemId = tonumber(fields[3]),
            state = fields[4],
            count = tonumber(fields[5]) or 0,
            responses = decodeResponses(fields[6]),
        }
        if lot.state == self.lootCore.STATE.RESOLVED then
            local name, link, icon = util:ItemRender(lot.itemId)
            local winnersText = fields[7] or ""
            local winners = {}
            for _, w in ipairs(util:Split(winnersText, ",")) do
                if w ~= "" then winners[#winners + 1] = w end
            end
            lot.record = {
                itemId = lot.id, realItemId = lot.itemId,
                itemName = name or link or ("item:" .. tostring(lot.itemId)),
                itemLink = link, itemIcon = icon, quantity = lot.count,
                winners = winners, winnersText = winnersText, winner = winners[1] or "No winner",
                summary = fields[8] or "", detailText = fields[9] or "", locked = true,
            }
        end
        inc.lots[#inc.lots + 1] = lot
    elseif command == "SNAP_END" then
        local inc = self.comm.incoming
        if inc then
            self.lootCore:ApplyRemote({ seq = inc.seq, lots = inc.lots }) -- -> projections + UI refresh
            self.comm.incoming = nil
        end
    elseif command == "SELECTION" then
        if not self:IsAuthorizedLootMaster() then
            return
        end
        self:SetPlayerResponse(fields[2], fields[3], fields[4]) -- ML core write; snapshot syncs back
    elseif command == "REQUEST_SESSION_SYNC" then
        if not self:IsAuthorizedLootMaster() then
            return
        end
        self:BroadcastSession()
    elseif command == "NAMED_ITEMS_SYNC" then
        local expectedLootMaster = util:NormalizeKey(self:GetLootMasterName() or "")
        local senderKey = util:NormalizeKey(sender or "")
        if expectedLootMaster ~= "" and senderKey ~= expectedLootMaster then
            return
        end
        self:SaveNamedItemsText(fields[2] or "", true)
        self:Print("Named items updated from " .. ((fields[1] ~= "" and fields[1]) or sender or "loot master") .. ".")
    elseif command == "DROP" then
        self:OnDropMessage(fields)
    elseif command == "RSP" then
        self:OnRspMessage(sender, fields)
    elseif command == "WIN" then
        self:OnWinMessage(fields)
    elseif command == "CANCEL" then
        self:OnCancelMessage(fields)
    end
end
