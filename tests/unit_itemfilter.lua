-- Unit + property tests for the cached whitelist/blacklist roll-popup filter (LiveRoll.lua):
-- RefreshItemFilters / SetItemFilterText and ShouldSuppressRollPopup reading the cached name sets.
--
-- The text filter (whitelist/blacklist) had NO coverage before caching was added, so this suite pins
-- both the behavior (suppress iff name is on the list, case/space-insensitive; ML exempt) AND the
-- caching contract: the set is built once and only changes through SetItemFilterText, never re-parsed
-- per check. The "stale cache" test proves the per-popup re-parse is actually gone.
--
-- Run from the addon dir:  luajit tests/unit_itemfilter.lua

local F = dofile("tests/_framework.lua").get()
local H = F
F.beginSuite("item-filter (whitelist/blacklist) battery")

local makeWorld = F.makeWorld

-- a non-ML raider with the class-usability filter off, so only the text filter is in play
local function raider()
    local w = makeWorld("Raider", false)
    local opt = w.addon.db.options
    opt.hideUnusableRolls = false
    opt.whitelistEnabled = false
    opt.blacklistEnabled = false
    return w, opt
end

local function suppress(w, name)
    return w.addon:ShouldSuppressRollPopup({ itemId = 1, name = name })
end

-- reference parse mirroring LiveRoll.parseItemList (split on \r\n, trim, lowercase, drop empties)
local function refSet(text)
    local set = {}
    for line in string.gmatch(text or "", "[^\r\n]+") do
        local t = string.match(line, "^%s*(.-)%s*$") or ""
        if t ~= "" then set[string.lower(t)] = true end
    end
    return set
end

-- ---------------------------------------------------------------------------
-- behavior
-- ---------------------------------------------------------------------------
H.test("blacklist: suppresses listed items, shows unlisted (non-ML)", function()
    local w, opt = raider()
    opt.blacklistEnabled = true
    w.addon:SetItemFilterText("blacklist", "Wand\nSword")
    H.eq(suppress(w, "Wand"), true, "listed item suppressed")
    H.eq(suppress(w, "Sword"), true, "second listed item suppressed")
    H.eq(suppress(w, "Shield"), false, "unlisted item shown")
end)

H.test("blacklist: matching is case- and whitespace-insensitive", function()
    local w, opt = raider()
    opt.blacklistEnabled = true
    w.addon:SetItemFilterText("blacklist", "   wAnD   ")
    H.eq(suppress(w, "WAND"), true, "case-folded + trimmed match")
end)

H.test("whitelist: non-empty list hides anything off it; empty list hides nothing", function()
    local w, opt = raider()
    opt.whitelistEnabled = true
    w.addon:SetItemFilterText("whitelist", "Wand")
    H.eq(suppress(w, "Wand"), false, "whitelisted item shown")
    H.eq(suppress(w, "Sword"), true, "non-whitelisted item suppressed")
    w.addon:SetItemFilterText("whitelist", "")
    H.eq(suppress(w, "Sword"), false, "empty whitelist suppresses nothing")
end)

H.test("ML is never suppressed by the text filter", function()
    local ml = makeWorld("Masterlooter", true)
    ml.addon.db.options.hideUnusableRolls = false
    ml.addon.db.options.blacklistEnabled = true
    ml.addon:SetItemFilterText("blacklist", "Wand")
    H.eq(ml.addon:ShouldSuppressRollPopup({ itemId = 1, name = "Wand" }), false, "ML sees a blacklisted item")
end)

-- ---------------------------------------------------------------------------
-- caching contract
-- ---------------------------------------------------------------------------
H.test("RefreshItemFilters builds both sets from current option text", function()
    local w, opt = raider()
    opt.blacklistEnabled = true
    opt.blacklistText = "Wand\nSword"        -- set directly, then explicit refresh (the init path)
    w.addon:RefreshItemFilters()
    H.eq(suppress(w, "Wand"), true, "Wand from refreshed set")
    H.eq(suppress(w, "Shield"), false, "Shield not listed")
end)

H.test("cache is reused, not re-parsed: a direct opt edit is invisible until rebuilt", function()
    local w, opt = raider()
    opt.blacklistEnabled = true
    w.addon:SetItemFilterText("blacklist", "Wand")
    H.eq(suppress(w, "Wand"), true, "Wand suppressed after set")

    -- bypass the setter and poke the raw option text. If ShouldSuppressRollPopup still re-parsed on
    -- every call this would take effect immediately; with the cache it must NOT.
    opt.blacklistText = "Sword"
    H.eq(suppress(w, "Wand"), true, "stale cache still suppresses Wand (no per-check re-parse)")
    H.eq(suppress(w, "Sword"), false, "stale cache does not yet see the direct edit")

    -- the supported mutation path rebuilds the set
    w.addon:SetItemFilterText("blacklist", "Sword")
    H.eq(suppress(w, "Sword"), true, "Sword suppressed after SetItemFilterText")
    H.eq(suppress(w, "Wand"), false, "Wand no longer suppressed")
end)

-- ---------------------------------------------------------------------------
-- property: suppression matches set membership over random lists/queries
-- ---------------------------------------------------------------------------
H.test("blacklist property: suppress(name) iff lowercased/trimmed name is on the list", function()
    local w, opt = raider()
    opt.blacklistEnabled = true
    math.randomseed(13371337)
    for _ = 1, 300 do
        local lines = {}
        for _ = 1, math.random(0, 8) do
            local base = "Item " .. math.random(1, 12)
            local cased = (math.random(0, 1) == 1) and string.upper(base) or base
            lines[#lines + 1] = (math.random(0, 1) == 1) and ("  " .. cased .. "  ") or cased
        end
        local text = table.concat(lines, "\n")
        w.addon:SetItemFilterText("blacklist", text)
        local ref = refSet(text)
        for q = 1, 12 do
            local query = "Item " .. q
            H.eq(suppress(w, query), ref[string.lower(query)] == true,
                 "suppress matches membership for " .. query)
        end
        H.eq(suppress(w, "Definitely Absent"), false, "absent name never suppressed")
    end
end)

F.endSuite()
