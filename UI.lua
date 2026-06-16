local addon = WeirdLoot
local util = addon.util

local ROW_HEIGHT = 22
local TAB_KEYS = { "loot", "raiders", "results", "master" }
local TAB_LABELS = {
    loot = "Loot",
    raiders = "Raiders",
    results = "Results",
    master = "Loot Master",
}

local function createLabel(parent, text, anchor, relativeTo, relativePoint, offsetX, offsetY)
    local fontString = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fontString:SetPoint(anchor, relativeTo, relativePoint, offsetX, offsetY)
    fontString:SetJustifyH("LEFT")
    fontString:SetText(text)
    return fontString
end

local function createButton(parent, text, width, height)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetWidth(width)
    button:SetHeight(height)
    button:SetText(text)
    return button
end

local function createBackdropFrame(name, parent)
    local frame = CreateFrame("Frame", name, parent)
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    frame:SetBackdropColor(0.05, 0.05, 0.08, 0.95)
    return frame
end

local function createScrollList(parent, name, rowCount, initializer)
    local frame = createBackdropFrame(name, parent)
    frame.scroll = CreateFrame("ScrollFrame", name .. "Scroll", frame, "FauxScrollFrameTemplate")
    frame.scroll:SetPoint("TOPLEFT", 0, -4)
    frame.scroll:SetPoint("BOTTOMRIGHT", -26, 4)

    frame.rows = {}
    for index = 1, rowCount do
        local row = CreateFrame("Button", name .. "Row" .. index, frame)
        row:SetHeight(ROW_HEIGHT)
        row:SetPoint("LEFT", 6, 0)
        row:SetPoint("RIGHT", -6, 0)
        if index == 1 then
            row:SetPoint("TOP", frame, "TOP", 0, -8)
        else
            row:SetPoint("TOP", frame.rows[index - 1], "BOTTOM", 0, -2)
        end
        initializer(row, index)
        frame.rows[index] = row
    end

    frame.update = function(totalCount, updater)
        frame.totalCount = totalCount
        frame.rowUpdater = updater
        local offset = FauxScrollFrame_GetOffset(frame.scroll)
        FauxScrollFrame_Update(frame.scroll, totalCount, rowCount, ROW_HEIGHT)
        for index, row in ipairs(frame.rows) do
            local dataIndex = index + offset
            updater(row, dataIndex)
        end
    end

    frame.scroll:SetScript("OnVerticalScroll", function(scrollFrame, offset)
        FauxScrollFrame_OnVerticalScroll(scrollFrame, offset, ROW_HEIGHT, function()
            if frame.rowUpdater then
                frame.update(frame.totalCount or 0, frame.rowUpdater)
            end
        end)
    end)

    return frame
end

function addon:InitializeUI()
    self.ui = self.ui or {}

    local frame = createBackdropFrame("WeirdLootFrame", UIParent)
    frame:SetWidth(980)
    frame:SetHeight(640)
    frame:SetPoint("CENTER", UIParent, "CENTER", self.db.ui.frame.x or 0, self.db.ui.frame.y or 0)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(selfFrame)
        selfFrame:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(selfFrame)
        selfFrame:StopMovingOrSizing()
        local _, _, _, x, y = selfFrame:GetPoint()
        addon.db.ui.frame.x = x
        addon.db.ui.frame.y = y
    end)
    frame:Hide()

    local title = createLabel(frame, "WeirdLoot", "TOPLEFT", frame, "TOPLEFT", 16, -14)
    title:SetFontObject(GameFontHighlightLarge)

    local closeButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)

    local status = createLabel(frame, "", "TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    status:SetWidth(720)

    local content = CreateFrame("Frame", nil, frame)
    content:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -64)
    content:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -12, 44)

    self.ui.frame = frame
    self.ui.status = status
    self.ui.content = content
    self.ui.tabs = {}
    self.ui.panels = {}
    self.ui.selectedTab = self.db.ui.selectedTab or "loot"

    self:BuildLootTab()
    self:BuildRaidersTab()
    self:BuildResultsTab()
    self:BuildMasterTab()
    self:BuildBottomTabs()

    self:RegisterCallback("STATE_UPDATED", function()
        addon:RefreshUI()
    end)
    self:RegisterCallback("CONFIG_UPDATED", function()
        addon:RefreshUI()
    end)
    self:RegisterCallback("ROSTER_UPDATED", function()
        addon:RefreshUI()
    end)
    self:RegisterCallback("AUTHORITY_UPDATED", function()
        addon:RefreshUI()
    end)
    self:RegisterCallback("SESSION_UPDATED", function()
        addon:RefreshUI()
    end)
    self:RegisterCallback("RESULTS_UPDATED", function()
        addon:RefreshUI()
    end)

    self:SelectTab(self.ui.selectedTab)
    self:RefreshUI()
