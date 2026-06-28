-- UI-load smoke suite. The harness normally skips UI.lua (heavy FrameXML, irrelevant to loot
-- accounting), so a refactor that splits UI into modules could silently leave a method referencing
-- an out-of-scope file-local and nothing would catch it until in-game. This suite loads every UI
-- file into the mocked env and proves the presentation layer loads, InitializeUI builds the window,
-- and every tab build/refresh runs without error on an empty session.
--
-- Run from the addon dir:  luajit tests/unit_uiload.lua

local F = dofile("tests/_framework.lua").get()
local H = F
F.beginSuite("ui load smoke battery")

local function uiWorld()
    local w = F.makeWorld("UISmoke", true)
    F.loadUI(w)
    return w
end

H.test("UI files load and define the expected entry points", function()
    local w = uiWorld()
    local expected = {
        "InitializeUI", "RefreshUI", "SelectTab", "ToggleMainFrame",
        "BuildLootTab", "BuildRaidersTab", "BuildResultsTab", "BuildMasterTab", "BuildOptionsTab",
        "RefreshLootTab", "RefreshRaidersTab", "RefreshResultsTab", "RefreshMasterTab", "RefreshOptionsTab",
    }
    for _, m in ipairs(expected) do
        H.eq(type(w.addon[m]), "function", m .. " is defined")
    end
end)

H.test("InitializeUI builds the window without error", function()
    local w = uiWorld()
    w.addon:InitializeUI()
    H.notNil(w.addon.ui, "addon.ui created")
end)

H.test("RefreshUI and SelectTab run across every tab on an empty session", function()
    local w = uiWorld()
    w.addon:InitializeUI()
    w.addon:RefreshUI()
    for _, tab in ipairs({ "loot", "results", "raiders", "master", "options" }) do
        w.addon:SelectTab(tab)
    end
    H.check(true, "no error through RefreshUI + SelectTab across all tabs")
end)

-- UI/Export.lua: the extracted export/import block. Defined + runnable means its re-localize header
-- resolved the shared widgets it needs from addon.UI.
H.test("export/import entry points are defined and run", function()
    local w = uiWorld()
    for _, m in ipairs({ "ExportWinners", "ExportLog", "BuildWinnersExportText", "BuildDetailedExportLogText", "ImportRoster", "ImportNamedItems" }) do
        H.eq(type(w.addon[m]), "function", m .. " is defined")
    end
    w.addon:InitializeUI()
    w.addon:ExportWinners()
    w.addon:ExportLog()
    H.check(true, "ExportWinners + ExportLog build their windows without error")
end)

-- UI/Minimap.lua: the extracted minimap button + owed-loot glow.
H.test("minimap entry points are defined and run", function()
    local w = uiWorld()
    for _, m in ipairs({ "BuildMinimapButton", "UpdateMinimapOwedGlow", "SetMinimapButtonShown", "CountLootOwedToMe" }) do
        H.eq(type(w.addon[m]), "function", m .. " is defined")
    end
    w.addon:InitializeUI()
    w.addon:BuildMinimapButton()
    w.addon:UpdateMinimapOwedGlow()
    w.addon:SetMinimapButtonShown(true)
    H.check(true, "minimap build + glow + toggle run without error")
end)

F.endSuite()
