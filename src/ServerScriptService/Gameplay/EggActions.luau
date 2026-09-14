-- Pure server plan builders. Identity, proximity and battle state are injected by the host.
local EggActions = {}
function EggActions.new(options)
    local catalog, rules, views = options.catalog, options.rules, options.views
    local economy = catalog.economy
    local function check(condition, code)
        if not condition then error({code = code}, 0) end
    end
    local function fields(params, allowed)
        check(type(params) == "table", "INVALID_INPUT")
        for key in pairs(params) do check(allowed[key] == true, "INVALID_INPUT") end
    end
    local function space(profile)
        check(profile.basicEggCount < economy.eggCapacity, "CAPACITY_FULL")
    end
    local builders = {}
    builders["Egg.Buy"] = function(_, profile, params)
        fields(params, {quantity = true})
        check(params.quantity == 1, "INVALID_INPUT")
        space(profile)
        check(profile.coinBalance >= economy.eggPrice, "INSUFFICIENT_FUNDS")
        return {coinDelta = -economy.eggPrice, eggDelta = 1, result = {coinDelta = -economy.eggPrice, eggDelta = 1}}
    end
    builders["Egg.Collect"] = function(_, profile, params, now, userId)
        fields(params, {nodeId = true})
        check(type(params.nodeId) == "string" and table.find(economy.nodeIds, params.nodeId) ~= nil, "INVALID_INPUT")
        check(options.nearNode(userId, params.nodeId), "OUT_OF_RANGE")
        check(now >= profile.nodeNextAvailableAt[params.nodeId], "NODE_UNAVAILABLE")
        space(profile)
        local nextAt = now + economy.nodeCooldownSeconds
        return {eggDelta = 1, nodeUpdates = {[params.nodeId] = nextAt}, result = {nodeId = params.nodeId, nextAvailableAt = nextAt, eggDelta = 1}}
    end
    builders["Egg.Hatch"] = function(operationId, profile, params, now, _, dryRun)
        fields(params, {})
        check(profile.basicEggCount > 0, "NO_EGG")
        local count = 0
        for _ in pairs(profile.creatures) do count += 1 end
        check(count < economy.creatureCapacity, "CAPACITY_FULL")
        local creature = {instanceId = operationId, originOperationId = operationId, definitionId = if dryRun then economy.eggOutcomes[1].definitionId else rules.rollEgg(options.nextNumber), totalXP = 0, startingPotentialStars = 0, winsSinceCreation = 0, isLocked = false, createdAt = now}
        return {eggDelta = -1, createCreatures = {creature}, result = {eggDelta = -1, creature = views.creature(rules, catalog, creature)}}
    end
    builders["Creature.SetLocked"] = function(_, profile, params)
        fields(params, {creatureId = true, locked = true})
        check(type(params.creatureId) == "string" and type(params.locked) == "boolean", "INVALID_INPUT")
        local existing = profile.creatures[params.creatureId]
        check(existing ~= nil, "CREATURE_NOT_FOUND")
        local creature = table.clone(existing)
        creature.isLocked = params.locked
        return {updateCreatures = {creature}, result = {creatureId = params.creatureId, locked = params.locked}}
    end
    builders["Reward.ClaimPendingEggs"] = function(_, profile, params)
        fields(params, {})
        check(profile.pendingEggRewards > 0, "NOTHING_TO_CLAIM")
        space(profile)
        local moved = math.min(economy.eggCapacity - profile.basicEggCount, profile.pendingEggRewards)
        return {eggDelta = moved, pendingEggDelta = -moved, result = {moved = moved, pendingRemaining = profile.pendingEggRewards - moved}}
    end
    for kind, builder in pairs(builders) do
        builders[kind] = function(id, profile, params, now, userId, dryRun)
            check(not options.inBattle(userId), "IN_BATTLE")
            return builder(id, profile, params, now, userId, dryRun)
        end
    end
    return builders
end
return EggActions