end

function addon:BuildBottomTabs()
    local previous
    for _, key in ipairs(TAB_KEYS) do
        local tab = createButton(self.ui.frame, TAB_LABELS[key], 120, 24)
        if not previous then
            tab:SetPoint("BOTTOMLEFT", self.ui.frame, "BOTTOMLEFT", 16, 12)
        else
            tab:SetPoint("LEFT", previous, "RIGHT", 8, 0)
        end
        tab:SetScript("OnClick", function()
            addon:SelectTab(key)
        end)
        self.ui.tabs[key] = tab
        previous = tab
    end
end

function addon:SelectTab(tabKey)
    self.ui.selectedTab = tabKey
    self.db.ui.selectedTab = tabKey

    for key, panel in pairs(self.ui.panels) do
        if key == tabKey then
            panel:Show()
        else
            panel:Hide()
        end
    end

    self:RefreshUI()
end

function addon:ToggleMainFrame()
    if not self.ui or not self.ui.frame then
        self:Print("UI is not initialized yet. If this keeps happening, reload the UI and check script errors.")
        return
    end

    if self.ui.frame:IsShown() then
        self.ui.frame:Hide()
    else
        self.ui.frame:Show()
        self:RefreshUI()
    end
end

function addon:BuildLootTab()
    local panel = CreateFrame("Frame", nil, self.ui.content)
    panel:SetAllPoints(self.ui.content)
    self.ui.panels.loot = panel

    local header = createLabel(panel, "Session items", "TOPLEFT", panel, "TOPLEFT", 4, -4)
    header:SetFontObject(GameFontHighlight)

    local syncButton = createButton(panel, "Request Sync", 110, 22)
    syncButton:SetPoint("LEFT", header, "RIGHT", 12, 0)
    syncButton:SetScript("OnClick", function()
        addon:RequestSessionSync()
    end)
    panel.syncButton = syncButton

    local list = createScrollList(panel, "WeirdLootLootList", 20, function(row)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetWidth(18)
        row.icon:SetHeight(18)
        row.icon:SetPoint("LEFT", row, "LEFT", 4, 0)

        row.name = createLabel(row, "", "LEFT", row.icon, "RIGHT", 8, 0)
        row.name:SetWidth(340)

        row.roll = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
        row.roll:SetPoint("LEFT", row.name, "RIGHT", 16, 0)
        row.roll:SetScript("OnClick", function(button)
            if not row.item then
                return
            end
            row.pass:SetChecked(not button:GetChecked())
            local playerName = util:GetPlayerName("player")
            addon:SetPlayerResponse(row.item.id, playerName, button:GetChecked())
            addon:BroadcastSelectionState(row.item.id, playerName, button:GetChecked())
            addon:SendSelection(row.item.id, button:GetChecked())
        end)
        row.rollText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.rollText:SetPoint("LEFT", row.roll, "RIGHT", 2, 0)
        row.rollText:SetText("Roll")

        row.pass = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
        row.pass:SetPoint("LEFT", row.rollText, "RIGHT", 24, 0)
        row.pass:SetScript("OnClick", function(button)
            if not row.item then
                return
            end
            row.roll:SetChecked(not button:GetChecked())
            local playerName = util:GetPlayerName("player")
            local shouldRoll = row.roll:GetChecked()
            addon:SetPlayerResponse(row.item.id, playerName, shouldRoll)
            addon:BroadcastSelectionState(row.item.id, playerName, shouldRoll)
            addon:SendSelection(row.item.id, shouldRoll)
        end)
        row.passText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.passText:SetPoint("LEFT", row.pass, "RIGHT", 2, 0)
        row.passText:SetText("Pass")

        row.state = createLabel(row, "", "LEFT", row.passText, "RIGHT", 20, 0)
        row.state:SetWidth(240)
        row.stateHitbox = CreateFrame("Frame", nil, row)
        row.stateHitbox:SetPoint("TOPLEFT", row.state, "TOPLEFT", -4, 4)
        row.stateHitbox:SetPoint("BOTTOMRIGHT", row.state, "BOTTOMRIGHT", 4, -4)
        row.stateHitbox:EnableMouse(true)
        row.stateHitbox:SetScript("OnEnter", function()
            if not row.item then
                return
            end

            local rollers = {}
            for playerKey, shouldRoll in pairs(addon.session.responses[row.item.id] or {}) do
                if shouldRoll then
                    local attendee = addon:GetAttendee(playerKey) or addon:GetRosterProfile(playerKey)
                    rollers[#rollers + 1] = {
                        name = attendee and attendee.name or playerKey,
                        className = attendee and attendee.className or "",
                        specName = attendee and attendee.specName or "",
                    }
                end
            end

            table.sort(rollers, function(left, right)
                return string.lower(left.name or "") < string.lower(right.name or "")
            end)

            GameTooltip:SetOwner(row.stateHitbox, "ANCHOR_NONE")
            GameTooltip:ClearAllPoints()
            GameTooltip:SetPoint("TOPLEFT", row.stateHitbox, "BOTTOMLEFT", 0, -4)
            GameTooltip:ClearLines()
            GameTooltip:AddLine("Players Rolling", 1, 0.82, 0)

            if #rollers == 0 then
                GameTooltip:AddLine("No active rollers", 1, 1, 1)
            else
                for _, roller in ipairs(rollers) do
                    local classSpec = string.trim((roller.className or "") .. " " .. (roller.specName or ""))
                    local colorCode = util:GetClassColorCode(roller.className)
                    local line = colorCode .. (roller.name or "") .. "|r"
                    if classSpec ~= "" then
                        line = line .. " - " .. classSpec
                    end
                    GameTooltip:AddLine(line, 1, 1, 1)
                end
            end

            GameTooltip:Show()
        end)
        row.stateHitbox:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)

        row:SetScript("OnEnter", function(selfRow)
            if not selfRow.item or not selfRow.item.link or selfRow.item.link == "" then
                return
            end

            GameTooltip:SetOwner(selfRow, "ANCHOR_NONE")
            GameTooltip:ClearAllPoints()
            GameTooltip:SetPoint("TOPRIGHT", selfRow, "TOPLEFT", -8, 0)
            GameTooltip:SetHyperlink(selfRow.item.link)
            GameTooltip:Show()
        end)

        row:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)

        row:SetScript("OnClick", function(selfRow, button)
            if button ~= "LeftButton" or not selfRow.item or not selfRow.item.link or selfRow.item.link == "" then
                return
            end

            if IsShiftKeyDown() and ChatEdit_GetActiveWindow() then
                ChatEdit_InsertLink(selfRow.item.link)
                return
            end

            if DressUpItemLink then
                DressUpItemLink(selfRow.item.link)
            else
                GameTooltip:SetOwner(selfRow, "ANCHOR_NONE")
                GameTooltip:ClearAllPoints()
                GameTooltip:SetPoint("TOPRIGHT", selfRow, "TOPLEFT", -8, 0)
                GameTooltip:SetHyperlink(selfRow.item.link)
                GameTooltip:Show()
            end
        end)
    end)
    list:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -8)
    list:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -4, 4)
    self.ui.lootList = list
