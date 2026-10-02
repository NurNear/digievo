local Suite = {}
function Suite.run(modules, originalRules, catalog)
    local checks = 0
    local function check(value, label) checks += 1; assert(value, label) end
    local function reject(response, code)
        check(response.status == "rejected" and response.error.code == code, "expected " .. code .. ", got " .. tostring(response.status) .. "/" .. tostring(response.error and response.error.code))
    end
    local function fixture(config)
        config = config or {}
        local rules = table.clone(originalRules)
        if config.playerStats then
            rules.stats = function(creature)
                return if creature.instanceId == "p1" then table.clone(config.playerStats) else originalRules.stats(creature)
            end
        end
        local time, serial, rolls, near = 1000, 0, 0, true
        local schema = modules.Schema.new(rules, function() return 100 end)
        local store = modules.MemoryStore.new(schema.copy)
        local function newId() serial += 1; return "battle-test-" .. serial end
        local repository = modules.Repository.new({schema = schema, store = store, sessionId = "battle-session", rulesVersion = catalog.rulesVersion, clock = function() return math.floor(time) end, newId = newId})
        local sessions = modules.Session.new(repository)
        check(sessions.join(1).status == "ok", "join")
        check(sessions.join(2).status == "ok", "other player")
        local seed = repository.issue(1, "BattleReward", "seed", sessions.snapshot(1).profile.profileVersion, function(operationId)
            return {createCreatures = {{instanceId = "p1", definitionId = config.definitionId or "C01", totalXP = config.xp or 0,
                startingPotentialStars = config.stars or 0, winsSinceCreation = config.wins or 0, inheritedSkillId = config.inherited,
                isLocked = config.locked == true, createdAt = time, originOperationId = operationId}},
                eggDelta = config.fullEggs and 19 or 0, firstVictoryEggGranted = config.firstDone or nil, result = {}}
        end)
        check(repository.execute(1, seed.operationId, "seed").status == "committed", "seed")
        local opts = {clock = function() return time end, rules = rules, catalog = catalog, views = modules.Views, repository = repository, copy = schema.copy,
            nearTraining = function() return near end, newId = newId,
            nextNumber = function()
                rolls += 1
                return if config.draws and config.draws[rolls] then config.draws[rolls] else (config.draw or 0.1)
            end}
        local battle = modules.Battle.new(opts)
        opts.inBattle = battle.inBattle
        opts.nearNode = function() return true end
        local actions = modules.Actions.new(opts)
        local mix = modules.Mix.new(opts)
        actions["Mix.Commit"] = mix.build
        local dispatcher = modules.Dispatcher.new({repository = repository, sessions = sessions, rules = rules, catalog = catalog, views = modules.Views,
            clock = function() return math.floor(time) end, battle = battle, mix = mix, operationBuilders = actions})
        local function request(action, args, userId, requestId, noTick)
            if not noTick then time += 1 end
            return dispatcher.handle(userId or 1, {apiVersion = 1, requestId = requestId or newId(), action = action, args = args or {}})
        end
        local function start(requestId) return request("Battle.Start", {creatureId = "p1", encounterId = "TRAINING"}, 1, requestId) end
        local function act(view, skillId, userId, requestId)
            return request("Battle.Action", {battleId = view.battleId, expectedRevision = view.revision, command = skillId and "SKILL" or "BASIC", skillId = skillId}, userId, requestId)
        end
        local function win(view)
            for _ = 1, 50 do
                if view.status ~= "active" then return view end
                time += 2.5
                local response = battle.tick(1)
                if not response then continue end
                check(response.status == "ok" or response.status == "pending", "combat action")
                view = response.data.battle
            end
            error("battle did not finish")
        end
        return {schema = schema, store = store, repository = repository, sessions = sessions, battle = battle, request = request, start = start, act = act, win = win,
            profile = function() return repository.snapshot(1).profile end, rolls = function() return rolls end,
            setNear = function(value) near = value end, setTime = function(value) time = value end, time = function() return time end,
            tick = function(seconds) time += seconds; return battle.tick(1) end}
    end
    local f = fixture({locked = true})
    local started = f.start("start-once")
    check(started.status == "ok", "locked pet trains")
    local view = started.data.battle
    check(view.enemy.currentHP == 57 and view.player.currentHP == 96, "training HP and no opening instant hit")
    check(view.roundIndex == nil and view.activeSide == nil and view.player.ownerTurnIndex == nil, "no turn state")
    check(view.player.skills[1].readyAt == view.startedAt, "skills immediately available")
    check(view.player.nextAttackAt > view.startedAt, "independent attack deadline")
    check(f.start("start-once").data.battle.battleId == view.battleId and f.rolls() == 2, "start replay")
    reject(f.start(), "IN_BATTLE")
    reject(f.request("Battle.Start", {creatureId = "p1", encounterId = "TRAINING"}, 2), "CREATURE_NOT_FOUND")
    reject(f.act(view, "S01", 2), "STALE_BATTLE")
    reject(f.request("Operation.Create", {kind = "Egg.Buy", params = {quantity = 1}}), "IN_BATTLE")
    reject(f.request("Operation.Create", {kind = "Creature.SetLocked", params = {creatureId = "p1", locked = false}}), "IN_BATTLE")
    reject(f.request("Mix.Preview", {parentIds = {"p1", "p2"}}), "IN_BATTLE")
    reject(f.act(view), "INVALID_INPUT")
    reject(f.act(view, "U01"), "SKILL_LOCKED")
    reject(f.request("Battle.Action", {battleId = view.battleId, expectedRevision = view.revision, command = "SKILL", skillId = "S01", damage = 999}), "INVALID_INPUT")
    local response = f.act(view, "S01", 1, "cast-once")
    check(response.status == "ok" and #response.data.events == 1, "skill hits immediately without automatic enemy retaliation")
    check(response.data.battle.player.nextAttackAt == view.player.nextAttackAt, "skill does not consume/reset automatic attack")
    check(response.data.battle.player.skills[1].readyAt == f.time() + 6, "six-second cooldown")
    check(f.act(view, "S01", 1, "cast-once").data.battle.revision == response.data.battle.revision, "skill request replay once")
    view = f.win(response.data.battle)
    check(view.status == "ended" and view.outcome == "win", "automatic attacks finish battle with no client basics")
    local profile = f.profile()
    check(profile.coinBalance == 40 and profile.basicEggCount == 2 and profile.firstVictoryEggGranted, "one reward and guaranteed egg")
    check(profile.creatures.p1.totalXP == 20 and profile.creatures.p1.winsSinceCreation == 1 and profile.creatures.p1.isLocked, "progression and lock preserved")
    local seq = profile.lastAppliedSeq
    check(f.tick(10) == nil, "no attacks after death")
    for _ = 1, 3 do check(f.request("Battle.Get").data.battle.status == "ended", "ended snapshot") end
    check(f.profile().lastAppliedSeq == seq, "reward exactly once")
    reject(f.act(view, "S01"), "BATTLE_ENDED")

    -- Clock precision and concurrent-auto revision handling.
    f = fixture({playerStats = {hp = 1000, atk = 1, def = 1, spd = 16}})
    view = f.start().data.battle
    check(f.tick(1.999) == nil, "no early automatic hit")
    f.setTime(view.player.nextAttackAt)
    response = f.battle.tick(1)
    check(#response.data.events == 2, "both equal-deadline fighters attack in one tick")
    check(response.data.events[1].seq == 1 and response.data.events[2].seq == 2, "ordered event ids")
    response = f.act(view, "S01")
    check(response.status == "ok", "skill tolerates earlier observed revision during auto hit race")
    view = response.data.battle
    local readyAt = view.player.skills[1].readyAt
    f.setTime(readyAt - 0.001)
    reject(f.request("Battle.Action", {battleId = view.battleId, expectedRevision = view.revision, command = "SKILL", skillId = "S01"}, 1, nil, true), "SKILL_COOLDOWN")
    f.setTime(readyAt)
    response = f.request("Battle.Action", {battleId = view.battleId, expectedRevision = view.revision, command = "SKILL", skillId = "S01"}, 1, nil, true)
    check(response.status == "ok", "ready at exact seconds boundary without waiting for a turn")
    check(f.tick(30).data.battle.eventSeq == nil, "internal event counter not exposed")
    response = f.tick(30)
    check(#response.data.events <= 2, "server hitch does not burst missed attacks")
    check(response.data.battle.player.nextAttackAt > f.time(), "next attack rebased after hitch")
    reject(f.request("Battle.Forfeit", {battleId = view.battleId, expectedRevision = 999999}), "STALE_BATTLE")

    f = fixture({definitionId = "C02"})
    view = f.start().data.battle
    check(view.enemy.attackInterval < view.player.attackInterval, "speed changes frequency")
    response = f.tick(2)
    check(#response.data.events == 1 and response.data.events[1].actor == "enemy", "faster enemy independently attacks")
    response = f.tick(0.2)
    check(#response.data.events == 1 and response.data.events[1].actor == "player", "slower player attacks on own deadline")

    -- Shield survives own basics; consumes one incoming hit or four seconds.
    f = fixture({definitionId = "C03", xp = 80, inherited = "W01", draw = 0.8})
    view = f.start().data.battle
    check(#view.player.skills == 2, "duplicate growth/inherited ID shares cooldown")
    response = f.act(view, "W01")
    check(response.data.events[1].shieldGranted == 10, "shield amount")
    local shieldExpiry = response.data.battle.player.shieldExpiresAt
    f.setTime(view.player.nextAttackAt)
    response = f.battle.tick(1)
    check(response.data.battle.player.shield == 10, "own basic does not clear shield")
    f.setTime(view.enemy.nextAttackAt)
    response = f.battle.tick(1)
    check(response.data.events[1].actor == "enemy" and response.data.events[1].shieldAbsorbed == 10, "next hit consumes shield")
    f = fixture({definitionId = "C03", xp = 80, draw = 0.8})
    view = f.start().data.battle
    response = f.act(view, "W01")
    shieldExpiry = response.data.battle.player.shieldExpiresAt
    f.setTime(shieldExpiry)
    response = f.battle.tick(1)
    for _, event in ipairs(response.data.events) do
        if event.actor == "enemy" then check(event.shieldAbsorbed == 0, "expired shield cannot absorb hit") end
    end

    f = fixture({definitionId = "C02"})
    view = f.start().data.battle
    seq = f.profile().lastAppliedSeq
    check(f.request("Battle.Forfeit", {battleId = view.battleId, expectedRevision = view.revision}).data.outcome == "forfeit", "forfeit")
    check(f.tick(10) == nil and f.profile().lastAppliedSeq == seq, "forfeit stops auto without reward")
    view = f.start().data.battle
    check(view.player.currentHP == 120 and view.player.skills[1].readyAt == view.startedAt, "new match resets HP and cooldown")
    f.battle.forget(1)
    check(f.tick(10) == nil and f.request("Battle.Get").data.battle == nil, "disconnect removes scheduler state")

    f = fixture({playerStats = {hp = 1, atk = 1, def = 1, spd = 1}})
    response = f.start()
    view = f.tick(2).data.battle
    check(view.outcome == "loss" and view.player.currentHP == 0, "enemy kills before slower player")
    check(#view.events == 1 and f.tick(100) == nil, "dead fighter never retaliates")
    check(f.profile().coinBalance == 20, "loss no resource penalty")
    f = fixture({playerStats = {hp = 1000, atk = 1000, def = 1, spd = 100}})
    view = f.win(f.start().data.battle)
    check(#view.events == 1 and view.outcome == "win", "lethal auto suppresses later enemy hit")

    -- Reward fault and fencing coverage remains on the existing PREPARE/COMMIT path.
    for _, mode in ipairs({"repeat", "before", "prepare", "commit", "takeover", "longOutage"}) do
        f = fixture({firstDone = true, playerStats = {hp = 1000, atk = 1000, def = 1, spd = 16}})
        view = f.start().data.battle
        local before, calls = f.profile(), f.store.calls
        if mode == "repeat" then f.store.callbackRepeats = 100
        elseif mode == "before" or mode == "longOutage" then f.store.failBefore = true
        elseif mode == "commit" then
            f.store.beforeCall = function(store) if store.calls == calls + 2 then store.failAfter = true end end
        else f.store.failAfter = true end
        response = f.act(view, "S01")
        local rolls = f.rolls()
        if mode == "repeat" then
            check(response.data.battle.status == "ended", "100 repeated callbacks finish once")
        else
            check(response.status == "pending" and response.data.battle.status == "resolving", mode .. " reward pending")
            check(f.battle.inBattle(1), "resolving reservation")
            reject(f.start(), "IN_BATTLE")
            check(f.tick(0.1) == nil, "pending rewards do not attack")
            f.store.failBefore, f.store.failAfter, f.store.beforeCall = false, false, nil
            if mode == "takeover" then
                f.battle.forget(1); f.setTime(1300)
                local replacement = modules.Repository.new({schema = f.schema, store = f.store, sessionId = "replacement", rulesVersion = catalog.rulesVersion, clock = function() return 1300 end, newId = function() return "unused" end})
                check(replacement.open(1).status == "ok", "takeover recovers reward")
                check(replacement.snapshot(1).profile.coinBalance == before.coinBalance + 20, "takeover pays once")
                check(f.repository.execute(1, response.data.battle.rewardOperationId, "battle:" .. view.battleId).status == "rejected", "old session fenced")
            else
                if mode == "longOutage" then f.setTime(1300); check(f.sessions.heartbeat(1).status == "ok", "renew after outage") end
                local recovered = f.tick(1.1)
                check(recovered.data.battle.status == "ended", mode .. " server timer recovers reward")
                check(f.profile().coinBalance == before.coinBalance + 20 and f.profile().creatures.p1.winsSinceCreation == 1, mode .. " exact reward")
            end
        end
        check(f.rolls() == rolls, mode .. " no recovery reroll")
    end
    -- Hatch -> realtime training -> Growth unlock -> mix.
    f = fixture({xp = 60})
    local egg = f.request("Operation.Create", {kind = "Egg.Hatch", params = {}})
    local hatched = f.request("Operation.Execute", {operationId = egg.data.operationId})
    check(hatched.status == "committed", "journey hatch")
    f.win(f.start().data.battle)
    local preview = f.request("Mix.Preview", {parentIds = {"p1", hatched.data.result.creature.instanceId}})
    check(preview.status == "ok", "mix after realtime reward")
    local inherited = false
    for _, candidate in ipairs(preview.data.candidates) do
        for _, outcome in ipairs(candidate.inheritedOutcomes) do if outcome.skillId == "U01" then inherited = true end end
    end
    check(inherited, "level five Growth in inheritance pool")
    local intent = f.request("Operation.Create", {kind = "Mix.Commit", params = {previewId = preview.data.previewId}})
    check(f.request("Operation.Execute", {operationId = intent.data.operationId}).status == "committed", "journey mix")
    f = fixture({wins = 9007199254740991})
    view = f.win(f.start().data.battle)
    check(view.status == "resolving" and f.profile().coinBalance == 20, "overflow no partial reward")
    f = fixture({fullEggs = true})
    f.win(f.start().data.battle)
    check(f.profile().basicEggCount == 20 and f.profile().pendingEggRewards == 1, "full inventory keeps victory egg")
    f = fixture({xp = 480, stars = 5})
    f.win(f.start().data.battle)
    check(f.profile().creatures.p1.totalXP == 480, "XP cap")
    f = fixture()
    local pending = f.request("Operation.Create", {kind = "Egg.Hatch", params = {}})
    f.store.failAfter = true
    check(f.request("Operation.Execute", {operationId = pending.data.operationId}).status == "pending", "uncertain operation")
    check(f.start().status == "pending", "cannot start during pending mutation")
    f.store.failAfter = false
    check(f.repository.recover(1).status == "ok", "mutation recovery")
    f.setNear(false)
    reject(f.start(), "OUT_OF_RANGE")
    f.setNear(true)
    view = f.start().data.battle
    for _ = 1, 2 do reject(f.request("Battle.Action", {battleId = view.battleId, expectedRevision = 99999, command = "SKILL", skillId = "S01"}, 1, nil, true), "STALE_BATTLE") end
    reject(f.request("Battle.Forfeit", {battleId = view.battleId, expectedRevision = view.revision}, 1, nil, true), "RATE_LIMITED")
    return {checks = checks}
end
return Suite
