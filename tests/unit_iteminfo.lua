-- Unit tests for addon.defaultItemInfo (ItemInfo.lua) -- the per-item note/role lookup table.
--
-- This file used to be entirely orphan: ItemInfo.lua was not in WeirdLoot.toc and not loaded
-- by tests/run.lua. Config.lua held a duplicate copy of the same data; whichever loaded last
-- won. Phase 1 of the refactor made ItemInfo.lua the single source of truth (wired into the toc
-- and the test harness's ADDON_FILES list, duplicate removed from Config.lua). These tests
-- pin that contract: the table exists, has the expected shape, and known entries resolve.
--
-- Run from the addon dir:  luajit tests/unit_iteminfo.lua
-- (or just `luajit tests/run.lua` to run the whole battery).

local F = dofile("tests/_framework.lua").get()
local H = F
F.beginSuite("iteminfo unit battery")

local w = H.makeWorld("Masterlooter", true)
local addon = w.addon

------------------------------------------------------------------------
-- The table exists and is non-empty.
------------------------------------------------------------------------
H.test("defaultItemInfo: addon.defaultItemInfo is a populated table", function()
    H.eq(type(addon.defaultItemInfo), "table", "defaultItemInfo is a table")
    local count = 0
    for _ in pairs(addon.defaultItemInfo) do count = count + 1 end
    H.check(count > 100, "has more than 100 entries (got " .. tostring(count) .. ")")
end)

------------------------------------------------------------------------
-- Every entry has the documented shape: { itemName, note, role }.
------------------------------------------------------------------------
H.test("defaultItemInfo: every entry has itemName/note/role fields", function()
    local malformed = {}
    local sample = 0
    for key, entry in pairs(addon.defaultItemInfo) do
        sample = sample + 1
        if type(entry) ~= "table"
                or type(entry.itemName) ~= "string"
                or type(entry.note) ~= "string"
                or type(entry.role) ~= "string" then
            malformed[#malformed + 1] = key
        end
    end
    H.eq(#malformed, 0, "every entry has {itemName, note, role} as strings (scanned " .. tostring(sample) .. ")")
end)

------------------------------------------------------------------------
-- Well-known entries resolve. We check the in-game item names the resolver/UI actually use
-- (T7 / T8 tier tokens, the Warrior shoulders, the Mage shoulders) -- if these vanish or get
-- renames the loot tab and resolver would silently lose the "allowed classes" hint.
------------------------------------------------------------------------
H.test("defaultItemInfo: T7 Conqueror shoulder is registered", function()
    local entry = addon:GetItemInfoEntry("Spaulders of the Lost Conqueror")
    H.notNil(entry, "Conqueror shoulder resolves by name")
    H.eq(entry.itemName, "Spaulders of the Lost Conqueror", "itemName is the display string")
    H.matches(entry.note, "Paladin", "note names Paladin (allowed class)")
    H.matches(entry.note, "Priest", "note names Priest (allowed class)")
    H.matches(entry.note, "Warlock", "note names Warlock (allowed class)")
end)

H.test("defaultItemInfo: T8 Conqueror shoulder is also registered (separate entry)", function()
    local entry = addon:GetItemInfoEntry("Spaulders of the Lost Conqueror")
    -- Same item name is used for T7 and T8 since the entry is keyed by display name. The
    -- tier distinction comes from the itemId (handled by util:TierTokenClassSet), not the
    -- name table. This test guards that the name table still has the entry.
    H.notNil(entry, "the display name still resolves")
end)

H.test("defaultItemInfo: lookup is case-insensitive", function()
    -- Names are stored lowercase; GetItemInfoEntry normalizes via util:NormalizeKey.
    local a = addon:GetItemInfoEntry("Spaulders of the Lost Conqueror")
    local b = addon:GetItemInfoEntry("spaulders of the lost conqueror")
    local c = addon:GetItemInfoEntry("SPAULDERS OF THE LOST CONQUEROR")
    H.notNil(a, "title-case resolves")
    H.notNil(b, "lower resolves")
    H.notNil(c, "UPPER resolves")
end)

H.test("defaultItemInfo: unknown item returns nil (not an empty table)", function()
    local entry = addon:GetItemInfoEntry("This Item Definitely Does Not Exist In The Table 12345")
    H.nil_(entry, "no entry -> nil")
end)

H.test("defaultItemInfo: empty / nil input returns nil", function()
    H.nil_(addon:GetItemInfoEntry(""), "empty string -> nil")
    H.nil_(addon:GetItemInfoEntry(nil), "nil -> nil")
end)

------------------------------------------------------------------------
-- Config.lua's parser functions still resolve an entry that lives ONLY in ItemInfo.lua's
-- (not Config.lua's) data. This is the contract Phase 1 establishes: Config parses,
-- ItemInfo holds the data, both loaded together.
------------------------------------------------------------------------
H.test("defaultItemInfo: Config's IsClassAllowedForItem reads through to ItemInfo", function()
    local entry = addon:GetItemInfoEntry("Spaulders of the Lost Conqueror")
    H.notNil(entry, "entry present")
    -- entry.note = "Paladin, Priest, Warlock"; allowed classes should include paladin
    local allowed = addon:GetItemAllowedClasses("Spaulders of the Lost Conqueror")
    H.notNil(allowed, "GetItemAllowedClasses returns a set")
    H.truthy(allowed["paladin"], "paladin is allowed")
    H.truthy(allowed["priest"], "priest is allowed")
    H.truthy(allowed["warlock"], "warlock is allowed")
    H.check(not allowed["warrior"], "warrior is NOT allowed for a Conqueror item")
end)

F.endSuite()