end

function addon:BuildRaidersTab()
    local panel = CreateFrame("Frame", nil, self.ui.content)
    panel:SetAllPoints(self.ui.content)
    self.ui.panels.raiders = panel

    local list = createScrollList(panel, "WeirdLootRaidersList", 22, function(row)
        row.name = createLabel(row, "", "LEFT", row, "LEFT", 8, 0)
        row.name:SetWidth(200)
        row.classSpec = createLabel(row, "", "LEFT", row.name, "RIGHT", 12, 0)
        row.classSpec:SetWidth(260)
        row.status = createLabel(row, "", "LEFT", row.classSpec, "RIGHT", 12, 0)
        row.status:SetWidth(160)
    end)
    list:SetAllPoints(panel)
    self.ui.raidersList = list
end

function addon:BuildResultsTab()
    local panel = CreateFrame("Frame", nil, self.ui.content)
    panel:SetAllPoints(self.ui.content)
    self.ui.panels.results = panel

    local list = createScrollList(panel, "WeirdLootResultsList", 16, function(row)
        row.name = createLabel(row, "", "LEFT", row, "LEFT", 8, 0)
        row.name:SetWidth(320)
        row.winner = createLabel(row, "", "LEFT", row.name, "RIGHT", 12, 0)
        row.winner:SetWidth(200)
        row:SetScript("OnClick", function()
            if row.result then
                addon.ui.selectedResult = row.result
                addon:RefreshUI()
            end
        end)
    end)
    list:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
    list:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 0, 0)
    list:SetWidth(520)

    local detailFrame = createBackdropFrame("WeirdLootResultDetail", panel)
    detailFrame:SetPoint("TOPLEFT", list, "TOPRIGHT", 8, 0)
    detailFrame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0)

    local scroll = CreateFrame("ScrollFrame", "WeirdLootResultDetailScroll", detailFrame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 8, -8)
    scroll:SetPoint("BOTTOMRIGHT", -30, 8)

    local editBox = CreateFrame("EditBox", "WeirdLootResultDetailText", scroll)
    editBox:SetMultiLine(true)
    editBox:SetFontObject(ChatFontNormal)
    editBox:SetWidth(380)
    editBox:SetHeight(1200)
    editBox:SetAutoFocus(false)
    editBox:EnableMouse(true)
    editBox:SetScript("OnEscapePressed", function() editBox:ClearFocus() end)
    scroll:SetScrollChild(editBox)

    self.ui.resultsList = list
    self.ui.resultDetail = editBox
