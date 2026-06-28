-- Unit tests for the preset registry (Core.lua's installPresetRegistry helper). Verifies that
-- the 6 generated methods (GetWhitelist/SaveCustomWhitelist/DeleteCustomWhitelist plus the
-- 3 blacklist counterparts) all behave correctly and identically modulo their data source.
--
-- Run from the addon dir:  luajit tests/unit_preset_registry.lua
-- (or just `luajit tests/run.lua` to run the whole battery).

local F = dofile("tests/_framework.lua").get()
local H = F
F.beginSuite("preset registry unit battery")

local w = H.makeWorld("Masterlooter", true)
local addon = w.addon

------------------------------------------------------------------------
-- Both kinds expose the same method names and return the expected shape.
------------------------------------------------------------------------
H.test("preset registry: both kinds expose Get/Save/Delete methods", function()
    for _, kind in ipairs({ "Whitelist", "Blacklist" }) do
        H.notNil(addon["Get" .. kind .. "Presets"], kind .. " Get method exists")
        H.notNil(addon["SaveCustom" .. kind .. "Preset"], kind .. " Save method exists")
        H.notNil(addon["DeleteCustom" .. kind .. "Preset"], kind .. " Delete method exists")
    end
end)

------------------------------------------------------------------------
-- Built-in blacklist presets are loaded from the Data/BlacklistPresets/*.lua files. With no
-- custom presets saved, GetBlacklistPresets returns ONLY builtins, each with builtin=true.
------------------------------------------------------------------------
H.test("preset registry: GetBlacklistPresets returns builtins from the data files", function()
    local list = addon:GetBlacklistPresets()
    H.check(#list > 0, "at least one blacklist preset is loaded (got " .. tostring(#list) .. ")")
    -- every entry from a data file has builtin=true
    local all_builtin = true
    for _, p in ipairs(list) do
        if p.builtin ~= true then all_builtin = false; break end
    end
    H.check(all_builtin, "all entries are marked builtin=true on a fresh DB")
end)

H.test("preset registry: GetBlacklistPresets includes Priest and Paladin entries", function()
    local list = addon:GetBlacklistPresets()
    local seen = {}
    for _, p in ipairs(list) do seen[p.name] = true end
    H.truthy(seen["Priest"], "Priest preset present")
    H.truthy(seen["Paladin"], "Paladin preset present")
    H.truthy(seen["Warlock"], "Warlock preset present")
end)

------------------------------------------------------------------------
-- GetWhitelistPresets is empty when no custom presets have been saved AND no built-ins ship
-- (current upstream state: addon.whitelistPresets = {}).
------------------------------------------------------------------------
H.test("preset registry: GetWhitelistPresets is empty by default", function()
    local list = addon:GetWhitelistPresets()
    H.eq(#list, 0, "no whitelist presets out of the box")
end)

------------------------------------------------------------------------
-- Save / Delete round-trip on a custom preset. Built-in collision is rejected.
------------------------------------------------------------------------
H.test("preset registry: SaveCustomBlacklistPreset round-trips through GetBlacklistPresets", function()
    local ok = addon:SaveCustomBlacklistPreset("My Test Preset", "Item One\nItem Two\n")
    H.truthy(ok, "Save returns truthy on success")

    local list = addon:GetBlacklistPresets()
    local found
    for _, p in ipairs(list) do
        if p.name == "My Test Preset" then found = p; break end
    end
    H.notNil(found, "saved preset is in the Get list")
    H.eq(found and found.builtin, false, "saved preset has builtin=false")
    H.eq(found and found.text, "Item One\nItem Two\n", "text round-trips verbatim")
end)

H.test("preset registry: SaveCustomBlacklistPreset refuses to overwrite a built-in name", function()
    local ok = addon:SaveCustomBlacklistPreset("Priest", "trying to clobber Priest")
    H.check(not ok, "Save returns falsy when name collides with a built-in")
end)

H.test("preset registry: SaveCustomBlacklistPreset refuses empty name", function()
    H.check(not addon:SaveCustomBlacklistPreset("", "body"), "empty name -> false")
    H.check(not addon:SaveCustomBlacklistPreset(nil, "body"), "nil name -> false")
end)

H.test("preset registry: DeleteCustomBlacklistPreset removes the saved entry", function()
    addon:SaveCustomBlacklistPreset("Doomed Preset", "anything")
    local before = addon:GetBlacklistPresets()
    local n_before = #before
    local ok = addon:DeleteCustomBlacklistPreset("Doomed Preset")
    H.truthy(ok, "Delete returns truthy on success")
    local after = addon:GetBlacklistPresets()
    H.eq(#after, n_before - 1, "list shrinks by one")
end)

H.test("preset registry: DeleteCustomBlacklistPreset refuses missing name", function()
    H.check(not addon:DeleteCustomBlacklistPreset("Nonexistent Preset XYZ"), "missing -> false")
end)

------------------------------------------------------------------------
-- Same round-trip works on the whitelist kind (it had no built-ins to collide with).
------------------------------------------------------------------------
H.test("preset registry: SaveCustomWhitelistPreset round-trips through GetWhitelistPresets", function()
    local ok = addon:SaveCustomWhitelistPreset("My Whitelist", "Item A\n")
    H.truthy(ok, "Save returns truthy")
    local list = addon:GetWhitelistPresets()
    H.eq(#list, 1, "exactly one whitelist preset after Save")
    H.eq(list[1].name, "My Whitelist", "name preserved")
    H.eq(list[1].text, "Item A\n", "text preserved")
end)

H.test("preset registry: whitelist sort is case-insensitive by name", function()
    -- Wipe any saved whitelist presets left over by previous tests so the assertions only see
    -- what this test saves. (Cheap to do here because the test count is low; the SavedVariable
    -- is in-memory only in the harness.)
    addon.db.options = addon.db.options or {}
    addon.db.options.customWhitelistPresets = {}
    addon:SaveCustomWhitelistPreset("banana", "")
    addon:SaveCustomWhitelistPreset("Apple", "")
    addon:SaveCustomWhitelistPreset("cherry", "")
    local list = addon:GetWhitelistPresets()
    local names = {}
    for _, p in ipairs(list) do names[#names + 1] = string.lower(p.name) end
    H.eq(names[1], "apple", "alphabetical first")
    H.eq(names[#names], "cherry", "alphabetical last")
end)

------------------------------------------------------------------------
-- Each kind is independent: saving a blacklist doesn't appear in GetWhitelistPresets, and
-- vice versa. This pins the data-source isolation that's the whole reason for the registry.
------------------------------------------------------------------------
H.test("preset registry: whitelist and blacklist are independent data sources", function()
    addon:SaveCustomWhitelistPreset("WL Only", "")
    addon:SaveCustomBlacklistPreset("BL Only", "")
    local wl = addon:GetWhitelistPresets()
    local bl = addon:GetBlacklistPresets()
    local wl_names, bl_names = {}, {}
    for _, p in ipairs(wl) do wl_names[p.name] = true end
    for _, p in ipairs(bl) do bl_names[p.name] = true end
    H.truthy(wl_names["WL Only"], "WL saved preset is in WL list")
    H.check(not bl_names["WL Only"], "WL saved preset is NOT in BL list")
    H.truthy(bl_names["BL Only"], "BL saved preset is in BL list")
    H.check(not wl_names["BL Only"], "BL saved preset is NOT in WL list")
end)

F.endSuite()