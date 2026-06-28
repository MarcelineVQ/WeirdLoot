-- Unit tests for the LootCore. Wraps the addon's LootCore.RunSelfChecks (the in-file self-test
-- battery the core author wrote) plus a few extra property-style assertions targeted at the
-- contract callers depend on (id monotonicity, no reuse, Resolve route is single-door).
--
-- Run from the addon dir:  luajit tests/unit_lootcore.lua
-- (or just `luajit tests/run.lua` to run the whole battery).

local F = dofile("tests/_framework.lua").get()
local H = F
F.beginSuite("lootcore unit battery")

H.test("core self-checks (in-harness)", function()
    local w = H.makeWorld("Masterlooter", true)
    H.check(w.addon.LootCore.RunSelfChecks(false), "all core self-checks pass")
end)

-- ---------------------------------------------------------------------------
-- Property-style: LootCore behaves correctly under repeated Reconcile cycles.
-- ---------------------------------------------------------------------------
H.test("LootCore: ids are strictly monotonic and never reused across resets", function()
    local w = H.makeWorld("Masterlooter", true)
    local c = w.addon.LootCore.New()
    -- Mint three distinct lots
    c:Reconcile({ [100] = 1 }, { [100] = true })
    c:Reconcile({ [101] = 1 }, { [101] = true })
    c:Reconcile({ [102] = 1 }, { [102] = true })
    local first = c:All()        -- All() returns every lot (List filters to live)
    H.eq(#first, 3, "three lots minted")
    local ids = { first[1].id, first[2].id, first[3].id }
    H.check(ids[1] ~= ids[2] and ids[2] ~= ids[3] and ids[1] ~= ids[3], "all three ids distinct")

    -- Drop one, re-mint: id must NOT be reused. Retired lots stay in the map with removed=true;
    -- the new live lot for [100] must carry a different id.
    c:Reconcile({ [100] = 0 }, {})
    c:Reconcile({ [100] = 1 }, { [100] = true })
    local newLot = c:openLotForItem(100)
    H.notNil(newLot, "a new live lot exists for [100]")
    H.check(newLot.id ~= ids[1], "new [100] lot id != the retired one (no id reuse)")
    -- The retired lot is still in the ledger (audit log) but no longer live.
    H.check(c:Get(ids[1]).removed == true, "retired lot flagged removed")
end)

H.test("LootCore: STATE constants are exactly the documented set", function()
    local w = H.makeWorld("Masterlooter", true)
    local S = w.addon.LootCore.STATE
    H.eq(S.NEW,      "new",      "NEW")
    H.eq(S.IDLE,     "idle",     "IDLE")
    H.eq(S.PENDING,  "pending",  "PENDING")
    H.eq(S.ROLLING,  "rolling",  "ROLLING")
    H.eq(S.RESOLVED, "resolved", "RESOLVED")
    H.eq(S.SKIPPED,  "skipped",  "SKIPPED")
end)

H.test("LootCore: AWARD constants are exactly the documented set", function()
    local w = H.makeWorld("Masterlooter", true)
    local A = w.addon.LootCore.AWARD
    H.eq(A.OWED,      "owed",      "OWED")
    H.eq(A.RESOLVED,  "resolved",  "RESOLVED")
    H.eq(A.DELIVERED, "delivered", "DELIVERED")
    H.eq(A.REMOVED,   "removed",   "REMOVED")
end)

H.test("LootCore: ledgerChanged event fires after Reset", function()
    -- Catches a regression where Reset forgets to emit the change notification, breaking UI sync.
    local w = H.makeWorld("Masterlooter", true)
    local c = w.addon.LootCore.New()
    local fired = 0
    c:On("ledgerChanged", function() fired = fired + 1 end)
    c:Reconcile({ [1] = 1 }, { [1] = true })
    c:Reset()
    H.check(fired >= 1, "ledgerChanged fired at least once (mints + reset)")
end)

F.endSuite()