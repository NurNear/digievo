local Suite = {}
function Suite.run(modules, originalRules, catalog)
    local checks, faultRuns = 0, 0
    local function check(value, label) checks += 1; assert(value, label) end
    local function rejected(result, code)
        check(result.status == "rejected" and (result.code or (result.error and result.error.code)) == code, "Expected " .. code)
    end
    local function fixture(measure)
        local time, serial, rolls = 1000, 0, 0
        local rules = table.clone(originalRules)
        rules.stats = function(creature)
            return if creature.instanceId == "p1" then {hp = 1000, atk = 1000, def = 20, spd = 16} else originalRules.stats(creature)
        end
        local schema = modules.Schema.new(rules, measure or function() return 100 end)
        local store = modules.MemoryStore.new(schema.copy)
        local function nextId() serial += 1; return "safety-" .. serial end
        local function repo(session)
            return modules.Repository.new({schema = schema, store = store, sessionId = session, rulesVersion = catalog.rulesVersion,
                clock = function() return time end, newId = nextId})
        end
        local repository = repo("first")
        local sessions = modules.Session.new(repository)
        check(sessions.join(1).status == "ok", "join fixture")
        local token = repository.issue(1, "BattleReward", "seed", repository.snapshot(1).profile.profileVersion, function(id)
            local pets = {}
            for i = 1, 2 do table.insert(pets, {instanceId = "p" .. i, definitionId = "C01", totalXP = 0,
                startingPotentialStars = 0, winsSinceCreation = 0, isLocked = false, createdAt = time, originOperationId = id}) end
            return {createCreatures = pets, coinDelta = 40, firstVictoryEggGranted = true, result = {}}
        end)
        check(repository.execute(1, token.operationId, "seed").status == "committed", "seed fixture")
        local opts = {rules = rules, catalog = catalog, views = modules.Views, repository = repository, copy = schema.copy,
            clock = function() return time end, nearTraining = function() return true end, nearNode = function() return true end,
            newId = nextId, nextNumber = function() rolls += 1; return 0.1 end}
        local battle = modules.Battle.new(opts)
        opts.inBattle = battle.inBattle
        local mix = modules.Mix.new(opts)
        local builders = modules.Actions.new(opts)
        builders["Mix.Commit"] = mix.build
        local dispatcher = modules.Dispatcher.new({repository = repository, sessions = sessions, rules = rules, catalog = catalog, views = modules.Views,
            clock = function() return time end, battle = battle, mix = mix, operationBuilders = builders})
        local function request(action, args, id, userId, frozen)
            if not frozen then time += 1 end
            return dispatcher.handle(userId or 1, {apiVersion = 1, requestId = id or nextId(), action = action, args = args or {}})
        end
        return {schema = schema, store = store, repo = repository, sessions = sessions, battle = battle, dispatcher = dispatcher, request = request, newRepo = repo,
            advance = function(seconds) time += seconds end, time = function() return time end, rolls = function() return rolls end,
            stored = function() return store.values["player:1"] end}
    end
    local function operation(f, kind)
        if kind == "reward" then
            local view = f.request("Battle.Start", {creatureId = "p1", encounterId = "TRAINING"}).data.battle
            return "reward:" .. view.battleId, function()
                return f.request("Battle.Action", {battleId = view.battleId, expectedRevision = view.revision, command = "SKILL", skillId = "S01"})
            end
        end
        local params = {}
        if kind == "mix" then params.previewId = f.request("Mix.Preview", {parentIds = {"p1", "p2"}}).data.previewId end
        local created = f.request("Operation.Create", {kind = if kind == "mix" then "Mix.Commit" else "Egg.Hatch", params = params})
        check(created.status == "ok", "issue operation")
        local id = created.data.operationId
        return id, function() return f.request("Operation.Execute", {operationId = id}) end
    end
    local function verify(f, kind, id, before)
        local profile = f.stored()
        check(profile.preparedOperation == nil, "no leftover prepare")
        check(profile.lastAppliedSeq == before.lastAppliedSeq + 1, "exactly one commit")
        local receipt
        for _, item in ipairs(profile.receipts) do if item.operationId == id then receipt = item end end
        check(receipt ~= nil, "original receipt present")
        if kind == "hatch" then
            check(profile.basicEggCount == before.basicEggCount - 1 and profile.coinBalance == before.coinBalance, "one egg consumed")
            check(profile.creatures[id] ~= nil, "one original hatch result")
        elseif kind == "mix" then
            check(profile.coinBalance == before.coinBalance - 20 and profile.creatures.p1 == nil and profile.creatures.p2 == nil, "parents and price consumed once")
            check(profile.creatures[id] ~= nil, "one original mix child")
        else
            check(profile.coinBalance == before.coinBalance + 20 and profile.creatures.p1.totalXP == 20, "one reward and XP")
            check(profile.creatures.p1.winsSinceCreation == 1 and profile.basicEggCount == before.basicEggCount + 1, "one win and egg")
        end
    end
    for _, kind in ipairs({"hatch", "mix", "reward"}) do
        for _, mode in ipairs({"beforePrepare", "afterPrepare", "beforeCommit", "afterCommit", "repeatCallbacks"}) do
            for _ = 1, 100 do
                faultRuns += 1
                local f = fixture()
                local id, execute = operation(f, kind)
                local before, calls = f.schema.copy(f.stored()), f.store.calls
                if mode == "beforePrepare" then f.store.failBefore = true
                elseif mode == "afterPrepare" then f.store.failAfter = true
                elseif mode == "repeatCallbacks" then f.store.callbackRepeats = 100
                else f.store.beforeCall = function(store)
                    if store.calls == calls + 2 then
                        store.failBefore = mode == "beforeCommit"
                        store.failAfter = mode == "afterCommit"
                    end
                end end
                local response = execute()
                local rolls = f.rolls()
                if mode ~= "repeatCallbacks" then
                    check(response.status == "pending", mode .. " returns pending")
                    check(not response.data or not response.data.result, "no unconfirmed result exposed")
                    if mode ~= "afterCommit" then
                        check(f.stored().coinBalance == before.coinBalance and f.stored().basicEggCount == before.basicEggCount, "precommit inventory unchanged")
                    end
                    check(f.request("Profile.Get").status == "pending", "uncertain profile not shown as confirmed")
                    f.store.failBefore, f.store.failAfter, f.store.beforeCall = false, false, nil
                    -- No direct repository recovery: exercise the client's real poll path.
                    response = f.request(if kind == "reward" then "Battle.Get" else "Operation.Get", if kind == "reward" then {} else {operationId = id})
                    check(response.status == (if kind == "reward" then "ok" else "committed"), "poll completes original operation")
                end
                verify(f, kind, id, before)
                check(f.rolls() == rolls, "poll/repeated callbacks never reroll")
                local committedSeq = f.stored().lastAppliedSeq
                for _ = 1, 3 do f.request(if kind == "reward" then "Battle.Get" else "Operation.Get", if kind == "reward" then {} else {operationId = id}) end
                check(f.stored().lastAppliedSeq == committedSeq, "poll replay never repeats mutation")
            end
        end
    end

    -- Real receipt/intent expiry and lost-before-PREPARE behavior.
    local f = fixture()
    local created = f.request("Operation.Create", {kind = "Egg.Hatch", params = {}})
    local expiry = created.data.expiresAt
    f.advance(5)
    local duplicate = f.request("Operation.Create", {kind = "Egg.Hatch", params = {}})
    check(duplicate.data.operationId == created.data.operationId and duplicate.data.expiresAt == expiry, "repeated issue does not extend deadline")
    local beforeExpiry = f.schema.copy(f.stored())
    check(f.request("Operation.Get", {operationId = created.data.operationId}).status == "pending", "reading unexecuted intent does not hatch")
    check(f.rolls() == 0 and f.stored().lastAppliedSeq == beforeExpiry.lastAppliedSeq, "no execute without request")
    f.advance(60)
    rejected(f.request("Operation.Get", {operationId = created.data.operationId}), "EXPIRED_INTENT")
    check(f.stored().basicEggCount == beforeExpiry.basicEggCount, "expiry does not consume egg")

    for _ = 1, 100 do
        faultRuns += 1
        f = fixture()
        local id, execute = operation(f, "mix")
        local before = f.schema.copy(f.stored())
        f.store.failAfter = true
        check(execute().status == "pending", "prepared mix response lost")
        local rolls = f.rolls()
        f.store.failAfter = false
        f.advance(121)
        local oldRepo, replacement = f.repo, f.newRepo("second")
        check(replacement.open(1).status == "ok", "new session recovers after lease expiry")
        verify(f, "mix", id, before)
        local writes = f.store.writes
        rejected(oldRepo.renew(1), "FENCED")
        check(f.store.writes == writes and f.rolls() == rolls, "old owner cannot write/reroll")
        -- Reconnect snapshot shows the original child; starter is not granted twice.
        local rejoined = modules.Session.new(replacement).join(1)
        check(rejoined.status == "ok" and rejoined.profile.creatures[id] ~= nil, "reconnect recovers child")
        check(f.stored().coinBalance == before.coinBalance - 20, "reconnect no extra starter")
    end
    for _ = 1, 100 do
        faultRuns += 1
        f = fixture()
        local id, execute = operation(f, "hatch")
        f.store.failBefore = true
        check(execute().status == "pending", "outage before prepare")
        f.advance(120)
        check(f.request("Operation.Get", {operationId = id}).status == "pending", "120-second outage stays pending")
        check(f.stored().preparedOperation == nil and f.stored().basicEggCount == 1, "no default or guessed result")
        f.store.failBefore = false
        check(f.sessions.heartbeat(1).status == "ok", "session reacquires lease")
        rejected(f.request("Operation.Get", {operationId = id}), "EXPIRED_INTENT")
        check(f.stored().basicEggCount == 1, "expired unprepared work cannot consume after recovery")
    end

    -- Unknown/corrupt future-schema copies must never overwrite their originals.
    for _ = 1, 100 do
        faultRuns += 1
        f = fixture()
        local source = f.schema.copy(f.stored())
        local copy = f.schema.copy(source)
        copy.schemaVersion = 99
        f.store.values["player:1"] = copy
        local writes = f.store.writes
        rejected(f.newRepo("inspect-copy").open(1), "UNSUPPORTED_SCHEMA")
        check(f.store.writes == writes and f.stored().schemaVersion == 99, "unknown schema not rewritten")
        check(source.schemaVersion == 1 and source.coinBalance == 60, "source fixture preserved")
    end

    for _ = 1, 100 do
        faultRuns += 1
        f = fixture()
        local before = f.schema.copy(f.stored())
        f.request("Battle.Start", {creatureId = "p1", encounterId = "TRAINING"})
        f.battle.forget(1)
        check(f.battle.tick(1) == nil and not f.battle.inBattle(1), "disconnect cancels live auto battle")
        check(f.stored().lastAppliedSeq == before.lastAppliedSeq, "disconnect does not reward unfinished fight")
        local id, execute = operation(f, "reward")
        f.store.failAfter = true
        check(execute().status == "pending", "reward prepared before disconnect")
        f.battle.forget(1)
        f.store.failAfter = false
        f.advance(121)
        check(f.newRepo("reward-reconnect").open(1).status == "ok", "new session finishes prepared reward")
        verify(f, "reward", id, before)
    end
    for _ = 1, 100 do
        faultRuns += 1
        local enforceSize = false
        f = fixture(function(profile)
            return if enforceSize and #profile.receipts > 2 then 262145 else 100
        end)
        local id, execute = operation(f, "hatch")
        local writes, before = f.store.writes, f.schema.copy(f.stored())
        enforceSize = true
        rejected(execute(), "PROFILE_TOO_LARGE")
        check(f.store.writes == writes and f.stored().preparedOperation == nil, "oversize projected commit rejected before prepare")
        check(f.stored().basicEggCount == before.basicEggCount and f.stored().creatures[id] == nil, "oversize does not consume or truncate")
    end

    -- Admission includes cached replay and malformed/unknown routes, while a
    -- different player's request still has an independent budget.
    f = fixture()
    local response = f.request("World.Get", {}, "replay", 1, true)
    check(response.status == "ok", "initial read")
    local accepted = 1
    for _ = 1, 999 do
        response = f.request("World.Get", {}, "replay", 1, true)
        check(response.requestId == "replay", "rate-limit response preserves correlation")
        if response.status == "ok" then accepted += 1 else rejected(response, "RATE_LIMITED") end
    end
    check(accepted == 40, "cached responses cannot bypass ingress budget")
    check(f.request("World.Get", {}, "other-player", 2, true).status == "ok", "player isolation under flood")
    f.advance(1)
    check(f.request("World.Get").status == "ok", "budget recovers")
    f = fixture()
    for index = 1, 1000 do
        response = f.request("Unknown." .. index, {}, "bad-" .. index, 1, true)
        rejected(response, if index <= 40 then "INVALID_INPUT" else "RATE_LIMITED")
    end
    f.advance(2)
    local wide = {}
    for i = 1, 1000 do wide["k" .. i] = i end
    rejected(f.request("World.Get", wide), "INVALID_INPUT")
    local cycle = {}; cycle.self = cycle
    rejected(f.request("World.Get", cycle), "INVALID_INPUT")
    rejected(f.request("World.Get", {v = 0/0}), "INVALID_INPUT")
    rejected(f.request("World.Get", {v = string.rep("x", 9000)}), "INVALID_INPUT")
    f.dispatcher.forget(1)
    check(f.request("World.Get", {}, "after-forget", 1, true).status == "ok", "cleanup resets ingress")
    check(f.stored().coinBalance == 60, "malformed flood has no resource effects")
    return {checks = checks, faultRuns = faultRuns}
end
return Suite
