local Suite = {}
function Suite.run(modules, rules, catalog)
    local checks, serial, time, rolls = 0, 0, 1000, 0
    local near, battle = true, false
    local function check(value, message) checks += 1; assert(value, message) end
    local schema = modules.Schema.new(rules, function() return 100 end)
    local store = modules.MemoryStore.new(schema.copy)
    local repository = modules.Repository.new({schema = schema, store = store, sessionId = "eggs", rulesVersion = catalog.rulesVersion, clock = function() return time end, newId = function() serial += 1; return "egg-op-" .. serial end})
    local sessions = modules.Session.new(repository)
    check(sessions.join(1).status == "ok", "join")
    check(sessions.join(2).status == "ok", "second player")
    local builders = modules.Actions.new({catalog = catalog, rules = rules, views = modules.Views, nearNode = function() return near end, inBattle = function() return battle end, nextNumber = function() rolls += 1; return 0.75 end})
    local dispatcher = modules.Dispatcher.new({repository = repository, sessions = sessions, rules = rules, catalog = catalog, views = modules.Views, clock = function() return time end, operationBuilders = builders})
    local function request(action, args, userId)
        time += 1; serial += 1
        return dispatcher.handle(userId or 1, {apiVersion = 1, requestId = "r" .. serial, action = action, args = args or {}})
    end
    local function create(kind, params)
        return request("Operation.Create", {kind = kind, params = params or {}})
    end
    local function execute(id, userId) return request("Operation.Execute", {operationId = id}, userId) end
    local function mutation(kind, params)
        local response = create(kind, params)
        if response.status ~= "ok" then return response end
        return execute(response.data.operationId)
    end
    local function rejected(response, code) check(response.status == "rejected" and response.error.code == code, "expected " .. code) end
    local function snapshot() return sessions.snapshot(1).profile end
    local function seed(plan)
        local issued = repository.issue(1, "BattleReward", "seed" .. serial, snapshot().profileVersion, function() return plan end)
        check(issued.status == "ok", "seed issued")
        check(repository.execute(1, issued.operationId, "seed" .. (serial - 1)).status == "committed", "seed committed")
    end
    local hatch = create("Egg.Hatch")
    check(hatch.status == "ok" and rolls == 0, "create does not roll")
    rejected(execute(hatch.data.operationId, 2), "STALE_OPERATION")
    store.callbackRepeats = 100
    local result = execute(hatch.data.operationId)
    check(result.status == "committed" and result.data.result.creature.definitionId == "C02", "hatch result")
    check(rolls == 1 and snapshot().basicEggCount == 0, "one roll and one egg consumed")
    check(execute(hatch.data.operationId).status == "committed" and rolls == 1, "replay never rerolls")
    -- A lost PREPARE response must recover the stored hatch, with no second roll.
    local second = request("Operation.Create", {kind = "Egg.Hatch", params = {}}, 2)
    local beforeRolls = rolls
    store.failAfter = true
    check(execute(second.data.operationId, 2).status == "pending", "lost prepare is pending")
    store.failAfter = false
    check(repository.recover(2).status == "ok", "recover prepared hatch")
    check(rolls == beforeRolls + 1, "recovery does not reroll")
    store.callbackRepeats = 1
    check(execute(second.data.operationId, 2).status == "committed", "recovered receipt replay")
    rejected(mutation("Egg.Hatch"), "NO_EGG")
    rejected(mutation("Egg.Buy", {quantity = 2}), "INVALID_INPUT")
    rejected(mutation("Egg.Buy", {quantity = 1}), "INSUFFICIENT_FUNDS")
    near = false
    rejected(mutation("Egg.Collect", {nodeId = "N01"}), "OUT_OF_RANGE")
    near = true
    rejected(mutation("Egg.Collect", {nodeId = "N99"}), "INVALID_INPUT")
    check(mutation("Egg.Collect", {nodeId = "N01"}).status == "committed", "collect")
    rejected(mutation("Egg.Collect", {nodeId = "N01"}), "NODE_UNAVAILABLE")
    local collected = create("Egg.Collect", {nodeId = "N02"})
    near = false
    rejected(execute(collected.data.operationId), "OUT_OF_RANGE")
    near = true
    check(execute(collected.data.operationId).status == "committed", "retry near node")
    local id = result.data.result.creature.instanceId
    check(mutation("Creature.SetLocked", {creatureId = id, locked = true}).status == "committed", "lock")
    check(snapshot().creatures[id].isLocked, "lock persisted")
    check(mutation("Creature.SetLocked", {creatureId = id, locked = true}).status == "committed", "same-value no-op")
    check(mutation("Creature.SetLocked", {creatureId = id, locked = false}).status == "committed", "unlock")
    rejected(mutation("Creature.SetLocked", {creatureId = "other", locked = true}), "CREATURE_NOT_FOUND")
    rejected(mutation("Egg.Hatch", {extra = true}), "INVALID_INPUT")
    rejected(mutation("Reward.ClaimPendingEggs"), "NOTHING_TO_CLAIM")
    battle = true
    rejected(mutation("Egg.Hatch"), "IN_BATTLE")
    battle = false
    seed({coinDelta = 40, pendingEggDelta = 25, result = {}})
    check(mutation("Egg.Buy", {quantity = 1}).status == "committed", "buy")
    check(snapshot().coinBalance == 20, "server price")
    check(mutation("Reward.ClaimPendingEggs").status == "committed", "claim to capacity")
    check(snapshot().basicEggCount == 20 and snapshot().pendingEggRewards == 8, "pending remainder")
    rejected(mutation("Egg.Collect", {nodeId = "N03"}), "CAPACITY_FULL")
    rejected(mutation("Reward.ClaimPendingEggs"), "CAPACITY_FULL")
    local cyclic = {}; cyclic.self = cyclic
    rejected(request("Profile.Get", cyclic), "INVALID_INPUT")
    rejected(request("Profile.Get", {x = string.rep("x", 9000)}), "INVALID_INPUT")
    rejected(request("Profile.Get", {extra = true}), "INVALID_INPUT")
    rejected(request("Profile.Get", {x = 0/0}), "INVALID_INPUT")
    -- Fill the collection through committed operations, refilling eggs with an internal fixture.
    for _ = 1, 19 do check(mutation("Egg.Hatch").status == "committed", "fill collection") end
    seed({eggDelta = 10, result = {}})
    for _ = 1, 10 do check(mutation("Egg.Hatch").status == "committed", "fill collection") end
    rejected(mutation("Egg.Hatch"), "CAPACITY_FULL")
    check(snapshot().basicEggCount == 1, "capacity rejection preserves egg")
    check(sessions.join(1).status == "ok" and snapshot().coinBalance == 20, "starter never repeats")
    return {checks = checks}
end
return Suite
