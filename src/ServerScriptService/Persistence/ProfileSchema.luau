local ProfileSchema = {}
local MAX = 9007199254740991

local function check(condition, code)
    if not condition then error({ code = code }, 0) end
end

local function integer(value, minimum, maximum)
    check(type(value) == "number" and value == value and value % 1 == 0 and value >= minimum and value <= maximum, "INVALID_INTEGER")
end

local function id(value)
    check(type(value) == "string" and #value > 0 and #value <= 128 and string.find(value, "%S") ~= nil and utf8.len(value) ~= nil, "INVALID_ID")
end

-- Reject cycles, sparse/mixed tables and non-JSON values before copying storage data.
function ProfileSchema.copy(value)
    local seen, count = {}, 0
    local function visit(item, depth)
        count += 1
        check(depth <= 32 and count <= 50000, "DATA_TOO_COMPLEX")
        local kind = type(item)
        if kind == "nil" or kind == "boolean" then return item end
        if kind == "string" then check(utf8.len(item) ~= nil, "INVALID_UTF8"); return item end
        if kind == "number" then
            check(item == item and math.abs(item) <= MAX, "INVALID_NUMBER")
            return item
        end
        check(kind == "table" and not seen[item] and getmetatable(item) == nil, "INVALID_DATA")
        seen[item] = true
        local result, keyType, numericCount = {}, nil, 0
        for key, child in pairs(item) do
            local currentType = type(key)
            check(currentType == "string" or currentType == "number", "INVALID_KEY")
            check(keyType == nil or keyType == currentType, "MIXED_TABLE")
            keyType = currentType
            if currentType == "number" then integer(key, 1, MAX); numericCount += 1 else check(utf8.len(key) ~= nil, "INVALID_UTF8") end
            result[key] = visit(child, depth + 1)
        end
        if keyType == "number" then for index = 1, numericCount do check(result[index] ~= nil, "SPARSE_ARRAY") end end
        seen[item] = nil
        return result
    end
    return visit(value, 0)
end

local function fields(value, names)
    check(type(value) == "table", "INVALID_OBJECT")
    for key in pairs(value) do check(names[key] == true, "UNKNOWN_FIELD") end
end

local function array(value)
    check(type(value) == "table", "INVALID_ARRAY")
    local count = 0
    for key in pairs(value) do integer(key, 1, #value); count += 1 end
    check(count == #value, "INVALID_ARRAY")
end

function ProfileSchema.new(rules, measure)
    local schema = { copy = ProfileSchema.copy, check = check, integer = integer, id = id }
    function schema.newProfile()
        return { schemaVersion = 1, profileVersion = 0, coinBalance = 0, basicEggCount = 0, pendingEggRewards = 0,
            starterGrantClaimed = false, firstVictoryEggGranted = false, nodeNextAvailableAt = { N01 = 0, N02 = 0, N03 = 0 },
            creatures = {}, lastAppliedSeq = 0, receipts = {} }
    end

    local function creature(value)
        fields(value, { instanceId=true, definitionId=true, totalXP=true, startingPotentialStars=true, winsSinceCreation=true, inheritedSkillId=true, isLocked=true, createdAt=true, originOperationId=true })
        id(value.instanceId); id(value.originOperationId)
        integer(value.createdAt, 0, MAX)
        check(type(value.isLocked) == "boolean", "INVALID_LOCK")
        local ok = pcall(rules.validateCreature, value)
        check(ok, "INVALID_CREATURE")
    end

    local kinds = { StarterGrant=true, ["Mix.Commit"]=true, ["Egg.Hatch"]=true, ["Egg.Buy"]=true, ["Egg.Collect"]=true, ["Creature.SetLocked"]=true, BattleReward=true, ["Reward.ClaimPendingEggs"]=true }
    function schema.validatePlan(plan)
        ProfileSchema.copy(plan)
        fields(plan, { coinDelta=true, eggDelta=true, pendingEggDelta=true, removeIds=true, createCreatures=true, updateCreatures=true, nodeUpdates=true, starterGrantClaimed=true, firstVictoryEggGranted=true, result=true })
        for _, key in ipairs({ "coinDelta", "eggDelta", "pendingEggDelta" }) do integer(plan[key] or 0, -MAX, MAX) end
        for _, key in ipairs({ "starterGrantClaimed", "firstVictoryEggGranted" }) do check(plan[key] == nil or plan[key] == true, "INVALID_GRANT_FLAG") end
        for _, key in ipairs({ "removeIds", "createCreatures", "updateCreatures" }) do array(plan[key] or {}) end
        for _, key in ipairs(plan.removeIds or {}) do id(key) end
        for _, value in ipairs(plan.createCreatures or {}) do creature(value) end
        for _, value in ipairs(plan.updateCreatures or {}) do creature(value) end
        fields(plan.nodeUpdates or {}, { N01=true, N02=true, N03=true })
        for _, timestamp in pairs(plan.nodeUpdates or {}) do integer(timestamp, 0, MAX) end
        check(type(plan.result) == "table", "INVALID_RESULT")
    end

    function schema.validate(profile)
        ProfileSchema.copy(profile)
        fields(profile, { schemaVersion=true, profileVersion=true, coinBalance=true, basicEggCount=true, pendingEggRewards=true, starterGrantClaimed=true, firstVictoryEggGranted=true, nodeNextAvailableAt=true, creatures=true, lease=true, lastAppliedSeq=true, preparedOperation=true, receipts=true })
        check(profile.schemaVersion == 1, "UNSUPPORTED_SCHEMA")
        integer(profile.profileVersion, 0, MAX); integer(profile.lastAppliedSeq, 0, MAX)
        check(profile.profileVersion == profile.lastAppliedSeq, "INVALID_SEQUENCE")
        integer(profile.coinBalance, 0, MAX); integer(profile.basicEggCount, 0, 20); integer(profile.pendingEggRewards, 0, MAX)
        check(type(profile.starterGrantClaimed) == "boolean" and type(profile.firstVictoryEggGranted) == "boolean", "INVALID_FLAGS")
        fields(profile.nodeNextAvailableAt, { N01=true, N02=true, N03=true })
        for _, key in ipairs({ "N01", "N02", "N03" }) do integer(profile.nodeNextAvailableAt[key], 0, MAX) end
        check(type(profile.creatures) == "table", "INVALID_CREATURES")
        local count = 0
        for key, value in pairs(profile.creatures) do
            id(key); creature(value); check(key == value.instanceId, "INSTANCE_ID_MISMATCH"); count += 1
        end
        check(count <= 30, "CAPACITY_FULL")
        if profile.lease then
            fields(profile.lease, { sessionId=true, generation=true, expiresAt=true })
            id(profile.lease.sessionId); integer(profile.lease.generation, 1, MAX); integer(profile.lease.expiresAt, 0, MAX)
        end
        array(profile.receipts)
        check(#profile.receipts <= 100, "TOO_MANY_RECEIPTS")
        local previous, ids = 0, {}
        for _, receipt in ipairs(profile.receipts) do
            fields(receipt, { operationId=true, seq=true, kind=true, inputFingerprint=true, committedAt=true, resultingProfileVersion=true, result=true })
            id(receipt.operationId); id(receipt.inputFingerprint)
            check(kinds[receipt.kind] == true, "UNKNOWN_OPERATION_KIND")
            integer(receipt.seq, previous + 1, profile.lastAppliedSeq)
            check(not ids[receipt.operationId], "DUPLICATE_RECEIPT")
            ids[receipt.operationId] = true; previous = receipt.seq
            integer(receipt.committedAt, 0, MAX)
            check(receipt.resultingProfileVersion == receipt.seq and type(receipt.result) == "table", "INVALID_RECEIPT")
        end
        check((profile.lastAppliedSeq == 0 and #profile.receipts == 0) or previous == profile.lastAppliedSeq, "MISSING_LATEST_RECEIPT")
        local prepared = profile.preparedOperation
        if prepared then
            fields(prepared, { operationId=true, seq=true, kind=true, inputFingerprint=true, expectedProfileVersion=true, preparedAt=true, rulesVersion=true, worldPhaseId=true, resultPlan=true })
            id(prepared.operationId); id(prepared.inputFingerprint); id(prepared.rulesVersion)
            if prepared.worldPhaseId then id(prepared.worldPhaseId) end
            check(kinds[prepared.kind] == true and not ids[prepared.operationId], "INVALID_PREPARED")
            integer(prepared.seq, 1, MAX)
            check(prepared.seq == profile.lastAppliedSeq + 1 and prepared.expectedProfileVersion == profile.profileVersion, "INVALID_PREPARED_SEQUENCE")
            integer(prepared.preparedAt, 0, MAX)
            schema.validatePlan(prepared.resultPlan)
        end
        check(measure(profile) <= 256 * 1024, "PROFILE_TOO_LARGE")
        return profile
    end

    function schema.apply(profile, plan, operationId, kind)
        schema.validatePlan(plan)
        check(kinds[kind] == true, "UNKNOWN_OPERATION_KIND")
        local result = ProfileSchema.copy(profile)
        result.preparedOperation = nil
        if plan.starterGrantClaimed then
            check(kind == "StarterGrant" and not result.starterGrantClaimed, "STARTER_ALREADY_GRANTED")
            check(plan.coinDelta == 20 and plan.eggDelta == 1, "INVALID_STARTER_GRANT")
            result.starterGrantClaimed = true
        end
        if kind == "StarterGrant" then check(plan.starterGrantClaimed == true, "INVALID_STARTER_GRANT") end
        if plan.firstVictoryEggGranted then
            check(kind == "BattleReward" and not result.firstVictoryEggGranted, "FIRST_VICTORY_ALREADY_GRANTED")
            result.firstVictoryEggGranted = true
        end
        result.coinBalance += plan.coinDelta or 0
        result.basicEggCount += plan.eggDelta or 0
        result.pendingEggRewards += plan.pendingEggDelta or 0
        local touched = {}
        for _, key in ipairs(plan.removeIds or {}) do
            check(not touched[key] and result.creatures[key] ~= nil, "INVALID_REMOVAL")
            check(not result.creatures[key].isLocked, "CREATURE_LOCKED")
            touched[key] = true; result.creatures[key] = nil
        end
        for _, value in ipairs(plan.createCreatures or {}) do
            local key = value.instanceId
            check(not touched[key] and result.creatures[key] == nil and value.originOperationId == operationId, "INVALID_CREATION")
            touched[key] = true; result.creatures[key] = ProfileSchema.copy(value)
        end
        for _, value in ipairs(plan.updateCreatures or {}) do
            local key, old = value.instanceId, result.creatures[value.instanceId]
            check(not touched[key] and old ~= nil, "INVALID_CREATURE_UPDATE")
            check(old.definitionId == value.definitionId and old.createdAt == value.createdAt and old.originOperationId == value.originOperationId and old.startingPotentialStars == value.startingPotentialStars and old.inheritedSkillId == value.inheritedSkillId, "IMMUTABLE_CREATURE_FIELD")
            check(value.totalXP >= old.totalXP and value.winsSinceCreation >= old.winsSinceCreation, "PROGRESSION_REGRESSION")
            touched[key] = true; result.creatures[key] = ProfileSchema.copy(value)
        end
        for key, timestamp in pairs(plan.nodeUpdates or {}) do
            check(timestamp >= result.nodeNextAvailableAt[key], "NODE_TIME_REGRESSION")
            result.nodeNextAvailableAt[key] = timestamp
        end
        schema.validate(result)
        return result
    end

    function schema.commit(profile, now)
        local prepared = profile.preparedOperation
        check(prepared ~= nil, "NOT_PREPARED")
        local result = schema.apply(profile, prepared.resultPlan, prepared.operationId, prepared.kind)
        result.lastAppliedSeq = prepared.seq
        result.profileVersion = prepared.seq
        table.insert(result.receipts, { operationId=prepared.operationId, seq=prepared.seq, kind=prepared.kind, inputFingerprint=prepared.inputFingerprint, committedAt=now, resultingProfileVersion=prepared.seq, result=ProfileSchema.copy(prepared.resultPlan.result) })
        if #result.receipts > 100 then table.remove(result.receipts, 1) end
        return schema.validate(result)
    end
    return schema
end

return ProfileSchema
