-- Out-of-game test battery for WeirdLoot's LootCore migration.
-- Loads the REAL addon files into mocked WoW environments (one per simulated client via
-- setfenv) and drives end-to-end flows: bag reconcile, live rolls, top-N resolution,
-- the stale-roll regression, payout owes, per-copy delivery, and ML->raider snapshot sync.
--
-- Run from the addon dir:  luajit tests/run.lua
--
-- The bag/tooltip scan is monkeypatched (we inject eligible counts directly), so we never
-- need GameTooltip line scraping; everything else runs the actual addon code.

-- UI.lua is intentionally omitted: it is pure presentation and pulls in heavy FrameXML
-- (FauxScrollFrame_*, templates) irrelevant to loot accounting. The projections the tests
-- assert on (session.items / session.results) are built in Session, not UI.
local ADDON_FILES = {
    "TradeDeliver.lua", "Core.lua", "LootCore.lua", "Util.lua", "Config.lua",
    "Roster.lua", "Session.lua", "Comm.lua", "Resolver.lua", "Payout.lua",
    "LiveRoll.lua", "AutoLoot.lua",
}

-- ---------------------------------------------------------------------------
-- tiny test framework
-- ---------------------------------------------------------------------------
local pass, fail, failures = 0, 0, {}
local current = "?"
local function check(cond, label)
    if cond then pass = pass + 1
    else fail = fail + 1; failures[#failures + 1] = current .. ": " .. label; print("  FAIL " .. label) end
end
local function eq(a, b, label) check(a == b, (label or "") .. " (got " .. tostring(a) .. ", want " .. tostring(b) .. ")") end
local function test(name, fn)
    current = name
    print("[" .. name .. "]")
    local ok, err = pcall(fn)
    if not ok then fail = fail + 1; failures[#failures + 1] = name .. ": ERROR " .. tostring(err); print("  ERROR " .. tostring(err)) end
end

-- ---------------------------------------------------------------------------
-- shared wire (AceComm transport) between simulated clients
-- ---------------------------------------------------------------------------
local WIRE = {}        -- queue of { prefix, msg, dist, target, sender }
local CLOCK = 1000     -- controllable GetTime()/time()

-- ---------------------------------------------------------------------------
-- universal frame mock: any method is a chainable no-op returning the frame, so the
-- addon's frame construction (Initialize* / popups / UI) loads without a real client.
-- We never fire OnUpdate/OnClick, so return values from getters are never math'd on.
-- ---------------------------------------------------------------------------
local frameMT
frameMT = {
    __index = function(_, k)
        return function(self) return self end
    end,
}
local function newFrame() return setmetatable({}, frameMT) end

-- ---------------------------------------------------------------------------
-- a fake fixed item database: itemId -> name. Links embed the itemId (3.3.5 format).
-- ---------------------------------------------------------------------------
local ITEMS = {
    [40001] = "Mantle of Test", [40002] = "Helm of Test", [40003] = "Ring of Test",
    [40004] = "Token of Test",  [40005] = "Blade of Test",
}
local function linkFor(itemId) return "|cffa335ee|Hitem:" .. itemId .. ":0:0:0:0:0:0:0|h[" .. (ITEMS[itemId] or ("Item" .. itemId)) .. "]|h|r" end

-- ---------------------------------------------------------------------------
-- build a fresh mocked environment + load the addon into it
-- ---------------------------------------------------------------------------
local function makeWorld(playerName, isML)
    local env = setmetatable({}, { __index = _G })
    env._G = env

    -- deterministic-ish rng (seeded per world); resolution asserts are invariant-based anyway
    local seed = 0
    for i = 1, #playerName do seed = seed + string.byte(playerName, i) end
    local function rng(m, n)
        seed = (seed * 1103515245 + 12345) % 2147483648
        local r = seed / 2147483648
        if m and n then return m + math.floor(r * (n - m + 1)) end
        return r
    end

    -- ---- WoW API stubs ----
    env.CreateFrame = function(_, name) local f = newFrame(); if name then env[name] = f end; return f end
    env.UIParent = newFrame()
    env.WorldFrame = newFrame()
    env.GameTooltip = newFrame()
    env.DEFAULT_CHAT_FRAME = setmetatable({ AddMessage = function() end }, { __index = function() return function() end end })
    env.GetTime = function() return CLOCK end
    env.time = function() return CLOCK end
    env.random = rng
    env.randomseed = function() end
    env.math = setmetatable({ random = rng }, { __index = math })
    env.UnitName = function(unit) if unit == "player" then return playerName end return playerName end
    env.GetUnitName = function() return playerName end
    env.UnitGUID = function() return "Player-0-000000" .. tostring(#playerName) end
    env.GetRealmName = function() return "TestRealm" end
    env.UnitClass = function() return "Warrior", "WARRIOR" end
    env.GetNumRaidMembers = function() return 5 end
    env.GetNumPartyMembers = function() return 0 end
    env.GetRaidRosterInfo = function() return playerName, (isML and 2 or 0) end
    env.GetLootMethod = function() return "master", 0, 1 end
    env.IsPartyLeader = function() return isML end
    env.SendChatMessage = function() end
    env.SendAddonMessage = function() end
    env.ChatThrottleLib = { SendChatMessage = function() end }
    env.ITEM_QUALITY_COLORS = { [4] = { hex = "|cffa335ee" } }
    env.ITEM_SOULBOUND = "Soulbound"
    env.ITEM_BIND_ON_EQUIP = "Binds when equipped"
    env.ERR_TRADE_COMPLETE = "Trade complete."
    env.UI_INFO_MESSAGE = "UI_INFO_MESSAGE"
    env.MAX_TRADABLE_ITEMS = 6
    env.CloseTrade = function() end
    env.AcceptTrade = function() end
    env.GetTradePlayerItemLink = function() end
    env.GetItemInfo = function(idOrLink)
        local id = tonumber(idOrLink) or tonumber(string.match(tostring(idOrLink), "item:(%d+)"))
        if not id then return nil end
        local name = ITEMS[id] or ("Item" .. id)
        -- name, link, quality, ilvl, reqLevel, class, subclass, stack, equipLoc, texture, sell
        return name, linkFor(id), 4, 200, 80, "Armor", "Cloth", 1, "INVTYPE_SHOULDER", "Interface\\Icons\\inv_test", 0
    end
    env.GetContainerNumSlots = function() return 0 end
    env.GetContainerItemLink = function() return nil end
    env.GetContainerItemInfo = function() return nil end
    env.SlashCmdList = {}
    env.StaticPopupDialogs = {}
    env.StaticPopup_Show = function() return newFrame() end
    env.StaticPopup_Hide = function() end
    env.PlaySound = function() end
    env.GetContainerItemID = function() return nil end
    env.IsInInstance = function() return false, "none" end
    env.GetInstanceInfo = function() return "none", "none" end
    env.InCombatLockdown = function() return false end

    -- ---- LibStub + libs (AceComm fake routes to the shared WIRE) ----
    local libs = {}
    local aceComm = {
        Embed = function(_, target)
            target.SendCommMessage = function(_, prefix, msg, dist, tgt)
                WIRE[#WIRE + 1] = { prefix = prefix, msg = msg, dist = dist, target = tgt, sender = playerName }
            end
            target.RegisterComm = function() end
        end,
    }
    libs["AceComm-3.0"] = aceComm
    libs["CallbackHandler-1.0"] = { New = function() return {} end }
    local LibStub = setmetatable({
        NewLibrary = function(_, name) libs[name] = libs[name] or {}; return libs[name] end,
        GetLibrary = function(_, name) return libs[name] end,
    }, { __call = function(_, name) return libs[name] end })
    env.LibStub = LibStub

    -- ---- load the addon files into this env ----
    local private = {}
    for _, file in ipairs(ADDON_FILES) do
        local chunk = assert(loadfile(file))
        setfenv(chunk, env)
        chunk("WeirdLoot", private)
    end

    local addon = env.WeirdLoot
    addon.InitializeUI = function() end       -- UI not loaded in the harness
    addon:PLAYER_LOGIN()

    -- ---- force the loot-authority + scan into a deterministic test state ----
    addon.roster = addon.roster or {}
    addon.roster.isLootMaster = isML
    addon.roster.lootMasterName = "Masterlooter"
    addon.lootCore:SetML("Masterlooter")
    addon.bagSettleAt = 0                     -- bags considered settled
    addon.db.autoRoll = true

    -- inject eligible bag counts directly (skip tooltip scraping)
    addon.__bag = {}                          -- itemId -> count (test-controlled)
    local function bagLinkCounts(self)
        local out = {}
        for id, n in pairs(self.__bag) do if n > 0 then out[linkFor(id)] = n end end
        return out
    end
    addon.BuildTradeableEpicCounts = bagLinkCounts
    addon.BuildBagSnapshot = bagLinkCounts
    addon.BuildManualScanCounts = bagLinkCounts

    -- give every responder a 'main' roster profile so resolution is pure roll (no status cut).
    -- Responses are keyed by normalized (lowercase) name; the real roster maps that back to a
    -- display name, so we capitalize here to mirror that (winners come out proper-cased).
    local function cap(s) return (tostring(s):gsub("^%l", string.upper)) end
    addon.GetRosterProfile = function(_, name) return { name = cap(name), className = "Warrior", specName = "Arms", status = "main" } end
    addon.GetAttendee = function(_, name) return { name = cap(name), className = "Warrior", specName = "Arms", status = "main" } end
    addon.GetAttendees = function() return {} end

    return { addon = addon, env = env, player = playerName }
end

-- ---------------------------------------------------------------------------
-- helpers to drive a world
-- ---------------------------------------------------------------------------
local function setBag(w, itemId, count) w.addon.__bag[itemId] = count end
local function bagUpdate(w) w.addon:OnBagUpdate() end

local function startSession(w)
    w.addon:StartLootSession()
end

local function lotsFor(w, itemId) return w.addon.lootCore:lotsForItem(itemId) end
local function openLot(w, itemId) return w.addon.lootCore:openLotForItem(itemId) end

local function owedCount(w)
    local n = 0
    local owed = w.addon.payout and w.addon.payout.db and w.addon.payout.db.owed or {}
    for _, entry in pairs(owed) do for _, it in ipairs(entry.items or {}) do n = n + (it.count or 0) end end
    return n
end

-- deliver the shared wire from one world to another (raider mirror)
local function flushWireTo(target, fromSender)
    local msgs = WIRE; WIRE = {}
    for _, m in ipairs(msgs) do
        if m.sender ~= target.player then
            target.addon:OnCommReceived(m.prefix, m.msg, m.dist or "RAID", m.sender or fromSender or "Masterlooter")
        end
    end
end
local function clearWire() WIRE = {} end

-- ===========================================================================
-- BATTERY
-- ===========================================================================

test("core self-checks (in-harness)", function()
    local w = makeWorld("Masterlooter", true)
    check(w.addon.LootCore.RunSelfChecks(false), "all core self-checks pass")
end)

test("session start baselines existing loot as idle (no auto-roll)", function()
    local w = makeWorld("Masterlooter", true)
    setBag(w, 40001, 1)             -- already carrying one before the session
    startSession(w)
    local lot = openLot(w, 40001)
    check(lot ~= nil, "baseline lot minted")
    eq(lot and lot.state, "idle", "pre-existing loot is idle, not surfaced")
    check(w.addon.lootCore:State(lot.id) ~= "pending", "not auto-surfaced")
end)

test("fresh drop mints a NEW lot and auto-surfaces (pending)", function()
    local w = makeWorld("Masterlooter", true)
    startSession(w)
    setBag(w, 40002, 1)
    bagUpdate(w)
    local lot = openLot(w, 40002)
    check(lot ~= nil, "fresh lot minted")
    eq(lot and lot.state, "pending", "fresh drop auto-surfaced to pending")
    eq(#w.addon.session.items, 1, "projection has one item")
    eq(w.addon.session.items[1].itemId, 40002, "projection itemId from link")
end)

test("pre-roll duplicate grows the open lot (one row, quantity 2)", function()
    local w = makeWorld("Masterlooter", true)
    startSession(w)
    setBag(w, 40002, 1); bagUpdate(w)
    setBag(w, 40002, 2); bagUpdate(w)
    eq(#lotsFor(w, 40002), 1, "still a single lot")
    eq(openLot(w, 40002).count, 2, "lot count grew to 2")
    eq(w.addon.session.items[1].quantity, 2, "projection quantity 2")
end)

test("live roll: single copy, two rollers -> one owed winner + payout", function()
    local w = makeWorld("Masterlooter", true)
    startSession(w)
    setBag(w, 40005, 1); bagUpdate(w)
    local lot = openLot(w, 40005)
    w.addon:StartLiveRoll(lot.id)
    eq(w.addon.lootCore:State(lot.id), "rolling", "lot is rolling")
    w.addon:RegisterInterest(lot.id, "Alice", "ms")
    w.addon:RegisterInterest(lot.id, "Bob", "ms")
    w.addon:ResolveLiveRoll(lot.id)
    local L = w.addon.lootCore:Get(lot.id)
    eq(L.state, "resolved", "lot resolved")
    eq(#L.awards, 1, "one award for a 1x lot")
    eq(L.awards[1].state, "owed", "winner is owed (non-ML)")
    check(L.awards[1].winner == "Alice" or L.awards[1].winner == "Bob", "winner is one of the rollers")
    eq(owedCount(w), 1, "payout owes exactly one item")
end)

test("top-N: 2x drop, 3 rollers -> 2 distinct owed winners", function()
    local w = makeWorld("Masterlooter", true)
    startSession(w)
    setBag(w, 40004, 2); bagUpdate(w)
    local lot = openLot(w, 40004)
    eq(lot.count, 2, "lot count 2")
    w.addon:StartLiveRoll(lot.id)
    w.addon:RegisterInterest(lot.id, "Alice", "ms")
    w.addon:RegisterInterest(lot.id, "Bob", "ms")
    w.addon:RegisterInterest(lot.id, "Cara", "ms")
    w.addon:ResolveLiveRoll(lot.id)
    local L = w.addon.lootCore:Get(lot.id)
    eq(#L.awards, 2, "two awards")
    eq(L.awards[1].state, "owed", "award 1 owed")
    eq(L.awards[2].state, "owed", "award 2 owed")
    local a, b = L.awards[1].winner, L.awards[2].winner
    check(a ~= b, "the two winners are distinct")
    local pool = { Alice = true, Bob = true, Cara = true }
    check(pool[a] and pool[b], "both winners are rollers")
    eq(owedCount(w), 2, "payout owes two items")
end)

test("top-N surplus: 2x drop, 1 roller -> 1 owed + 1 no-winner kept", function()
    local w = makeWorld("Masterlooter", true)
    startSession(w)
    setBag(w, 40004, 2); bagUpdate(w)
    local lot = openLot(w, 40004)
    w.addon:StartLiveRoll(lot.id)
    w.addon:RegisterInterest(lot.id, "Alice", "ms")
    w.addon:ResolveLiveRoll(lot.id)
    local L = w.addon.lootCore:Get(lot.id)
    eq(#L.awards, 2, "two awards")
    eq(L.awards[1].winner, "Alice", "the sole roller wins one")
    eq(L.awards[1].state, "owed", "that copy is owed")
    eq(L.awards[2].winner, nil, "surplus copy has no winner")
    eq(L.awards[2].state, "resolved", "ML keeps the surplus copy")
    eq(owedCount(w), 1, "payout owes only the won copy")
end)

test("self-win stays resolved, not owed (no payout)", function()
    local w = makeWorld("Masterlooter", true)
    startSession(w)
    setBag(w, 40003, 1); bagUpdate(w)
    local lot = openLot(w, 40003)
    w.addon:StartLiveRoll(lot.id)
    w.addon:RegisterInterest(lot.id, "Masterlooter", "ms")  -- the ML rolls and is the only roller
    w.addon:ResolveLiveRoll(lot.id)
    local L = w.addon.lootCore:Get(lot.id)
    eq(L.awards[1].winner, "Masterlooter", "ML won")
    eq(L.awards[1].state, "resolved", "self-win is resolved, not owed")
    eq(owedCount(w), 0, "no payout owed for self-win")
end)

test("stale-roll regression: re-drop after resolve is a fresh lot, no bleed", function()
    local w = makeWorld("Masterlooter", true)
    startSession(w)
    setBag(w, 40001, 1); bagUpdate(w)
    local lot1 = openLot(w, 40001)
    w.addon:StartLiveRoll(lot1.id)
    w.addon:RegisterInterest(lot1.id, "Alice", "ms")
    w.addon:ResolveLiveRoll(lot1.id)
    local first = w.addon.lootCore:Get(lot1.id)
    eq(first.state, "resolved", "first lot resolved")
    local firstWinner = first.awards[1].winner
    -- winner keeps it; a NEW identical copy drops (bag now shows 2 of the item)
    setBag(w, 40001, 2); bagUpdate(w)
    eq(#lotsFor(w, 40001), 2, "a NEW lot is minted, not the resolved one reused")
    local fresh = openLot(w, 40001)
    check(fresh.id ~= lot1.id, "fresh lot has a new id")
    eq(next(fresh.responses), nil, "fresh lot has empty responses (no stale bleed)")
    eq(w.addon.lootCore:Get(lot1.id).awards[1].winner, firstWinner, "original award is untouched")
end)

test("unlock retracts the owe (payout forgive)", function()
    local w = makeWorld("Masterlooter", true)
    startSession(w)
    setBag(w, 40005, 1); bagUpdate(w)
    local lot = openLot(w, 40005)
    w.addon:StartLiveRoll(lot.id)
    w.addon:RegisterInterest(lot.id, "Alice", "ms")
    w.addon:ResolveLiveRoll(lot.id)
    eq(owedCount(w), 1, "owed before unlock")
    w.addon.lootCore:Unlock(lot.id)
    eq(owedCount(w), 0, "unlock forgave the owe")
    eq(w.addon.lootCore:State(lot.id), "idle", "lot back to idle for reroll")
end)

test("delivery records per-copy disposition", function()
    local w = makeWorld("Masterlooter", true)
    startSession(w)
    setBag(w, 40005, 1); bagUpdate(w)
    local lot = openLot(w, 40005)
    w.addon:StartLiveRoll(lot.id)
    w.addon:RegisterInterest(lot.id, "Alice", "ms")
    w.addon:ResolveLiveRoll(lot.id)
    local ok = w.addon.lootCore:MarkDeliveredFor("Alice", 40005, CLOCK)
    check(ok, "MarkDeliveredFor succeeded")
    eq(w.addon.lootCore:Get(lot.id).awards[1].state, "delivered", "award marked delivered")
    eq(w.addon.lootCore:Get(lot.id).awards[1].recipient, "Alice", "recipient recorded")
end)

test("reconcile retire: item leaves bags -> lot retired", function()
    local w = makeWorld("Masterlooter", true)
    startSession(w)
    setBag(w, 40002, 1); bagUpdate(w)
    local lot = openLot(w, 40002)
    check(w.addon.lootCore:State(lot.id) ~= nil, "lot exists")
    setBag(w, 40002, 0); bagUpdate(w)
    eq(w.addon.lootCore:LiveCount(lot.id), 0, "lot retired when item left bags")
end)

test("itemId identity: two different links, same itemId, collapse to one lot", function()
    local w = makeWorld("Masterlooter", true)
    startSession(w)
    -- two bag entries that resolve to the same itemId via different link strings
    w.addon.BuildTradeableEpicCounts = function()
        return {
            ["|cffa335ee|Hitem:40001:0:0:0|h[Mantle]|h|r"] = 1,
            ["|cffFFFFFF|Hitem:40001:5:0:0|h[Mantle of the Bear]|h|r"] = 1,
        }
    end
    bagUpdate(w)
    eq(#lotsFor(w, 40001), 1, "one lot for the shared itemId")
    eq(openLot(w, 40001).count, 2, "both copies counted into it")
end)

test("comm sync: ML snapshot mirrors onto a raider", function()
    clearWire()
    local ml = makeWorld("Masterlooter", true)
    local raider = makeWorld("Raidertwo", false)
    startSession(ml)
    setBag(ml, 40004, 2); bagUpdate(ml)
    local lot = openLot(ml, 40004)
    ml.addon:StartLiveRoll(lot.id)
    ml.addon:RegisterInterest(lot.id, "Alice", "ms")
    ml.addon:RegisterInterest(lot.id, "Bob", "ms")
    ml.addon:ResolveLiveRoll(lot.id)
    -- force one clean full snapshot (AutoBroadcastSession is debounced on a frozen clock here)
    clearWire()
    ml.addon:BroadcastSession()
    flushWireTo(raider)
    local rl = raider.addon.lootCore:Get(lot.id)
    check(rl ~= nil, "raider mirrored the lot by id")
    eq(rl and rl.itemId, 40004, "raider lot itemId matches")
    eq(rl and rl.state, "resolved", "raider sees it resolved")
    eq(#raider.addon.session.results, 1, "raider results projection has the lot")
    local mlRes = ml.addon.session.results[1]
    local rRes = raider.addon.session.results[1]
    eq(rRes.winnersText, mlRes.winnersText, "raider winners match the ML's")
end)

test("raider pick whispers the ML and is applied", function()
    clearWire()
    local ml = makeWorld("Masterlooter", true)
    local raider = makeWorld("Raidertwo", false)
    startSession(ml)
    setBag(ml, 40005, 1); bagUpdate(ml)
    local lot = openLot(ml, 40005)
    ml.addon:StartLiveRoll(lot.id)
    flushWireTo(raider)                 -- raider gets the DROP + snapshot
    -- raider records a loot-tab response -> routed to ML as a SELECTION whisper
    raider.addon:SetPlayerResponse(lot.id, "Raidertwo", "ms")
    flushWireTo(ml)                     -- ML receives the SELECTION
    local L = ml.addon.lootCore:Get(lot.id)
    check(L.responses["raidertwo"] ~= nil, "ML recorded the raider's pick on the lot")
end)

-- ===========================================================================
print("")
print(string.format("=== WeirdLoot battery: %d passed, %d failed ===", pass, fail))
if fail > 0 then
    print("FAILURES:")
    for _, f in ipairs(failures) do print("  - " .. f) end
    os.exit(1)
end
