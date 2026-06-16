local addon = WeirdLoot
local util = addon.util

function addon:InitializeResolver()
end

function addon:BuildRollerList(itemId)
    local session = self:GetCurrentSession()
    local rollers = {}
    local responses = session.responses[itemId] or {}

    for playerKey, shouldRoll in pairs(responses) do
        if shouldRoll then
            local attendee = self:GetAttendee(playerKey) or self:GetRosterProfile(playerKey)
            if attendee then
                rollers[#rollers + 1] = {
                    name = attendee.name or playerKey,
                    className = attendee.className or "",
                    specName = attendee.specName or "",
                    status = attendee.status or "nil",
                    descriptor = util:NormalizeKey((attendee.className or "") .. " " .. (attendee.specName or "")),
                }
            else
                rollers[#rollers + 1] = {
                    name = playerKey,
                    className = "",
                    specName = "",
                    status = "nil",
                    descriptor = "",
                }
            end
        end
    end

    util:SortByName(rollers, "name")
    return rollers
end

function addon:FindMatchingTier(rule, candidates, matcher)
    if not rule or not rule.tiers then
        return nil, candidates
    end

    local unmatched = util:CloneTable(candidates)
    for _, tier in ipairs(rule.tiers) do
        local survivors = {}
        local matchedKeys = {}
        local hasRest = false

        for _, entry in ipairs(tier.entries) do
            if entry.isRest then
                hasRest = true
            else
                for _, candidate in ipairs(candidates) do
                    if not matchedKeys[candidate.name] and matcher(entry, candidate) then
                        survivors[#survivors + 1] = candidate
                        matchedKeys[candidate.name] = true
                    end
                end
            end
        end

        if #survivors > 0 then
            return tier, survivors
        end

        if hasRest then
            return tier, unmatched
        end
    end

    return nil, candidates
end

function addon:FilterByStatus(candidates)
    local highestRank = 0
    local survivors = {}

    for _, candidate in ipairs(candidates) do
        highestRank = math.max(highestRank, util:StatusRank(candidate.status))
    end

    for _, candidate in ipairs(candidates) do
        if util:StatusRank(candidate.status) == highestRank then
            survivors[#survivors + 1] = candidate
        end
    end

    return survivors, highestRank
end

function addon:RollCandidates(candidates)
    local rolls = {}
    if #candidates == 1 then
        rolls[1] = {
            name = candidates[1].name,
            roll = 100,
            auto = true,
        }
        return rolls
    end

    for _, candidate in ipairs(candidates) do
        rolls[#rolls + 1] = {
            name = candidate.name,
            roll = math.random(1, 100),
            auto = false,
        }
    end

    table.sort(rolls, function(left, right)
        if left.roll == right.roll then
            return string.lower(left.name) < string.lower(right.name)
        end
        return left.roll > right.roll
    end)

    return rolls
end

function addon:BuildResultDetail(result)
    local lines = {}
    local quantityText = (result.quantity or 1) > 1 and string.format(" x%d", result.quantity or 1) or ""
    lines[#lines + 1] = "Item: " .. (result.itemName or "") .. quantityText
    lines[#lines + 1] = "All rollers: " .. (#result.allRollers > 0 and table.concat(result.allRollers, ", ") or "none")
    lines[#lines + 1] = "Named tier: " .. (result.namedTierText or "none")
    lines[#lines + 1] = "Class/spec tier: " .. (result.lootTierText or "none")
    lines[#lines + 1] = "Status tier: " .. (result.statusTierText or "none")
    lines[#lines + 1] = "Prioritized players: " .. (#result.prioritizedNames > 0 and table.concat(result.prioritizedNames, ", ") or "none")

    local rollParts = {}
    for _, roll in ipairs(result.finalRolls or {}) do
        rollParts[#rollParts + 1] = string.format("%s (%s)", roll.name, roll.auto and "AUTO" or tostring(roll.roll))
    end

    lines[#lines + 1] = "Prioritized rolls: " .. (#rollParts > 0 and table.concat(rollParts, ", ") or "none")
    lines[#lines + 1] = "Winner(s): " .. (result.winnersText or result.winner or "none")
    return table.concat(lines, "\n")
end

function addon:SelectWinningRolls(rolls, quantity)
    local winnerCount = 1
    if (quantity or 1) >= 2 then
        winnerCount = math.min(2, #rolls)
    end

    local winners = {}
    for index = 1, winnerCount do
        if rolls[index] then
            winners[#winners + 1] = rolls[index].name
        end
    end

    return winners
end

function addon:BuildResultRecord(item, allRollerNames, namedTierText, lootTierText, statusRank, prioritizedNames, rolls)
    local winners = self:SelectWinningRolls(rolls, item.quantity or 1)
    local winnersText = #winners > 0 and table.concat(winners, ", ") or "No winner"
    local result = {
        itemId = item.id,
        itemName = item.name,
        itemLink = item.link,
        quantity = item.quantity or 1,
        allRollers = allRollerNames,
        namedTierText = namedTierText,
        lootTierText = lootTierText,
        statusTierText = statusRank == 3 and "Main" or (statusRank == 2 and "Designated Alt" or "Nil"),
        prioritizedNames = prioritizedNames,
        finalRolls = rolls,
        winners = winners,
        winnersText = winnersText,
        winner = winners[1] or "No winner",
    }

    if (item.quantity or 1) >= 2 then
        result.summary = string.format("%s x%d -> %s", item.name or "Item", item.quantity or 1, winnersText)
    else
        result.summary = string.format("%s -> %s", item.name or "Item", winnersText)
    end
    result.detailText = self:BuildResultDetail(result)
    return result
end

function addon:ProcessLoot()
    if not self:IsAuthorizedLootMaster() then
        self:Print("Only the loot master can process loot.")
        return
    end

    local session = self:GetCurrentSession()
    local results = {}

    for _, item in ipairs(session.items or {}) do
        local rollers = self:BuildRollerList(item.id)
        local allRollerNames = {}
        for _, roller in ipairs(rollers) do
            allRollerNames[#allRollerNames + 1] = roller.name
        end

        local namedRule = self:GetNamedRule(item.name)
        local lootRule = self:GetLootRule(item.name)

        local namedTier, prioritized = self:FindMatchingTier(namedRule, rollers, function(entry, candidate)
            return entry.playerKey == util:NormalizeKey(candidate.name)
        end)

        if not namedTier and lootRule then
            local lootTier
            lootTier, prioritized = self:FindMatchingTier(lootRule, prioritized, function(entry, candidate)
                local keyA = util:NormalizeKey((candidate.className or "") .. " " .. (candidate.specName or ""))
                local keyB = util:NormalizeKey((candidate.specName or "") .. " " .. (candidate.className or ""))
                for _, key in ipairs(entry.matchKeys or {}) do
                    if key ~= "" and (key == keyA or key == keyB) then
                        return true
                    end
                end
                return false
            end)

            local statusSurvivors, rank = self:FilterByStatus(prioritized)
            local rolls = self:RollCandidates(statusSurvivors)
            local prioritizedNames = {}
            for _, player in ipairs(statusSurvivors) do
                prioritizedNames[#prioritizedNames + 1] = player.name
            end

            results[#results + 1] = self:BuildResultRecord(
                item,
                allRollerNames,
                nil,
                lootTier and lootTier.raw or nil,
                rank,
                prioritizedNames,
                rolls
            )
        else
            local statusSurvivors, rank = self:FilterByStatus(prioritized)
            local rolls = self:RollCandidates(statusSurvivors)
            local prioritizedNames = {}
            for _, player in ipairs(statusSurvivors) do
                prioritizedNames[#prioritizedNames + 1] = player.name
            end

            results[#results + 1] = self:BuildResultRecord(
                item,
                allRollerNames,
                namedTier and namedTier.raw or nil,
                nil,
                rank,
                prioritizedNames,
                rolls
            )
        end
    end

    session.results = results
    self.sessionDb.history = self.sessionDb.history or {}
    self.sessionDb.history[#self.sessionDb.history + 1] = {
        sessionId = session.id,
        timestamp = time(),
        results = util:CloneTable(results),
    }

    for _, result in ipairs(results) do
        SendChatMessage(result.summary, "RAID")
    end

    self:BroadcastResults(results)
    self:TriggerCallback("RESULTS_UPDATED")
    self:Print("Loot processed.")
end
