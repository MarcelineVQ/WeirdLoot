-- Programmatic checker for the WeirdLoot core trace (WeirdLootDebugLog).
--
-- The in-game logger (Debug.lua) persists a structured record per core command/transition
-- to the WeirdLootDebugLog SavedVariable. This script asserts that trace against the core's
-- intended behaviors, so an in-game test run can be verified mechanically instead of by eye.
--
-- Usage:
--   luajit tests/checklog.lua <path/to/SavedVariables/WeirdLoot.lua>   # check a real run
--   luajit tests/checklog.lua --demo                                   # drive the real core
--                                                                      # and self-check + a
--                                                                      # negative teeth test
--
-- Exit code is 0 when every invariant holds, 1 otherwise (CI-friendly).

local STATE_NEW, STATE_IDLE, STATE_PENDING = "new", "idle", "pending"
local STATE_ROLLING, STATE_RESOLVED, STATE_SKIPPED = "rolling", "resolved", "skipped"

-- ---------------------------------------------------------------------------
-- the checker: records (array) -> (ok, violations)
-- Tracking is scoped per session segment (lot ids restart "L:1" each login).
-- ---------------------------------------------------------------------------
local function checkRecords(records)
    local V, notes = {}, {}
    local function fail(inv, rec, msg)
        V[#V + 1] = { inv = inv, seq = rec and rec.seq, ev = rec and rec.ev, msg = msg }
    end
    local function note(rec, msg)
        notes[#notes + 1] = { seq = rec and rec.seq, msg = msg }
    end

    local lastSeq = nil
    local state, minted, owed = {}, {}, {}   -- per-id, reset on each session segment
    local appliedRev, gapPending = nil, false -- raider-side comm tracking (recv-* events)
    -- reliability lifecycle, keyed by reqId (req/resend/ack/give-up events). Per-client: a raider
    -- log carries the request side, the ML log the targeted-send/ack side.
    local reqSeen, reqOpen, gaveUp, acked, lastResend = {}, {}, {}, {}, {}
    -- midCapture: the segment began with a clear/login, so capture may have started with a
    -- non-empty ledger (clear wipes the LOG, not the loot ledger). Lots minted / a baseline synced
    -- before the clear are legitimately absent, so leading orphan ops are notes, not failures. A
    -- real `reset` wipes the ledger, so it switches back to strict checking.
    local midCapture = false

    local function resetSegment()
        state, minted, owed = {}, {}, {}
        appliedRev, gapPending = nil, false
        reqSeen, reqOpen, gaveUp, acked, lastResend = {}, {}, {}, {}, {}
    end

    for _, rec in ipairs(records) do
        local ev, id = rec.ev, rec.id

        -- A. global monotonic seq
        if lastSeq and rec.seq and rec.seq <= lastSeq then
            fail("monotonic-seq", rec, string.format("seq %s not > previous %s", tostring(rec.seq), tostring(lastSeq)))
        end
        if rec.seq then lastSeq = rec.seq end

        -- pre-capture tolerance: in a clear/login-started segment the first op on an unseen id was
        -- minted before the log was cleared. Register it and skip the one-time transition check,
        -- instead of flagging mint-before-use / an illegal transition from an unknown prior state.
        local preCapture = false
        if midCapture and id and not minted[id]
            and ev ~= "mint" and ev ~= "session" and ev ~= "reset" and ev ~= "mark" then
            minted[id] = true
            preCapture = true
            note(rec, "pre-capture lot " .. tostring(id) .. " (operated on before the log was cleared)")
        end

        if ev == "session" or ev == "reset" then
            -- segment boundary: a new login (session) or a ledger Reset (Start/Clear Session)
            -- legitimately restarts lot ids at L:1, so clear per-id tracking here.
            resetSegment()
            if ev == "reset" then
                midCapture = false -- ledger truly wiped: fresh L:1 mints expected, check strictly
            else
                local r = rec.reason
                midCapture = (r == "clear" or r == "login") -- capture may begin with a populated ledger
            end
        elseif ev == "mark" then
            -- segment label only
        elseif ev == "mint" then
            -- A duplicate mint id can only arise from a ledger Reset (the core's seq strictly
            -- increments within one instance). If we reach here with the id already minted, a
            -- reset happened that was not recorded (e.g. a log captured before reset logging) --
            -- treat it as an implicit segment boundary and note it, rather than a false failure.
            if minted[id] then
                note(rec, "implicit segment boundary at " .. tostring(id) .. " (no reset/session record before it)")
                resetSegment()
            end
            minted[id] = true
            state[id] = rec.state or STATE_NEW
        elseif ev == "grow" or ev == "shrink" or ev == "retire" or ev == "remove" then
            -- count adjustments: id (when present) must already exist
            if id and not minted[id] then fail("mint-before-use", rec, ev .. " on unminted " .. tostring(id)) end
        elseif ev == "surface" then
            if not minted[id] then fail("mint-before-use", rec, "surface on unminted " .. tostring(id))
            else
                local s = state[id]
                if not preCapture and s ~= STATE_NEW and s ~= STATE_IDLE and s ~= STATE_SKIPPED then
                    fail("legal-transition", rec, string.format("surface from %s (want new/idle/skipped)", tostring(s)))
                end
                state[id] = STATE_PENDING
            end
        elseif ev == "skip" then
            if not preCapture and state[id] ~= STATE_PENDING then fail("legal-transition", rec, "skip from " .. tostring(state[id])) end
            state[id] = STATE_SKIPPED
        elseif ev == "startRoll" then
            if not preCapture and state[id] ~= STATE_PENDING then fail("legal-transition", rec, "startRoll from " .. tostring(state[id])) end
            state[id] = STATE_ROLLING
        elseif ev == "cancel" then
            if not preCapture and state[id] ~= STATE_ROLLING then fail("legal-transition", rec, "cancel from " .. tostring(state[id])) end
            state[id] = STATE_PENDING
        elseif ev == "response" then
            if rec.ok then
                if not minted[id] then fail("mint-before-use", rec, "response on unminted " .. tostring(id)) end
                -- F. an accepted response must never land on a resolved (not-yet-unlocked) lot
                if state[id] == STATE_RESOLVED then
                    fail("no-response-after-resolve", rec, "accepted response on resolved " .. tostring(id) .. " (stale-roll)")
                end
            end
        elseif ev == "resolve" then
            if not minted[id] then fail("mint-before-use", rec, "resolve on unminted " .. tostring(id)) end
            if state[id] == STATE_RESOLVED then fail("legal-transition", rec, "resolve of already-resolved " .. tostring(id)) end
            state[id] = STATE_RESOLVED
            local awards = rec.awards or {}
            -- E. one award per copy
            if rec.count and #awards ~= rec.count then
                fail("awards-eq-count", rec, string.format("%d award(s) for count %d", #awards, rec.count))
            end
            local o = 0
            for _, a in ipairs(awards) do if a.state == "owed" then o = o + 1 end end
            owed[id] = o
        elseif ev == "unlock" then
            if not preCapture and state[id] ~= STATE_RESOLVED then fail("legal-transition", rec, "unlock from " .. tostring(state[id])) end
            state[id] = STATE_IDLE
            owed[id] = 0
        elseif ev == "deliver" then
            -- G. delivery only against an owed award produced by a prior resolve
            if (owed[id] or 0) <= 0 then
                fail("deliver-needs-owed", rec, "deliver on " .. tostring(id) .. " with no outstanding owed award")
            else
                owed[id] = owed[id] - 1
            end
        elseif ev == "recv-snap" then
            -- a full snapshot re-baselines the raider's revision unconditionally and heals any gap;
            -- it is also the response that resolves any outstanding sync request.
            appliedRev, gapPending = rec.rev, false
            reqOpen = {}
        elseif ev == "recv-gap" then
            gapPending = true
        elseif ev == "recv-lot" then
            -- H. a delta is only applied after a baseline, strictly contiguous, and never while a
            -- gap is outstanding (a gap must be healed by a recv-snap first).
            if gapPending then
                fail("gap-before-resync", rec, "delta rev " .. tostring(rec.rev) .. " applied while a gap was pending")
            end
            if appliedRev == nil then
                if midCapture then
                    note(rec, "recv baseline adopted mid-capture at rev " .. tostring(rec.rev) .. " (snapshot predates the clear)")
                else
                    fail("recv-contiguity", rec, "delta rev " .. tostring(rec.rev) .. " applied with no prior snapshot baseline")
                end
            elseif rec.rev ~= appliedRev + 1 then
                fail("recv-contiguity", rec, string.format("delta rev %s applied after %s (not contiguous)", tostring(rec.rev), tostring(appliedRev)))
            end
            appliedRev = rec.rev
        elseif ev == "req" then
            -- a peer opened a reliable sync request (raider log)
            if rec.reqId then reqSeen[rec.reqId] = true; reqOpen[rec.reqId] = true end
        elseif ev == "resend" then
            local rid = rec.reqId
            -- I. a give-up is terminal: nothing more may happen for that reqId
            if rid and gaveUp[rid] then
                fail("give-up-terminal", rec, "resend for " .. tostring(rid) .. " after it gave up")
            end
            -- J. a resend is never the initial send (attempt 1), and attempts strictly increase
            if rec.attempt and rec.attempt < 2 then
                fail("resend-monotonic", rec, "resend attempt " .. tostring(rec.attempt) .. " < 2 (attempt 1 is the initial send)")
            end
            if rid and rec.attempt and lastResend[rid] and rec.attempt <= lastResend[rid] then
                fail("resend-monotonic", rec, string.format("resend attempt %s not > previous %s for %s",
                    tostring(rec.attempt), tostring(lastResend[rid]), tostring(rid)))
            end
            if rid and rec.attempt then lastResend[rid] = rec.attempt end
            -- K. a request resend must follow a request we actually saw open
            if rec.kind == "request" and rid and not reqSeen[rid] then
                fail("request-opened", rec, "resend(request) for " .. tostring(rid) .. " with no prior req")
            end
            -- L. once acked, the authority must stop resending the targeted snapshot
            if rec.kind == "ack" and rid and acked[rid] then
                fail("ack-once", rec, "resend(ack) for " .. tostring(rid) .. " after it was acked")
            end
        elseif ev == "ack" then
            local rid = rec.reqId
            if rid and gaveUp[rid] then fail("give-up-terminal", rec, "ack for " .. tostring(rid) .. " after give-up") end
            if rid and acked[rid] then fail("ack-once", rec, "duplicate ack for " .. tostring(rid)) end
            if rid then acked[rid] = true end
        elseif ev == "give-up" then
            -- M. give-up carries one of the known reasons
            local reason = rec.reason
            if reason ~= "max" and reason ~= "left" and reason ~= "no-authority" then
                fail("give-up-reason", rec, "unknown give-up reason " .. tostring(reason))
            end
            local rid = rec.reqId
            if rid then
                if gaveUp[rid] then fail("give-up-terminal", rec, "duplicate give-up for " .. tostring(rid)) end
                if rec.kind == "request" and not reqSeen[rid] then
                    fail("request-opened", rec, "give-up(request) for " .. tostring(rid) .. " with no prior req")
                end
                gaveUp[rid] = true
                reqOpen[rid] = nil
            end
        end
    end

    -- N. a sync request still open at end of log never got a resync or a give-up. Soft: the run
    -- may simply have ended mid-retry, so this is a note, not a failure.
    for rid in pairs(reqOpen) do
        note(nil, "sync request " .. tostring(rid) .. " unresolved at end of log (no resync or give-up)")
    end

    return #V == 0, V, notes
end

-- ---------------------------------------------------------------------------
-- reporting
-- ---------------------------------------------------------------------------
local INVARIANTS = {
    "monotonic-seq", "mint-before-use", "legal-transition",
    "awards-eq-count", "no-response-after-resolve", "deliver-needs-owed",
    "recv-contiguity", "gap-before-resync",
    "resend-monotonic", "give-up-terminal", "ack-once", "request-opened", "give-up-reason",
}

local function report(label, records)
    local counts = {}
    for _, r in ipairs(records) do counts[r.ev] = (counts[r.ev] or 0) + 1 end
    local evParts = {}
    for ev, n in pairs(counts) do evParts[#evParts + 1] = ev .. "=" .. n end
    table.sort(evParts)
    print(string.format("[%s] %d record(s): %s", label, #records, table.concat(evParts, " ")))

    local ok, V, notes = checkRecords(records)
    local byInv = {}
    for _, v in ipairs(V) do byInv[v.inv] = (byInv[v.inv] or 0) + 1 end
    for _, inv in ipairs(INVARIANTS) do
        local n = byInv[inv] or 0
        print(string.format("  %-28s %s", inv, n == 0 and "ok" or ("FAIL (" .. n .. ")")))
    end
    for _, v in ipairs(V) do
        print(string.format("  ! seq=%s %s [%s] %s", tostring(v.seq), tostring(v.ev), v.inv, v.msg))
    end
    for _, nt in ipairs(notes or {}) do
        print(string.format("  ~ seq=%s note: %s", tostring(nt.seq), nt.msg))
    end
    return ok
end

-- ---------------------------------------------------------------------------
-- load a SavedVariables file and pull out WeirdLootDebugLog.records
-- ---------------------------------------------------------------------------
local function loadSavedVar(path)
    local f = assert(io.open(path, "r"), "cannot open " .. path)
    local src = f:read("*a"); f:close()
    local env = setmetatable({}, { __index = _G })
    local chunk = assert(loadstring(src, "@" .. path))
    setfenv(chunk, env)
    chunk()
    local log = env.WeirdLootDebugLog
    assert(log and log.records, "no WeirdLootDebugLog.records in " .. path)
    return log.records
end

-- ---------------------------------------------------------------------------
-- demo mode: drive the REAL core through a logger, then check the trace.
-- This validates the instrumentation and the checker together, out of game.
-- ---------------------------------------------------------------------------
local function demoRecords()
    local here = string.match(arg[0] or "", "^(.*)/tests/") or "."
    local LootCore = loadfile(here .. "/Loot/LootCore.lua")("WeirdLoot", {})

    local recs, seq = {}, 0
    local function logger(ev, data)
        seq = seq + 1
        local r = { seq = seq, ev = ev }
        if data then for k, v in pairs(data) do r[k] = v end end
        recs[#recs + 1] = r
    end

    -- top-N resolver: order responders by roll desc, one winner per copy
    local function topN(lot)
        local rs = {}
        for player, v in pairs(lot.responses) do
            if v ~= "pass" then rs[#rs + 1] = { name = player, roll = tonumber(string.match(v, "%d+")) or 0 } end
        end
        table.sort(rs, function(a, b) return a.roll > b.roll end)
        local winners = {}
        for i = 1, lot.count do winners[i] = rs[i] and rs[i].name or nil end
        return { winners = winners, winner = winners[1] }
    end

    local c = LootCore.New()
    c:SetLogger(logger)
    c:SetResolver(topN)
    c:SetML("ML")
    c:On("ledgerChanged", function() end)

    logger("session", { reason = "demo" })

    -- scenario 1: 2x drop, three rollers -> two distinct owed winners, deliver one
    c:Reconcile({ [40001] = 2 }, { [40001] = true })          -- mint L:1 count 2 (fresh)
    local id = c:openLotForItem(40001).id
    c:Reconcile({ [40001] = 3 }, { [40001] = true })          -- grow to 3
    c:Surface(id); c:StartRoll(id)
    c:SetResponse(id, "Bob", "ms:90")
    c:SetResponse(id, "Amy", "ms:70")
    c:SetResponse(id, "Cat", "os:40")
    c:Resolve(id)                                             -- 3 awards, 2 owed (ML not among)
    c:SetResponse(id, "Late", "ms:99")                       -- rejected (resolved) -> ok=false
    c:MarkDeliveredFor("Bob", 40001)                         -- deliver one owed copy

    -- scenario 2: stale-roll guard -- re-drop the SAME itemId after resolve mints a NEW lot
    c:Reconcile({ [40001] = 4 }, { [40001] = true })         -- +1 fresh copy -> new open lot
    local id2 = c:openLotForItem(40001).id
    assert(id2 ~= id, "re-drop must mint a fresh lot id")

    -- scenario 3: unlock + reroll, then a copy leaves bags (retire/remove)
    c:Reconcile({ [50000] = 1 }, { [50000] = true })
    local x = c:openLotForItem(50000).id
    c:Surface(x); c:StartRoll(x); c:SetResponse(x, "Dan", "ms:55"); c:Resolve(x)
    c:Unlock(x)
    c:Surface(x); c:StartRoll(x); c:SetResponse(x, "Eve", "ms:60"); c:Resolve(x)
    c:Reconcile({}, {})                                      -- everything left bags -> retire/remove

    -- a clean raider-side comm sequence: snapshot baseline, two contiguous deltas, a gap that is
    -- healed by a resync snapshot, then a contiguous delta off the new baseline. All valid.
    logger("recv-snap", { rev = 1, lots = 2 })
    logger("recv-lot", { id = "L:1", rev = 2 })
    logger("recv-lot", { id = "L:2", rev = 3 })
    logger("recv-gap", { rev = 7, lastRev = 3 })
    logger("recv-snap", { rev = 7, lots = 3 })
    logger("recv-lot", { id = "L:3", rev = 8 })

    -- a clean reliability lifecycle. Raider side: a request, one backoff resend, then the resync
    -- snapshot that resolves it. Authority side (would be a separate log; mixed here for the
    -- self-test): an ack for one targeted send, and a roster-leave give-up for another.
    logger("req", { reqId = "Raider:1", attempt = 1 })
    logger("resend", { kind = "request", reqId = "Raider:1", attempt = 2 })
    logger("recv-snap", { rev = 9, lots = 1 })                              -- resolves Raider:1
    logger("ack", { reqId = "ML:3" })                                       -- targeted send confirmed
    logger("give-up", { kind = "ack", reqId = "ML:4", reason = "left" })    -- target left the raid

    return recs
end

-- a deliberately-broken trace: the checker MUST flag it, or it has no teeth
local function brokenRecords()
    return {
        { seq = 1, ev = "session", reason = "teeth" },
        { seq = 2, ev = "mint", id = "L:1", itemId = 1, count = 1, state = "new" },
        { seq = 3, ev = "surface", id = "L:1", from = "new" },
        { seq = 4, ev = "startRoll", id = "L:1" },
        { seq = 5, ev = "resolve", id = "L:1", count = 1, awards = { { state = "owed", winner = "Bob" } } },
        { seq = 6, ev = "response", id = "L:1", player = "Bob", value = "ms", ok = true },  -- stale-roll bug
        { seq = 7, ev = "deliver", id = "L:2", recipient = "Zed" },                          -- never minted/owed
        { seq = 8, ev = "resolve", id = "L:3", count = 2, awards = { { state = "owed" } } }, -- awards != count + unminted
        { seq = 9, ev = "recv-snap", rev = 1, lots = 1 },
        { seq = 10, ev = "recv-lot", id = "L:1", rev = 3 },     -- non-contiguous (skipped rev 2)
        { seq = 11, ev = "recv-gap", rev = 9, lastRev = 3 },
        { seq = 12, ev = "recv-lot", id = "L:1", rev = 10 },    -- applied while a gap is pending
        -- reliability violations
        { seq = 13, ev = "give-up", kind = "request", reqId = "B:1", reason = "max" },  -- give-up(request) with no prior req
        { seq = 14, ev = "resend", kind = "request", reqId = "B:1", attempt = 3 },      -- resend after give-up (+ no prior req)
        { seq = 15, ev = "give-up", kind = "ack", reqId = "B:2", reason = "bogus" },    -- unknown give-up reason
        { seq = 16, ev = "resend", kind = "ack", reqId = "B:3", attempt = 2 },
        { seq = 17, ev = "resend", kind = "ack", reqId = "B:3", attempt = 2 },          -- attempt not increasing
        { seq = 18, ev = "ack", reqId = "B:3" },
        { seq = 19, ev = "resend", kind = "ack", reqId = "B:3", attempt = 3 },          -- resend after ack
    }
end

-- ---------------------------------------------------------------------------
-- main
-- ---------------------------------------------------------------------------
local target = arg[1]
if target == "--demo" or target == nil then
    if target == nil then print("(no file given; running --demo. Pass a SavedVariables path to check a real run.)") end
    local okDemo = report("demo", demoRecords())
    print()
    -- teeth test: the broken trace must FAIL, and we assert it does
    local okBroken = report("teeth (expect FAIL)", brokenRecords())
    print()
    if okDemo and (not okBroken) then
        print("checklog self-test: PASS (real-core trace clean, broken trace caught)")
        os.exit(0)
    else
        print("checklog self-test: FAIL (demo clean=" .. tostring(okDemo) .. ", broken caught=" .. tostring(not okBroken) .. ")")
        os.exit(1)
    end
else
    local ok = report(target, loadSavedVar(target))
    os.exit(ok and 0 or 1)
end