end

function addon:BuildMasterTab()
    local panel = CreateFrame("Frame", nil, self.ui.content)
    panel:SetAllPoints(self.ui.content)
    self.ui.panels.master = panel

    panel.warning = createLabel(panel, "", "TOPLEFT", panel, "TOPLEFT", 8, -8)
    panel.warning:SetTextColor(1, 0.2, 0.2)

    local startButton = createButton(panel, "Start Session", 120, 24)
    startButton:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -36)
    startButton:SetScript("OnClick", function()
        addon:StartLootSession()
    end)

    local scanButton = createButton(panel, "Scan Bags", 120, 24)
    scanButton:SetPoint("LEFT", startButton, "RIGHT", 8, 0)
    scanButton:SetScript("OnClick", function()
        addon:RefreshSessionItems(true)
    end)

    local broadcastButton = createButton(panel, "Broadcast", 120, 24)
    broadcastButton:SetPoint("LEFT", scanButton, "RIGHT", 8, 0)
    broadcastButton:SetScript("OnClick", function()
        addon:BroadcastSession()
    end)

    local processButton = createButton(panel, "Process Loot", 120, 24)
    processButton:SetPoint("LEFT", broadcastButton, "RIGHT", 8, 0)
    processButton:SetScript("OnClick", function()
        addon:ProcessLoot()
    end)

    panel.startButton = startButton
    panel.scanButton = scanButton
    panel.broadcastButton = broadcastButton
    panel.processButton = processButton

    panel.rosterLabel = createLabel(panel, "Roster import", "TOPLEFT", startButton, "BOTTOMLEFT", 0, -18)
    panel.rosterBox = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    panel.rosterBox:SetMultiLine(true)
    panel.rosterBox:SetFontObject(ChatFontNormal)
    panel.rosterBox:SetWidth(300)
    panel.rosterBox:SetHeight(180)
    panel.rosterBox:SetPoint("TOPLEFT", panel.rosterLabel, "BOTTOMLEFT", 0, -6)
    panel.rosterBox:SetAutoFocus(false)

    panel.lootLabel = createLabel(panel, "Loot priority import", "TOPLEFT", panel.rosterBox, "TOPRIGHT", 18, 0)
    panel.lootBox = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    panel.lootBox:SetMultiLine(true)
    panel.lootBox:SetFontObject(ChatFontNormal)
    panel.lootBox:SetWidth(300)
    panel.lootBox:SetHeight(180)
    panel.lootBox:SetPoint("TOPLEFT", panel.lootLabel, "BOTTOMLEFT", 0, -6)
    panel.lootBox:SetAutoFocus(false)

    panel.namedLabel = createLabel(panel, "Named item import", "TOPLEFT", panel.lootBox, "TOPRIGHT", 18, 0)
    panel.namedBox = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    panel.namedBox:SetMultiLine(true)
    panel.namedBox:SetFontObject(ChatFontNormal)
    panel.namedBox:SetWidth(300)
    panel.namedBox:SetHeight(180)
    panel.namedBox:SetPoint("TOPLEFT", panel.namedLabel, "BOTTOMLEFT", 0, -6)
    panel.namedBox:SetAutoFocus(false)

    local saveButton = createButton(panel, "Save Imports", 120, 24)
    saveButton:SetPoint("TOPLEFT", panel.rosterBox, "BOTTOMLEFT", 0, -14)
    saveButton:SetScript("OnClick", function()
        addon:SaveImports(panel.rosterBox:GetText(), panel.lootBox:GetText(), panel.namedBox:GetText())
    end)

    panel.summary = createLabel(panel, "", "TOPLEFT", saveButton, "BOTTOMLEFT", 0, -16)
    panel.summary:SetWidth(900)
    panel.summary:SetJustifyV("TOP")

    self.ui.masterPanel = panel
