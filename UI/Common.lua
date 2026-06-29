local addon = WeirdLoot
local UI = addon.UI

local createLabel = UI.createLabel
local createButton = UI.createButton
local createMultilineEditScroll = UI.createMultilineEditScroll
local elevateInteractiveFrame = UI.elevateInteractiveFrame
local getOptions = UI.getOptions

-- Shared builder for the Options tab's whitelist/blacklist preset managers. The two are identical apart
-- from the list they read/write, so everything is derived from `kind` ("whitelist"/"blacklist"): the
-- dropdown frame name, the Save/Delete popup ids, the GetXPresets getter, the saved option fields
-- (xText / xPresetName), and the addon:RefreshXPresetDropdown method. `anchorCB` is the checkbox the
-- "Preset:" label sits under; opts.note (optional) inserts a curated-presets caption between the dropdown
-- and the edit box. Returns the multiline edit box so the caller can anchor following widgets to it.
function UI.createPresetManager(panel, kind, anchorCB, opts)
    opts = opts or {}
    local cap          = kind:sub(1, 1):upper() .. kind:sub(2)   -- "Whitelist" / "Blacklist"
    local UPPER        = kind:upper()
    local dropdownName = "WeirdLoot" .. cap .. "PresetDropdown"
    local textField    = kind .. "Text"
    local nameField    = kind .. "PresetName"
    local function getPresets() return addon["Get" .. cap .. "Presets"](addon) end

    local presetLabel = createLabel(panel, "Preset:", "TOPLEFT", anchorCB, "BOTTOMLEFT", 4, -10)
    local presetDropdown = CreateFrame("Frame", dropdownName, panel, "UIDropDownMenuTemplate")
    elevateInteractiveFrame(presetDropdown, panel, 10)
    presetDropdown:SetPoint("LEFT", presetLabel, "RIGHT", -4, -2)
    UIDropDownMenu_SetWidth(presetDropdown, 160)
    UIDropDownMenu_JustifyText(presetDropdown, "LEFT")
    if UIDropDownMenu_EnableDropDown then
        UIDropDownMenu_EnableDropDown(presetDropdown)
    end
    local ddButton = _G[dropdownName .. "Button"]
    if ddButton then
        ddButton:SetFrameLevel((presetDropdown:GetFrameLevel() or 0) + 2)
        ddButton:Enable()
    end

    local saveBtn = createButton(panel, "Save as...", 80, 22)
    saveBtn:SetPoint("LEFT", presetDropdown, "RIGHT", 4, 2)
    saveBtn:SetScript("OnClick", function()
        StaticPopup_Show("WEIRDLOOT_SAVE_" .. UPPER .. "_PRESET")
    end)

    local deleteBtn = createButton(panel, "Delete", 60, 22)
    deleteBtn:SetPoint("LEFT", saveBtn, "RIGHT", 4, 0)
    deleteBtn:Disable()

    -- The edit box hangs under the dropdown, or under the optional curated note when one is present.
    local boxAnchor, boxX, boxY = presetDropdown, 16, -2
    if opts.note then
        local note = createLabel(panel, opts.note, "TOPLEFT", presetDropdown, "BOTTOMLEFT", 16, -6)
        note:SetWidth(560)
        note:SetJustifyH("LEFT")
        note:SetTextColor(0.85, 0.85, 0.85)
        boxAnchor, boxX, boxY = note, 0, -6
    end

    local box = createMultilineEditScroll(panel, 420, 110)
    box:SetPoint("TOPLEFT", boxAnchor, "BOTTOMLEFT", boxX, boxY)
    box.editBox:SetText(getOptions(addon)[textField] or "")
    box.editBox:SetScript("OnEditFocusLost", function(selfBox)
        addon:SetItemFilterText(kind, selfBox:GetText())
    end)

    -- Show a preset name in the dropdown and set the delete button for it WITHOUT touching the items;
    -- used both for a live selection and to restore the remembered name on load.
    local function showSelectedPreset(name)
        if not name or name == "" or name == "<none>" then
            UIDropDownMenu_SetText(presetDropdown, "<none>")
            deleteBtn.currentPresetName = nil
            deleteBtn:Disable()
            return
        end
        local builtin = true
        for _, p in ipairs(getPresets()) do
            if p.name == name then builtin = p.builtin; break end
        end
        UIDropDownMenu_SetText(presetDropdown, name)
        deleteBtn.currentPresetName = name
        deleteBtn.currentPresetBuiltin = builtin
        if builtin then deleteBtn:Disable() else deleteBtn:Enable() end
    end

    local function applyPreset(preset)
        if not preset then
            showSelectedPreset(nil)
            getOptions(addon)[nameField] = nil
            return
        end
        box.editBox:SetText(preset.text or "")
        addon:SetItemFilterText(kind, preset.text)
        -- Remember the chosen name across reloads; never re-apply its items on load (the saved text is
        -- authoritative and may have been edited since). The name is purely a "what I last picked" label.
        local chosen = preset.isNone and nil or preset.name
        getOptions(addon)[nameField] = chosen
        showSelectedPreset(chosen)
    end

    local function initDropdown()
        local noneInfo = UIDropDownMenu_CreateInfo()
        noneInfo.text = "<none>"
        noneInfo.value = ""
        noneInfo.func = function() applyPreset({ name = "<none>", text = "", builtin = true, isNone = true }) end
        UIDropDownMenu_AddButton(noneInfo)
        for _, preset in ipairs(getPresets()) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = preset.builtin and preset.name or (preset.name .. " (custom)")
            info.value = preset.name
            info.func = function() applyPreset(preset) end
            UIDropDownMenu_AddButton(info)
        end
    end
    UIDropDownMenu_Initialize(presetDropdown, initDropdown)
    showSelectedPreset(getOptions(addon)[nameField])

    deleteBtn:SetScript("OnClick", function()
        local name = deleteBtn.currentPresetName
        if not name or deleteBtn.currentPresetBuiltin then return end
        local dialog = StaticPopup_Show("WEIRDLOOT_DELETE_" .. UPPER .. "_PRESET", name)
        if dialog then dialog.data = name end
    end)

    addon["Refresh" .. cap .. "PresetDropdown"] = function(self, selectName)
        UIDropDownMenu_Initialize(presetDropdown, initDropdown)
        if selectName then
            for _, preset in ipairs(getPresets()) do
                if preset.name == selectName then
                    applyPreset(preset)
                    return
                end
            end
        end
        applyPreset(nil)
    end

    return box
end
