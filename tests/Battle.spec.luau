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
        local repository = modules.Repository.new({schema = schema, store = store, sessionId = "battle-session", rulesVersion = catalog.rulesVersion, clock = function() return time end, newId = newId})
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
        local opts = {rules = rules, catalog = catalog, views = modules.Views, repository = repository, copy = schema.copy,
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
            clock = function() return time end, battle = battle, mix = mix, operationBuilders = actions})
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
                local response = act(view)
                check(response.status == "ok" or response.status == "pending", "combat action")
                view = response.data.battle
            end
            error("battle did not finish")
        end
        return {schema = schema, store = store, repository = repository, sessions = sessions, battle = battle, request = request, start = start, act = act, win = win,
            profile = function() return repository.snapshot(1).profile end, rolls = function() return rolls end,
            setNear = function(value) near = value end, setTime = function(value) time = value end}
    end
    local f = fixture({locked = true})
    local writes = f.store.writes
    local started = f.start("start-once")
    check(started.status == "ok", "locked creature can train")
    local view = started.data.battle
    check(view.enemy.definitionId == "C01" and view.enemy.stats.hp == 96 and view.enemy.currentHP == 57, "training enemy 60 percent HP")
    check(view.player.currentHP == 96 and #view.player.skills == 1, "full HP and growth locked")
    check(view.activeSide == "player" and view.player.ownerTurnIndex == 1, "player wins first tie draw")
    check(f.start("start-once").data.battle.battleId == view.battleId and f.rolls() == 2, "start replay does not reroll")
    reject(f.start(), "IN_BATTLE")
    reject(f.request("Battle.Start", {creatureId = "p1", encounterId = "TRAINING"}, 2), "CREATURE_NOT_FOUND")
    reject(f.act(view, nil, 2), "STALE_BATTLE")
    reject(f.request("Operation.Create", {kind = "Egg.Buy", params = {quantity = 1}}), "IN_BATTLE")
    reject(f.request("Operation.Create", {kind = "Creature.SetLocked", params = {creatureId = "p1", locked = false}}), "IN_BATTLE")
    reject(f.request("Mix.Preview", {parentIds = {"p1", "p2"}}), "IN_BATTLE")
    reject(f.request("Operation.Create", {kind = "BattleReward", params = {}}), "IN_BATTLE")
    reject(f.request("Battle.Action", {battleId = view.battleId, expectedRevision = view.revision, command = "BASIC", skillId = "S01"}), "INVALID_INPUT")
    reject(f.act(view, "U01"), "SKILL_LOCKED")
    reject(f.request("Battle.Action", {battleId = view.battleId, expectedRevision = view.revision, command = "BASIC", damage = 999}), "INVALID_INPUT")
    local response = f.act(view, nil, 1, "action-once")
    check(response.data.battle.roundIndex == 2 and #response.data.events == 3, "tie alternates and enemy takes end/start turns")
    check(response.data.events[1].actor == "player" and response.data.events[2].actor == "enemy" and response.data.events[3].actor == "enemy", "event order")
    reject(f.act(view), "STALE_BATTLE")
    check(f.act(view, nil, 1, "action-once").data.battle.revision == response.data.battle.revision, "action replay")
    check(f.store.writes == writes, "no storage writes for combat turns/rejections")
    view = f.win(response.data.battle)
    check(view.status == "ended" and view.outcome == "win", "training victory")
    local profile = f.profile()
    check(profile.coinBalance == 40 and profile.basicEggCount == 2 and profile.firstVictoryEggGranted, "first victory exact coins and guaranteed egg")
    check(profile.creatures.p1.totalXP == 20 and profile.creatures.p1.winsSinceCreation == 1 and profile.creatures.p1.isLocked, "only fighter gains progression and preserves lock")
    check(view.rewardOperationId == "reward:" .. view.battleId, "reward identity bound to battle")
    check(f.rolls() == 2, "first victory has no extra egg RNG")
    local seq = profile.lastAppliedSeq
    for _ = 1, 3 do check(f.request("Battle.Get").data.battle.status == "ended", "repeated get") end
    check(f.profile().lastAppliedSeq == seq, "reward exactly once")
    reject(f.act(view), "BATTLE_ENDED")
    reject(f.request("Operation.Create", {kind = "BattleReward", params = {}}), "INVALID_INPUT")
    check(f.start().data.battle.player.currentHP == originalRules.stats(profile.creatures.p1).hp, "new battle restores HP")

    f = fixture({definitionId = "C02", draw = 0.8})
    view = f.start().data.battle
    check(view.enemy.definitionId == "C02" and view.enemy.stats.hp == 120, "other training species")
    check(view.player.currentHP < 120 and view.roundIndex == 1, "enemy wins tie and auto attacks before player")
    view = f.act(view, "S02").data.battle
    check(view.player.ownerTurnIndex == 2 and view.player.skills[1].readyAtOwnerTurn == 4, "cooldown owner turn 4")
    reject(f.act(view, "S02"), "SKILL_COOLDOWN")
    view = f.act(view).data.battle
    reject(f.act(view, "S02"), "SKILL_COOLDOWN")
    view = f.act(view).data.battle
    check(view.player.ownerTurnIndex == 4, "two cooldown turns pass")
    response = f.act(view, "S02")
    check(response.status == "ok" and response.data.battle.outcome == "win", "skill reusable turn four")
    check(#response.data.events == 1, "defeated enemy cannot retaliate")

    f = fixture({definitionId = "C03", xp = 80, inherited = "W01", draw = 0.1})
    view = f.start().data.battle
    check(#view.player.skills == 2, "growth and inherited same skill deduplicated")
    response = f.act(view, "W01")
    check(response.data.events[1].shieldGranted == 10, "wave guard shield amount")
    check(response.data.events[2].shieldAbsorbed == 10 and response.data.battle.player.shield == 0, "shield absorbs next hit then clears")

    f = fixture({definitionId = "C02", inherited = "W01", draw = 0.8})
    view = f.start().data.battle
    response = f.act(view, "W01")
    check(#response.data.events == 1 and response.data.events[1].shieldGranted == 9, "shield granted at end of round")
    check(response.data.battle.player.shield == 0, "unused shield expires on immediate next owner turn")

    f = fixture({definitionId = "C02", draw = 0.1})
    response = f.start()
    check(response.data.events[1].actor == "enemy" and response.data.battle.player.currentHP < 120, "higher enemy speed starts")
    view = response.data.battle
    profile = f.profile()
    check(f.request("Battle.Forfeit", {battleId = view.battleId, expectedRevision = view.revision}).data.outcome == "forfeit", "forfeit")
    check(f.profile().lastAppliedSeq == profile.lastAppliedSeq and not f.battle.inBattle(1), "forfeit no penalty or reward")
    check(f.start().status == "ok", "restart after forfeit")
    f.battle.forget(1)
    check(f.request("Battle.Get").data.battle == nil and f.profile().lastAppliedSeq == profile.lastAppliedSeq, "disconnect cancels active battle without reward")

    f = fixture({definitionId = "C02", playerStats = {hp = 1, atk = 1, def = 1, spd = 100}})
    view = f.start().data.battle
    writes = f.store.writes
    response = f.act(view)
    check(response.data.battle.outcome == "loss" and response.data.battle.player.currentHP == 0, "loss stops at zero HP")
    check(f.store.writes == writes and f.profile().coinBalance == 20 and f.profile().creatures.p1.totalXP == 0, "loss has no penalty or reward")
    check(not f.battle.inBattle(1), "loss releases reservation")

    f = fixture({fullEggs = true, xp = 60, wins = 4, stars = 3})
    view = f.win(f.start().data.battle)
    profile = f.profile()
    check(profile.basicEggCount == 20 and profile.pendingEggRewards == 1, "full inventory keeps guaranteed egg pending")
    check(profile.creatures.p1.totalXP == 80 and originalRules.stars(3, profile.creatures.p1.winsSinceCreation) == 4, "level five and inherited stars progression")
    view = f.start().data.battle
    check(#view.player.skills == 2, "growth unlock appears in next battle")

    f = fixture({xp = 480, wins = 25, stars = 5, firstDone = true, draw = 0.9})
    f.win(f.start().data.battle)
    profile = f.profile()
    check(profile.creatures.p1.totalXP == 480 and originalRules.stars(5, profile.creatures.p1.winsSinceCreation) == 5, "XP and stars stay capped")
    check(profile.coinBalance == 40 and profile.basicEggCount == 1 and profile.creatures.p1.winsSinceCreation == 26, "cap still gives coins and wins; failed egg roll")
    f = fixture({firstDone = true, draw = 0.1})
    f.win(f.start().data.battle)
    check(f.profile().basicEggCount == 2 and f.rolls() == 3, "later victory egg roll once")

    f = fixture()
    f.setNear(false)
    reject(f.start(), "OUT_OF_RANGE")
    f.setNear(true)
    reject(f.request("Battle.Start", {creatureId = "missing", encounterId = "TRAINING"}), "CREATURE_NOT_FOUND")
    reject(f.request("Battle.Start", {creatureId = "p1", encounterId = "OTHER"}), "INVALID_INPUT")
    local issued = f.request("Operation.Create", {kind = "Egg.Hatch", params = {}})
    reject(f.start(), "OPERATION_BUSY")
    f.setTime(1070)
    check(f.start().status == "ok", "expired intent allows battle")
    reject(f.request("Operation.Execute", {operationId = issued.data.operationId}), "IN_BATTLE")

    -- Each storage failure is exercised at the reward boundary, not during combat.
    for _, mode in ipairs({"repeat", "before", "prepare", "commit", "takeover", "longOutage"}) do
        f = fixture({firstDone = true})
        view = f.start().data.battle
        while view.enemy.currentHP > 23 do view = f.act(view).data.battle end
        local before = f.profile()
        local calls = f.store.calls
        if mode == "repeat" then f.store.callbackRepeats = 100
        elseif mode == "before" or mode == "longOutage" then f.store.failBefore = true
        elseif mode == "commit" then
            f.store.beforeCall = function(store) if store.calls == calls + 2 then store.failAfter = true end end
        else f.store.failAfter = true end
        response = f.act(view)
        local rolls = f.rolls()
        if mode == "repeat" then
            check(response.data.battle.status == "ended", "100 callback repetitions finish")
        else
            check(response.status == "pending" and response.data.battle.status == "resolving", mode .. " reward remains pending")
            check(f.battle.inBattle(1), "resolving blocks new economic work")
            reject(f.start(), "IN_BATTLE")
            f.store.failBefore, f.store.failAfter, f.store.beforeCall = false, false, nil
            if mode == "takeover" then
                f.battle.forget(1)
                f.setTime(1300)
                local replacement = modules.Repository.new({schema = f.schema, store = f.store, sessionId = "replacement", rulesVersion = catalog.rulesVersion, clock = function() return 1300 end, newId = function() return "unused" end})
                check(replacement.open(1).status == "ok", "takeover recovers prepared reward")
                profile = replacement.snapshot(1).profile
                check(profile.coinBalance == before.coinBalance + 20 and profile.creatures.p1.winsSinceCreation == 1, "takeover exactly once")
                check(f.repository.execute(1, response.data.battle.rewardOperationId, "battle:" .. view.battleId).status == "rejected", "old session fenced")
            else
                if mode == "longOutage" then f.setTime(1300); check(f.sessions.heartbeat(1).status == "ok", "renew after prolonged outage") end
                check(f.request("Battle.Get").data.battle.status == "ended", mode .. " recovers reward")
                check(f.profile().coinBalance == before.coinBalance + 20 and f.profile().creatures.p1.winsSinceCreation == 1, mode .. " reward once")
            end
        end
        check(f.rolls() == rolls, mode .. " recovery never rerolls")
    end

    -- Playable journey: hatch, train to Growth unlock, preview inheritance, mix.
    f = fixture({xp = 60})
    local eggIntent = f.request("Operation.Create", {kind = "Egg.Hatch", params = {}})
    local hatched = f.request("Operation.Execute", {operationId = eggIntent.data.operationId})
    check(hatched.status == "committed", "journey hatch")
    f.win(f.start().data.battle)
    local preview = f.request("Mix.Preview", {parentIds = {"p1", hatched.data.result.creature.instanceId}})
    check(preview.status == "ok", "journey mix after reward")
    local inherited = false
    for _, candidate in ipairs(preview.data.candidates) do
        for _, outcome in ipairs(candidate.inheritedOutcomes) do if outcome.skillId == "U01" then inherited = true end end
    end
    check(inherited, "new Growth skill enters inheritance pool")
    local mixIntent = f.request("Operation.Create", {kind = "Mix.Commit", params = {previewId = preview.data.previewId}})
    local mixed = f.request("Operation.Execute", {operationId = mixIntent.data.operationId})
    check(mixed.status == "committed" and mixed.data.result.creature.level == 1 and f.profile().coinBalance == 20, "journey reward funds mix")

    f = fixture({wins = 9007199254740991})
    view = f.win(f.start().data.battle)
    check(view.status == "resolving" and f.profile().creatures.p1.winsSinceCreation == 9007199254740991, "overflow holds reward without wrapping")
    check(f.profile().coinBalance == 20, "overflow has no partial coin grant")
    reject(f.start(), "IN_BATTLE")

    f = fixture()
    local pendingIntent = f.request("Operation.Create", {kind = "Egg.Hatch", params = {}})
    f.store.failAfter = true
    check(f.request("Operation.Execute", {operationId = pendingIntent.data.operationId}).status == "pending", "pending mutation fixture")
    check(f.start().status == "pending", "cannot start during uncertain/prepared mutation")
    f.store.failAfter = false
    check(f.repository.recover(1).status == "ok" and f.start().status == "ok", "start after recovery")
    local blocked = f.repository.issue(1, "Egg.Buy", "direct", f.profile().profileVersion, function() return {result = {}} end)
    check(blocked.status == "rejected" and blocked.code == "IN_BATTLE", "repository reservation guards direct economic issue")

    f = fixture()
    view = f.start().data.battle
    -- Same-second, fresh requests cannot exceed the shared battle action/forfeit bucket.
    local function badAction(action)
        return f.request(action, {battleId = view.battleId, expectedRevision = 999}, 1, nil, true)
    end
    reject(badAction("Battle.Forfeit"), "STALE_BATTLE")
    reject(badAction("Battle.Forfeit"), "STALE_BATTLE")
    reject(badAction("Battle.Action"), "RATE_LIMITED")
    return {checks = checks}
end
return Suite