end

function addon:RefreshUI()
    if not self.ui or not self.ui.frame then
        return
    end

    local session = self:GetCurrentSession()
    local lootMasterName = self:GetLootMasterName() or "Unknown"
    local authority = self:IsAuthorizedLootMaster() and "Yes" or "No"
    local sessionState = session.active and ("Active session " .. (session.id or "")) or "No active session"
    self.ui.status:SetText(string.format("Loot master: %s | Authorized: %s | %s", lootMasterName, authority, sessionState))

    self:RefreshLootTab()
    self:RefreshRaidersTab()
    self:RefreshResultsTab()
    self:RefreshMasterTab()
end

function addon:RefreshLootTab()
    local items = self.session.items or {}
    local playerName = util:GetPlayerName("player")
    if self.ui.panels and self.ui.panels.loot and self.ui.panels.loot.syncButton then
        local label = self:IsAuthorizedLootMaster() and "Rebroadcast" or "Request Sync"
        self.ui.panels.loot.syncButton:SetText(label)
    end
    self.ui.lootList.update(#items, function(row, index)
        local item = items[index]
        row.item = item
        if not item then
            row:Hide()
            return
        end

        row:Show()
        row.icon:SetTexture(item.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        local itemText = item.link and item.link ~= "" and item.link or item.name or ""
        if (item.quantity or 1) > 1 then
            itemText = string.format("%s x%d", itemText, item.quantity)
        end
        row.name:SetText(itemText)

        local shouldRoll = self:GetPlayerResponse(item.id, playerName)
        row.roll:SetChecked(shouldRoll)
        row.pass:SetChecked(not shouldRoll)

        local rollCount = 0
        for _, shouldPlayerRoll in pairs(self.session.responses[item.id] or {}) do
            if shouldPlayerRoll then
                rollCount = rollCount + 1
            end
        end
        row.state:SetText(string.format("%d roller(s)", rollCount))
    end)
end

function addon:RefreshRaidersTab()
    local attendees = self.session.attendees and #self.session.attendees > 0 and self.session.attendees or self:GetAttendees()
    self.ui.raidersList.update(#attendees, function(row, index)
        local attendee = attendees[index]
        if not attendee then
            row:Hide()
            return
        end
        row:Show()
        row.name:SetText(attendee.name or "")
        row.classSpec:SetText(string.trim((attendee.className or "") .. " " .. (attendee.specName or "")))
        row.status:SetText(util:PlayerDisplayStatus(attendee.status))
    end)
end

function addon:RefreshResultsTab()
    local results = self.session.results or {}
    self.ui.resultsList.update(#results, function(row, index)
        local result = results[index]
        row.result = result
        if not result then
            row:Hide()
            return
        end
        row:Show()
        local itemText = (result.itemLink and result.itemLink ~= "" and result.itemLink) or result.itemName or ""
        if (result.quantity or 1) > 1 then
            itemText = string.format("%s x%d", itemText, result.quantity)
        end
        row.name:SetText(itemText)
        row.winner:SetText(result.winnersText or result.winner or "No winner")
    end)

    local selected = self.ui.selectedResult
    if not selected and results[1] then
        selected = results[1]
        self.ui.selectedResult = selected
    end

    self.ui.resultDetail:SetText(selected and selected.detailText or "No results yet.")
end

function addon:RefreshMasterTab()
    local panel = self.ui.masterPanel
    local authorized = self:IsAuthorizedLootMaster()
    panel.warning:SetText(authorized and "" or "Loot master controls are locked until you are the loot master or leadership fallback.")

    if authorized then
        panel.startButton:Enable()
        panel.scanButton:Enable()
        panel.broadcastButton:Enable()
        panel.processButton:Enable()
    else
        panel.startButton:Disable()
        panel.scanButton:Disable()
        panel.broadcastButton:Disable()
        panel.processButton:Disable()
    end
    panel.rosterBox:EnableMouse(authorized)
    panel.lootBox:EnableMouse(authorized)
    panel.namedBox:EnableMouse(authorized)
    if panel.rosterBox.Disable then
        if authorized then
            panel.rosterBox:Enable()
            panel.lootBox:Enable()
            panel.namedBox:Enable()
        else
            panel.rosterBox:Disable()
            panel.lootBox:Disable()
            panel.namedBox:Disable()
        end
    end

    if not panel.rosterBox:HasFocus() and panel.rosterBox:GetText() ~= (self.config.rosterImportText or "") then
        panel.rosterBox:SetText(self.config.rosterImportText or "")
    end
    if not panel.lootBox:HasFocus() and panel.lootBox:GetText() ~= (self.config.lootPriorityText or "") then
        panel.lootBox:SetText(self.config.lootPriorityText or "")
    end
    if not panel.namedBox:HasFocus() and panel.namedBox:GetText() ~= (self.config.namedItemsText or "") then
        panel.namedBox:SetText(self.config.namedItemsText or "")
    end

    local session = self:GetCurrentSession()
    local attendeeCount = #(self:GetAttendees() or {})
    local itemCount = #(session.items or {})
    local resultCount = #(session.results or {})
    panel.summary:SetText(string.format(
        "Config revision: %d\nRaid attendees: %d\nSession items: %d\nProcessed results: %d",
        self.config.revision or 0,
        attendeeCount,
        itemCount,
        resultCount
    ))
end
