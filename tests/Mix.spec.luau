local Suite = {}
function Suite.run(modules, rules, catalog)
    local checks = 0
    local function check(value, label) checks += 1; assert(value, label) end
    local function fixture()
        local time, serial, rolls, battle = 1000, 0, 0, false
        local schema = modules.Schema.new(rules, function() return 100 end)
        local store = modules.MemoryStore.new(schema.copy)
        local function newId() serial += 1; return "mix-" .. serial end
        local repository = modules.Repository.new({schema = schema, store = store, sessionId = "mix-test", rulesVersion = catalog.rulesVersion, clock = function() return time end, newId = newId})
        local sessions = modules.Session.new(repository)
        check(sessions.join(1).status == "ok", "join")
        check(sessions.join(2).status == "ok", "second join")
        local function seed(userId, count, coins)
            local profile = sessions.snapshot(userId).profile
            local issued = repository.issue(userId, "BattleReward", "seed", profile.profileVersion, function(id)
                local creatures = {}
                for index = 1, count do table.insert(creatures, {instanceId = "p" .. index, definitionId = if index % 2 == 0 then "C02" else "C01", totalXP = 80, startingPotentialStars = 2, winsSinceCreation = 0, isLocked = false, createdAt = time, originOperationId = id}) end
                return {createCreatures = creatures, coinDelta = coins or 0, result = {}}
            end)
            check(repository.execute(userId, issued.operationId, "seed").status == "committed", "seed")
        end
        seed(1, 2)
        local mix = modules.Mix.new({rules = rules, catalog = catalog, views = modules.Views, inBattle = function() return battle end, nextNumber = function() rolls += 1; return 0.1 end, newId = newId})
        local dispatcher = modules.Dispatcher.new({repository = repository, sessions = sessions, rules = rules, catalog = catalog, views = modules.Views, clock = function() return time end, mix = mix, operationBuilders = {["Mix.Commit"] = mix.build}})
        local function request(action, args, userId, requestId)
            time += 1
            return dispatcher.handle(userId or 1, {apiVersion = 1, requestId = requestId or newId(), action = action, args = args or {}})
        end
        local function preview(ids, userId)
            return request("Mix.Preview", {parentIds = ids or {"p1", "p2"}}, userId)
        end
        local function create(id, userId, requestId) return request("Operation.Create", {kind = "Mix.Commit", params = {previewId = id}}, userId, requestId) end
        local function execute(id) return request("Operation.Execute", {operationId = id}) end
        return {schema = schema, store = store, repository = repository, sessions = sessions, mix = mix, dispatcher = dispatcher, request = request, preview = preview, create = create, execute = execute, rolls = function() return rolls end, seed = seed,
            setTime = function(value) time = value end, setBattle = function(value) battle = value end,
            profile = function() return sessions.snapshot(1).profile end}
    end
    local function rejected(response, code)
        check(response.status == "rejected" and response.error.code == code, "expected " .. code .. ", got " .. tostring(response.status) .. "/" .. tostring(response.error and response.error.code))
    end
    local f = fixture()
    local beforeWrites = f.store.writes
    local view = f.preview().data
    check(view ~= nil and view.cost == 20 and #view.parentIds == 2, "preview view supports string parent IDs")
    check(view.parentIds[1] == "p1" and #view.candidates > 0 and #view.rarityProbabilities == 4, "preview outcomes")
    local probability = 0
    for _, candidate in ipairs(view.candidates) do
        probability += candidate.probability
        check(#candidate.starsOutcomes > 0 and #candidate.inheritedOutcomes > 0, "inheritance distributions")
    end
    check(math.abs(probability - 1) < 1e-10, "probabilities sum to one")
    check(f.rolls() == 0 and f.store.writes == beforeWrites, "preview is read only and never rolls")
    local issued = f.create(view.previewId, 1, "create-once")
    check(issued.status == "ok" and f.rolls() == 0, "create never rolls")
    check(f.create(view.previewId, 1, "create-once").data.operationId == issued.data.operationId, "create replay")
    f.store.callbackRepeats = 100
    local committed = f.execute(issued.data.operationId)
    check(committed.status == "committed", "mix commits")
    local profile = f.profile()
    local child = committed.data.result.creature
    check(profile.coinBalance == 0 and profile.creatures.p1 == nil and profile.creatures.p2 == nil, "consume parents and exact price")
    check(profile.creatures[child.instanceId] ~= nil and child.level == 1 and child.totalXP == 0, "new child starts level one")
    check(#committed.data.result.consumedIds == 2 and committed.data.result.coinDelta == -20, "receipt matches contract")
    local rolls = f.rolls()
    f.setTime(1070)
    check(f.execute(issued.data.operationId).status == "committed" and f.rolls() == rolls, "receipt beats expired preview")
    rejected(f.create(view.previewId), "STALE_PREVIEW")

    f = fixture()
    rejected(f.preview({"p1", "p1"}), "INVALID_INPUT")
    rejected(f.preview({"p1"}), "INVALID_INPUT")
    rejected(f.preview({"p1", "p2", "p3"}), "INVALID_INPUT")
    rejected(f.preview({"p1", "missing"}), "CREATURE_NOT_FOUND")
    rejected(f.preview(nil, 2), "CREATURE_NOT_FOUND")
    view = f.preview().data
    rejected(f.create(view.previewId, 2), "STALE_PREVIEW")
    rejected(f.create("invented"), "STALE_PREVIEW")
    f.setBattle(true)
    rejected(f.preview(), "IN_BATTLE")
    f.setBattle(false)
    local locked = table.clone(f.profile().creatures.p1); locked.isLocked = true
    local token = f.repository.issue(1, "Creature.SetLocked", "lock", f.profile().profileVersion, function() return {updateCreatures = {locked}, result = {}} end)
    check(f.repository.execute(1, token.operationId, "lock").status == "committed", "lock fixture")
    rejected(f.preview(), "CREATURE_LOCKED")
    rejected(f.create(view.previewId), "STALE_PREVIEW")

    f = fixture()
    view = f.preview().data
    issued = f.create(view.previewId)
    f.setTime(view.expiresAt - 1)
    rejected(f.execute(issued.data.operationId), "STALE_PREVIEW")
    check(f.rolls() == 0 and f.profile().coinBalance == 20, "expired preview preserves resources and RNG")

    f = fixture()
    f.setTime(1075)
    view = f.preview().data
    issued = f.create(view.previewId)
    f.setTime(1080)
    rejected(f.execute(issued.data.operationId), "STALE_PREVIEW")
    check(f.profile().creatures.p1 ~= nil and f.rolls() == 0, "phase change rejected before roll")

    f = fixture()
    f.setTime(1075)
    view = f.preview().data
    issued = f.create(view.previewId)
    -- World changes between plan creation and the actual storage callback.
    f.store.beforeCall = function() f.setTime(1080) end
    rejected(f.execute(issued.data.operationId), "STALE_PREVIEW")
    f.store.beforeCall = nil
    check(f.profile().coinBalance == 20 and f.profile().creatures.p1 ~= nil, "callback freshness check prevents stale commit")

    f = fixture()
    view = f.preview().data
    issued = f.create(view.previewId)
    f.store.failAfter = true
    check(f.execute(issued.data.operationId).status == "pending", "lost prepare is pending")
    rolls = f.rolls()
    f.store.failAfter = false
    f.setTime(1081)
    check(f.repository.recover(1).status == "ok", "recover after preview expiry and phase change")
    check(f.execute(issued.data.operationId).status == "committed" and f.rolls() == rolls, "recovery never rerolls")
    check(f.profile().coinBalance == 0 and f.profile().creatures.p1 == nil, "recovery applies exactly once")

    f = fixture()
    view = f.preview().data
    issued = f.create(view.previewId)
    f.store.failAfter = true
    check(f.execute(issued.data.operationId).status == "pending", "prepare response lost before session takeover")
    f.store.failAfter = false
    rolls = f.rolls()
    f.setTime(1200)
    local replacement = modules.Repository.new({schema = f.schema, store = f.store, sessionId = "replacement", rulesVersion = catalog.rulesVersion, clock = function() return 1200 end, newId = function() return "unused" end})
    check(replacement.open(1).status == "ok", "replacement session recovers prepared operation")
    local recovered = replacement.snapshot(1).profile
    check(recovered.coinBalance == 0 and recovered.creatures.p1 == nil and recovered.creatures[issued.data.operationId] ~= nil, "session takeover keeps committed child")
    check(f.rolls() == rolls, "new session cannot reroll")

    f = fixture()
    view = f.preview().data
    issued = f.create(view.previewId)
    f.store.failBefore = true
    check(f.execute(issued.data.operationId).status == "pending", "outage before prepare")
    rolls = f.rolls()
    f.store.failBefore = false
    check(f.execute(issued.data.operationId).status == "committed", "same operation retries after outage")
    check(f.rolls() == rolls, "unaccepted retry preserves materialized random plan")

    f = fixture()
    -- Full collection still permits net -1 creature from mixing.
    profile = f.profile()
    for index = 3, 30 do local creature = table.clone(profile.creatures.p1); creature.instanceId = "p" .. index; profile.creatures[creature.instanceId] = creature end
    local v = f.mix.preview(1, profile, {parentIds = {"p1", "p2"}}, 1000)
    local plan = f.mix.build("full-op", profile, {previewId = v.previewId}, 1001, 1, false)
    local projected = f.schema.apply(profile, plan, "full-op", "Mix.Commit")
    local count = 0; for _ in pairs(projected.creatures) do count += 1 end
    check(count == 29, "mix allowed at collection capacity")
    profile.coinBalance = 19
    local ok, failure = pcall(f.mix.build, "poor-op", profile, {previewId = v.previewId}, 1001, 1, false)
    check(not ok and failure.code == "INSUFFICIENT_FUNDS", "insufficient funds")
    f.mix.forget(1)
    ok, failure = pcall(f.mix.validate, 1, profile, {previewId = v.previewId}, 1001)
    check(not ok and failure.code == "STALE_PREVIEW", "disconnect clears preview")
    return {checks = checks}
end
return Suite
