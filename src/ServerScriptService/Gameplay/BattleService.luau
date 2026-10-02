-- Server-owned, session-only combat. Only the final reward uses durable operations.
local BattleService = {}
function BattleService.new(options)
    local rules, catalog, views = options.rules, options.catalog, options.views
    local repository, copy = options.repository, options.copy
    local battles, busy, service = {}, {}, {}
    local now = assert(options.clock, "Combat clock required")
    local function check(value, code) if not value then error({code = code}, 0) end end
    local function fields(args, allowed)
        check(type(args) == "table", "INVALID_INPUT")
        for key in pairs(args) do check(allowed[key] == true, "INVALID_INPUT") end
    end
    local function id(value)
        check(type(value) == "string" and #value > 0 and #value <= 128 and utf8.len(value) ~= nil and string.find(value, "%S") ~= nil, "INVALID_INPUT")
    end
    local function roll()
        local value = options.nextNumber()
        check(type(value) == "number" and value >= 0 and value < 1, "INVALID_RULE_CONFIG")
        return value
    end
    local function public(battle)
        return copy({battleId = battle.battleId, revision = battle.revision, status = battle.status,
            startedAt = battle.startedAt, serverTime = now(), player = battle.player, enemy = battle.enemy, events = battle.events,
            rewardOperationId = battle.rewardOperationId, outcome = battle.outcome})
    end
    local function result(battle, events)
        return {status = if battle.status == "resolving" then "pending" else "ok",
            code = battle.rewardError, data = {battle = public(battle), events = events or {}}}
    end
    local function guarded(userId, work)
        if busy[userId] then return {status = "pending", code = "BUSY"} end
        busy[userId] = true
        local ok, response = pcall(work)
        busy[userId] = nil
        if not ok then error(response, 0) end
        return response
    end
    local function fighter(creature, enemy, at)
        local view = views.creature(rules, catalog, creature)
        local skills, seen = {}, {}
        if not enemy then
            for _, slot in ipairs(view.slots) do
                if slot.unlocked and slot.skillId and not seen[slot.skillId] then
                    seen[slot.skillId] = true
                    table.insert(skills, {skillId = slot.skillId, readyAt = at, cooldownSeconds = catalog.skills[slot.skillId].cooldownSeconds})
                end
            end
        end
        return {definitionId = creature.definitionId, stats = view.stats,
            currentHP = if enemy then math.floor(view.stats.hp * 60 / 100) else view.stats.hp,
            shield = 0, shieldExpiresAt = 0, attackInterval = rules.attackInterval(view.stats.spd),
            nextAttackAt = at + rules.attackInterval(view.stats.spd), skills = skills}
    end
    local function expireShield(fighter, at)
        if fighter.shield > 0 and at >= fighter.shieldExpiresAt then
            fighter.shield, fighter.shieldExpiresAt = 0, 0
            return true
        end
        return false
    end
    local function strike(battle, side, skillId, events, at)
        local attacker = battle[side]
        local target = battle[if side == "player" then "enemy" else "player"]
        expireShield(target, at)
        expireShield(attacker, at)
        local damage = rules.damage(attacker.stats, target.stats.def, skillId, target.shield)
        local absorbed = math.min(target.shield, damage.rawDamage)
        target.shield, target.shieldExpiresAt = 0, 0
        target.currentHP = math.max(0, target.currentHP - damage.hpDamage)
        local granted = if target.currentHP > 0 then rules.shieldAmount(skillId, attacker.stats.hp) else 0
        if granted > 0 then
            attacker.shield, attacker.shieldExpiresAt = granted, at + catalog.combat.shieldSeconds
        end
        for _, skill in ipairs(attacker.skills) do
            if skill.skillId == skillId then skill.readyAt = rules.readyAt(skillId, at) end
        end
        battle.eventSeq += 1
        local event = {seq = battle.eventSeq, at = at, actor = side, command = if skillId == "BASIC" then "BASIC" else "SKILL",
            skillId = if skillId ~= "BASIC" then skillId else nil, rawDamage = damage.rawDamage,
            shieldAbsorbed = absorbed, hpDamage = damage.hpDamage, targetHP = target.currentHP, shieldGranted = granted}
        table.insert(events, event)
        table.insert(battle.events, event)
        if #battle.events > 24 then table.remove(battle.events, 1) end
        if target.currentHP == 0 then
            battle.outcome = if side == "player" then "win" else "loss"
            battle.status = if side == "player" then "resolving" else "ended"
        end
    end
    local function rewardPlan(battle, profile)
        local creature = profile.creatures[battle.creatureId]
        check(creature ~= nil, "CREATURE_NOT_FOUND")
        check(creature.winsSinceCreation < 9007199254740991, "PROFILE_INVALID")
        check(profile.coinBalance <= 9007199254740991 - catalog.economy.victoryCoins, "PROFILE_INVALID")
        local updated = rules.afterVictory(creature)
        local first = not profile.firstVictoryEggGranted
        -- Freeze the draw in memory as well as in PREPARE, including pre-prepare retries.
        if battle.eggAward == nil then battle.eggAward = if first or roll() < catalog.economy.victoryEggChance then 1 else 0 end
        local egg = if profile.basicEggCount < catalog.economy.eggCapacity then battle.eggAward else 0
        local pending = battle.eggAward - egg
        check(profile.pendingEggRewards <= 9007199254740991 - pending, "PROFILE_INVALID")
        return {coinDelta = catalog.economy.victoryCoins, eggDelta = egg, pendingEggDelta = pending,
            firstVictoryEggGranted = if first then true else nil, updateCreatures = {updated},
            result = {battleId = battle.battleId, coinDelta = catalog.economy.victoryCoins,
                xpDelta = updated.totalXP - creature.totalXP, eggDelta = egg, pendingEggDelta = pending,
                creature = views.creature(rules, catalog, updated)}}
    end
    local function resolve(userId, battle)
        if battle.status ~= "resolving" then return end
        local snapshot = repository.snapshot(userId)
        if snapshot.status ~= "ok" then snapshot = repository.recover(userId) end
        if snapshot.status ~= "ok" then battle.rewardError = snapshot.code; return end
        local function complete(receipt)
            battle.rewardOperationId = receipt.operationId
            battle.status, battle.rewardError = "ended", nil
            battle.revision += 1
            repository.endBattle(userId, battle.battleId)
        end
        for _, receipt in ipairs(snapshot.profile.receipts) do
            if receipt.operationId == "reward:" .. battle.battleId then complete(receipt); return end
        end
        local ok, plan = pcall(function()
            if not battle.rewardPlan then battle.rewardPlan = rewardPlan(battle, snapshot.profile) end
            return battle.rewardPlan
        end)
        if not ok then battle.rewardError = if type(plan) == "table" then plan.code else "PROFILE_INVALID"; return end
        local fingerprint = "battle:" .. battle.battleId
        local issued = repository.issue(userId, "BattleReward", fingerprint, snapshot.profile.profileVersion, function() return plan end)
        if issued.status ~= "ok" then battle.rewardError = issued.code; return end
        battle.rewardOperationId = issued.operationId
        local executed = repository.execute(userId, issued.operationId, fingerprint)
        if executed.status == "committed" then complete(executed.receipt) else battle.rewardError = executed.code end
    end
    function service.inBattle(userId)
        return busy[userId] == true or (battles[userId] ~= nil and battles[userId].status ~= "ended")
    end
    function service.start(userId, args)
        return guarded(userId, function()
            fields(args, {creatureId = true, encounterId = true}); id(args.creatureId)
            check(args.encounterId == "TRAINING", "INVALID_INPUT")
            check(not battles[userId] or battles[userId].status == "ended", "IN_BATTLE")
            check(options.nearTraining(userId), "OUT_OF_RANGE")
            local snapshot = repository.snapshot(userId)
            if snapshot.status ~= "ok" then return snapshot end
            local creature = snapshot.profile.creatures[args.creatureId]
            check(creature ~= nil, "CREATURE_NOT_FOUND")
            local battleId = options.newId()
            local reserved = repository.reserveBattle(userId, battleId)
            if reserved.status ~= "ok" then return reserved end
            local ok, response = pcall(function()
                local enemy = {definitionId = if roll() < 0.5 then "C01" else "C02", totalXP = 0, startingPotentialStars = 0, winsSinceCreation = 0}
                local at = now()
                local battle = {battleId = battleId, creatureId = args.creatureId, revision = 1, status = "active", startedAt = at,
                    eventSeq = 0, events = {}, tieSide = if roll() < 0.5 then "player" else "enemy",
                    player = fighter(creature, false, at), enemy = fighter(enemy, true, at)}
                local events = {}
                battles[userId] = battle
                if battle.status == "ended" then repository.endBattle(userId, battleId) end
                return result(battle, events)
            end)
            if not ok then repository.endBattle(userId, battleId); error(response, 0) end
            return response
        end)
    end
    local function current(userId, args)
        id(args.battleId)
        check(type(args.expectedRevision) == "number" and args.expectedRevision % 1 == 0 and args.expectedRevision >= 1 and args.expectedRevision <= 9007199254740991, "INVALID_INPUT")
        local battle = battles[userId]
        check(battle ~= nil and battle.battleId == args.battleId, "STALE_BATTLE")
        -- A skill may race a server auto hit. Older observed revisions are valid;
        -- battle identity, current HP and readyAt are still checked on the server.
        check(args.expectedRevision <= battle.revision, "STALE_BATTLE")
        check(battle.status == "active", "BATTLE_ENDED")
        return battle
    end
    function service.action(userId, args)
        return guarded(userId, function()
            fields(args, {battleId = true, expectedRevision = true, command = true, skillId = true})
            local battle = current(userId, args)
            check(args.command == "SKILL", "INVALID_INPUT"); id(args.skillId)
            local found
            for _, skill in ipairs(battle.player.skills) do if skill.skillId == args.skillId then found = skill end end
            check(found ~= nil, "SKILL_LOCKED")
            check(now() >= found.readyAt, "SKILL_COOLDOWN")
            local skillId = args.skillId
            local snapshot = repository.snapshot(userId)
            if snapshot.status ~= "ok" then return snapshot end
            local events = {}
            strike(battle, "player", skillId, events, now())
            battle.revision += 1
            if battle.status == "ended" then repository.endBattle(userId, battle.battleId) end
            resolve(userId, battle)
            return result(battle, events)
        end)
    end
    function service.tick(userId)
        if busy[userId] then return nil end
        local existing = battles[userId]
        if not existing or existing.status == "ended" then return nil end
        return guarded(userId, function()
            local battle, at = battles[userId], now()
            if battle.status == "resolving" then
                if at < (battle.nextResolveAt or 0) then return nil end
                battle.nextResolveAt = at + 1
                local revision = battle.revision
                resolve(userId, battle)
                return if battle.revision ~= revision then result(battle) else nil
            end
            local player, enemy = battle.player, battle.enemy
            local shieldDue = (player.shield > 0 and at >= player.shieldExpiresAt) or (enemy.shield > 0 and at >= enemy.shieldExpiresAt)
            if at < player.nextAttackAt and at < enemy.nextAttackAt and not shieldDue then return nil end
            local snapshot = repository.snapshot(userId)
            if snapshot.status ~= "ok" then
                battle.player.nextAttackAt = at + battle.player.attackInterval
                battle.enemy.nextAttackAt = at + battle.enemy.attackInterval
                return nil
            end
            local events = {}
            local changed = expireShield(battle.player, at)
            changed = expireShield(battle.enemy, at) or changed
            local first = if battle.player.nextAttackAt == battle.enemy.nextAttackAt then battle.tieSide
                elseif battle.player.nextAttackAt < battle.enemy.nextAttackAt then "player" else "enemy"
            for _, side in ipairs({first, if first == "player" then "enemy" else "player"}) do
                local fighter = battle[side]
                if battle.status == "active" and at >= fighter.nextAttackAt then
                    fighter.nextAttackAt = at + fighter.attackInterval
                    strike(battle, side, "BASIC", events, at)
                    changed = true
                end
            end
            if not changed then return nil end
            battle.revision += 1
            if battle.status == "ended" then repository.endBattle(userId, battle.battleId) end
            resolve(userId, battle)
            return result(battle, events)
        end)
    end
    function service.get(userId, args)
        return guarded(userId, function()
            fields(args, {})
            local battle = battles[userId]
            if not battle then return {status = "ok", data = {}} end
            resolve(userId, battle)
            return result(battle)
        end)
    end
    function service.forfeit(userId, args)
        return guarded(userId, function()
            fields(args, {battleId = true, expectedRevision = true})
            local battle = current(userId, args)
            battle.status, battle.outcome = "ended", "forfeit"
            battle.revision += 1
            repository.endBattle(userId, battle.battleId)
            return {status = "ok", data = {outcome = "forfeit", battle = public(battle)}}
        end)
    end
    function service.forget(userId)
        local battle = battles[userId]
        if battle then repository.endBattle(userId, battle.battleId) end
        battles[userId], busy[userId] = nil, nil
    end
    return service
end
return BattleService
