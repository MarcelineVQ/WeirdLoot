-- Unit tests for addon:FilterByStatus and addon:RollCandidates (Resolver.lua).
-- The full resolver integration flows are exercised by tests/integration_session.lua; this file
-- focuses on the small pure helpers that other code relies on for status/roll routing.
--
-- Run from the addon dir:  luajit tests/unit_resolver.lua
-- (or just `luajit tests/run.lua` to run the whole battery).

local F = dofile("tests/_framework.lua").get()
local H = F
F.beginSuite("resolver unit battery")

H.test("FilterByStatus: BiS mode keeps only the highest-status candidates", function()
    local w = H.makeWorld("Masterlooter", true)
    local cands = {
        { name = "Alice", status = "main" },
        { name = "Bob",   status = "designatedalt" },
        { name = "Carol", status = "nil" },
    }
    local out, highest = w.addon:FilterByStatus(cands, false)
    H.eq(#out, 1, "BiS mode keeps only Mains")
    H.eq(out[1].name, "Alice", "Alice kept")
    H.eq(highest, 3, "highest actual is Main=3")
end)

H.test("FilterByStatus: non-BiS mode merges Main + DesAlt into one effective rank", function()
    local w = H.makeWorld("Masterlooter", true)
    local cands = {
        { name = "Alice", status = "main" },
        { name = "Bob",   status = "designatedalt" },
        { name = "Carol", status = "nil" },
    }
    local out, highest = w.addon:FilterByStatus(cands, true)
    -- Effective rank: Alice=2, Bob=2 (main collapsed to 2 when mergeMainAndAlt=true), Carol=1
    H.eq(#out, 2, "non-BiS keeps Main+DesAlt")
    H.eq(highest, 3, "highestActual still reports Alice's real status (main=3)")
    -- And the nil player (Carol) is dropped
    local kept = {}
    for _, c in ipairs(out) do kept[c.name] = true end
    H.truthy(kept.Alice, "Alice kept")
    H.truthy(kept.Bob,   "Bob kept")
    H.check(not kept.Carol, "Carol dropped (nil status)")
end)

H.test("FilterByStatus: empty input returns empty", function()
    local w = H.makeWorld("Masterlooter", true)
    local out, highest = w.addon:FilterByStatus({}, false)
    H.eq(#out, 0, "empty input -> empty output")
    H.eq(highest, 0, "highest defaults to 0 on empty")
end)

H.test("RollCandidates: rolls come from rollAssignments when present", function()
    local w = H.makeWorld("Masterlooter", true)
    local cands = { { name = "Alice" }, { name = "Bob" } }
    local rolls = w.addon:RollCandidates(cands, {
        alice = { name = "Alice", roll = 95 },
        bob   = { name = "Bob",   roll = 50 },
    })
    H.eq(#rolls, 2, "two rolls")
    -- Sorted descending: Alice (95) first, Bob (50) second
    H.eq(rolls[1].name, "Alice", "highest roll first")
    H.eq(rolls[1].roll, 95, "roll preserved")
    H.eq(rolls[2].roll, 50, "second roll preserved")
end)

H.test("RollCandidates: ties broken by lowercase name", function()
    local w = H.makeWorld("Masterlooter", true)
    local cands = { { name = "Bob" }, { name = "alice" } }
    local rolls = w.addon:RollCandidates(cands, {
        bob   = { name = "Bob",   roll = 50 },
        alice = { name = "alice", roll = 50 },
    })
    H.eq(rolls[1].name, "alice", "tie: lowercase 'alice' beats 'Bob'")
end)

F.endSuite()