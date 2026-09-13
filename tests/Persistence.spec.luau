local Suite = {}
function Suite.run(modules, rules, measure)
    local checks, faultRuns = 0, 0
    local function check(value, label)
        checks += 1
        assert(value, label)
    end
    local function status(result, expected, code)
        check(result.status == expected, "Expected " .. expected .. ", got " .. tostring(result.status) .. "/" .. tostring(result.code))
        if code then check(result.code == code, "Expected error " .. code .. ", got " .. tostring(result.code)) end
        return result
    end
    -- CLI uses a conservative JSON byte upper bound; Studio injects JSONEncode length.
    local function upperBound(value)
        if type(value) == "table" then
            local bytes = 2
            for key, child in pairs(value) do bytes += #tostring(key) * 6 + 4 + upperBound(child) end
            return bytes
        end
        return if type(value) == "string" then #value * 6 + 2 else 32
    end
    measure = measure or upperBound
    local function fixture(customMeasure)
        local schema = modules.Schema.new(rules, customMeasure or measure)
        local store = modules.MemoryStore.new(schema.copy)
        local time, nextId = 1000, 0
        local function makeRepo(session)
            return modules.Repository.new({ schema=schema, store=store, clock=function() return time end,
                newId=function() nextId += 1; return session .. ":op:" .. nextId end,
                sessionId=session, rulesVersion="mvp-1.0.0" })
        end
        local f = { schema=schema, store=store, repo=makeRepo("A"), makeRepo=makeRepo }
        function f.advance(seconds) time += seconds end
        function f.profile() return store.values["player:1"] end
        return f
    end
    local function starter(f)
        local snapshot = status(f.repo.snapshot(1), "ok").profile
        return status(f.repo.issue(1, "StarterGrant", "starter", snapshot.profileVersion, function()
            return { coinDelta=20, eggDelta=1, starterGrantClaimed=true, result={ coins=20, eggs=1 } }
        end), "ok").operationId
    end
    local function seed(f, count)
        local profile = f.schema.newProfile()
        profile.coinBalance = 20
        profile.starterGrantClaimed = true
        for i = 1, count do
            local key = "parent" .. i
            profile.creatures[key] = { instanceId=key, definitionId="C01", totalXP=80, startingPotentialStars=2,
                winsSinceCreation=0, isLocked=false, createdAt=1, originOperationId="seed" }
        end
        f.store.values["player:1"] = profile
    end
    local function mix(f)
        return status(f.repo.issue(1, "Mix.Commit", "mix:parent1:parent2", 0, function(operationId)
            return { coinDelta=-20, removeIds={ "parent1", "parent2" }, createCreatures={ {
                instanceId="child", definitionId="C03", totalXP=0, startingPotentialStars=0, winsSinceCreation=0,
                isLocked=false, createdAt=1000, originOperationId=operationId,
            } }, result={ childId="child" } }
        end), "ok").operationId
    end
    local function mixed(f)
        local profile = f.profile()
        check(profile.coinBalance == 0 and profile.creatures.parent1 == nil and profile.creatures.parent2 == nil and profile.creatures.child ~= nil, "Atomic 2-to-1 mix")
        check(profile.lastAppliedSeq == 1 and profile.profileVersion == 1 and #profile.receipts == 1 and profile.preparedOperation == nil, "Exactly one committed operation")
        check(profile.creatures.child.originOperationId == profile.receipts[1].operationId, "Recovered original result")
    end

    local f = fixture()
    status(f.repo.open(1), "ok")
    check(f.profile().coinBalance == 0 and not f.profile().starterGrantClaimed, "Open does not silently grant starter")
    local op = starter(f)
    status(f.repo.execute(1, op, "starter"), "committed")
    for _ = 1, 100 do status(f.repo.execute(1, op, "starter"), "committed") end
    check(f.profile().coinBalance == 20 and f.profile().basicEggCount == 1 and #f.profile().receipts == 1, "Starter once across 100 retries")
    status(f.repo.execute(1, op, "different"), "rejected", "IDEMPOTENCY_CONFLICT")
    status(f.repo.release(1), "ok")
    f.repo = f.makeRepo("B")
    status(f.repo.open(1), "ok")
    check(f.profile().starterGrantClaimed and f.profile().coinBalance == 20, "Starter survives repository/session replacement")
    status(f.repo.issue(1, "StarterGrant", "starter-again", 1, function() return { coinDelta=20, eggDelta=1, starterGrantClaimed=true, result={} } end), "rejected", "STARTER_ALREADY_GRANTED")
    local snapshot = status(f.repo.snapshot(1), "ok").profile
    snapshot.coinBalance = 999
    check(f.profile().coinBalance == 20, "Snapshots cannot mutate stored data")

    for _ = 1, 100 do
        for _, fault in ipairs({ "beforePrepare", "afterPrepare", "beforeCommit", "afterCommit" }) do
            faultRuns += 1
            local test = fixture()
            seed(test, 2); status(test.repo.open(1), "ok")
            local mixId = mix(test)
            if fault == "beforePrepare" then test.store.failBefore = true end
            if fault == "afterPrepare" then test.store.failAfter = true end
            if fault == "beforeCommit" or fault == "afterCommit" then
                test.store.beforeCall = function(backend)
                    if backend.calls == 3 then
                        backend.failBefore = fault == "beforeCommit"
                        backend.failAfter = fault == "afterCommit"
                    end
                end
            end
            status(test.repo.execute(1, mixId, "mix:parent1:parent2"), "pending", "STORAGE_UNAVAILABLE")
            status(test.repo.snapshot(1), "pending")
            status(test.repo.issue(1, "Egg.Buy", "new-request", 0, function() return { result={} } end), "pending")
            if fault ~= "afterCommit" then check(test.profile().coinBalance == 20 and test.profile().creatures.parent1 ~= nil, "Uncommitted resources remain") end
            test.store.failBefore, test.store.failAfter, test.store.beforeCall = false, false, nil
            status(test.repo.recover(1), "ok")
            status(test.repo.execute(1, mixId, "mix:parent1:parent2"), "committed")
            mixed(test)
            status(test.repo.issue(1, "Egg.Buy", "next-after-recovery", 1, function() return { result={} } end), "ok")
        end
    end

    f = fixture(); seed(f, 2); status(f.repo.open(1), "ok")
    op = mix(f)
    f.store.callbackRepeats = 100
    status(f.repo.prepare(1, op, "mix:parent1:parent2"), "prepared")
    check(f.profile().coinBalance == 20 and f.profile().creatures.parent1 ~= nil, "Prepare reserves without consuming")
    f.advance(61)
    status(f.repo.execute(1, op, "mix:parent1:parent2"), "committed")
    mixed(f)
    check(f.store.writes == 3, "100 callback invocations still only open/prepare/commit writes")

    f = fixture(); seed(f, 2); status(f.repo.open(1), "ok"); op = mix(f)
    status(f.repo.prepare(1, op, "mix:parent1:parent2"), "prepared")
    local oldRepo, newRepo = f.repo, f.makeRepo("B")
    status(newRepo.open(1), "rejected", "LEASE_HELD")
    f.advance(121)
    status(newRepo.open(1), "ok")
    mixed(f)
    local writes = f.store.writes
    status(oldRepo.renew(1), "rejected", "FENCED")
    check(f.store.writes == writes and f.profile().lease.generation == 2, "Old generation cannot write after takeover")

    f = fixture(); seed(f, 2); status(f.repo.open(1), "ok"); op = mix(f)
    newRepo = f.makeRepo("C")
    f.store.beforeCommit = function(backend)
        backend.beforeCommit = nil
        f.advance(121)
        status(newRepo.open(1), "ok")
    end
    status(f.repo.prepare(1, op, "mix:parent1:parent2"), "rejected", "FENCED")
    check(f.profile().coinBalance == 20 and f.profile().preparedOperation == nil and f.profile().lease.sessionId == "C", "Callback rechecks fencing after concurrent takeover")

    f = fixture(); status(f.repo.open(1), "ok"); op = starter(f)
    f.store.failAfter = true
    status(f.repo.prepare(1, op, "starter"), "pending")
    f.store.failAfter = false; f.store.failBefore = true; f.advance(120)
    status(f.repo.recover(1), "pending")
    check(f.profile().coinBalance == 0 and f.profile().preparedOperation.operationId == op, "120-second outage retains prepared result")
    f.store.failBefore = false
    status(f.repo.open(1), "ok")
    check(f.profile().coinBalance == 20 and f.profile().lastAppliedSeq == 1, "Reacquire and recover after expired lease")

    f = fixture(); status(f.repo.open(1), "ok"); op = starter(f)
    f.advance(60)
    status(f.repo.execute(1, op, "starter"), "rejected", "EXPIRED_INTENT")
    check(f.profile().coinBalance == 0 and f.profile().preparedOperation == nil, "Expired unprepared intent has no effect")
    status(f.repo.execute(1, "never-issued", "starter"), "rejected", "STALE_OPERATION")
    status(f.repo.issue(1, "Egg.Buy", "stale", 99, function() return { result={} } end), "rejected", "STALE_PROFILE")

    f = fixture(); status(f.repo.open(1), "ok")
    local reentered
    f.store.beforeCall = function() reentered = f.repo.recover(1) end
    status(f.repo.renew(1), "ok")
    status(reentered, "pending", "BUSY")
    check(f.profile().profileVersion == 0 and f.profile().lastAppliedSeq == 0, "Heartbeat does not stale domain version")

    f = fixture(); f.store.failBefore = true
    status(f.repo.open(1), "pending")
    check(f.profile() == nil, "Backend load error never creates default")
    f.store.failBefore = false; status(f.repo.open(1), "ok")
    f.profile().schemaVersion = 99
    writes = f.store.writes
    status(f.repo.open(1), "rejected", "UNSUPPORTED_SCHEMA")
    check(f.profile().schemaVersion == 99 and f.store.writes == writes, "Unknown schema is not overwritten")
    f = fixture(); local corrupt = f.schema.newProfile(); corrupt.coinBalance = -1; f.store.values["player:1"] = corrupt
    status(f.repo.open(1), "rejected", "INVALID_INTEGER")
    check(f.profile().coinBalance == -1 and f.store.writes == 0, "Invalid profile is quarantined, not reset")

    f = fixture(function(profile) return if #profile.receipts > 0 then 262145 else 100 end)
    status(f.repo.open(1), "ok"); op = starter(f); writes = f.store.writes
    status(f.repo.prepare(1, op, "starter"), "rejected", "PROFILE_TOO_LARGE")
    check(f.store.writes == writes and not f.profile().preparedOperation, "Oversized projected commit rejected before prepare")
    f = fixture(); status(f.repo.open(1), "ok")
    status(f.repo.issue(1, "Egg.Buy", "huge", 0, function() return { result={ text=string.rep("x", 270000) } } end), "ok")
    op = f.repo.issue(1, "Egg.Buy", "huge", 0, function() error("Must not rebuild same intent") end).operationId
    status(f.repo.prepare(1, op, "huge"), "rejected", "PROFILE_TOO_LARGE")

    f = fixture(); status(f.repo.open(1), "ok")
    local firstId
    for index = 1, 105 do
        local token = status(f.repo.issue(1, "BattleReward", "reward:" .. index, index - 1, function() return { coinDelta=1, result={ win=index } } end), "ok")
        firstId = firstId or token.operationId
        status(f.repo.execute(1, token.operationId, "reward:" .. index), "committed")
    end
    check(#f.profile().receipts == 100 and f.profile().lastAppliedSeq == 105 and f.profile().coinBalance == 105, "Receipt retention preserves high watermark")
    status(f.repo.execute(1, firstId, "reward:1"), "rejected", "STALE_OPERATION")

    f = fixture(); seed(f, 2); f.profile().creatures.parent1.isLocked = true; status(f.repo.open(1), "ok")
    status(f.repo.issue(1, "Mix.Commit", "locked", 0, function() return { removeIds={ "parent1", "parent2" }, result={} } end), "rejected", "CREATURE_LOCKED")
    f = fixture(); status(f.repo.open(1), "ok")
    status(f.repo.issue(1, "Egg.Buy", "overspend", 0, function() return { coinDelta=-1, result={} } end), "rejected", "INVALID_INTEGER")
    status(f.repo.issue(1, "Egg.Buy", "capacity", 0, function() return { eggDelta=21, result={} } end), "rejected", "INVALID_INTEGER")
    local cyclic = {}; cyclic.self = cyclic
    check(not pcall(f.schema.copy, cyclic), "Cyclic data rejected")
    check(not pcall(f.schema.copy, { [1]="a", [3]="b" }), "Sparse arrays rejected")
    check(not pcall(f.schema.copy, { value=0/0 }), "NaN rejected")

    local contacted = 0
    f = fixture()
    local sessions = modules.Session.new(f.repo)
    status(sessions.join(1), "ok")
    check(f.profile().coinBalance == 20 and f.profile().basicEggCount == 1, "Lifecycle grants starter on join")
    f.advance(30)
    status(sessions.heartbeat(1), "ok")
    check(f.profile().lease.expiresAt == 1150 and f.profile().profileVersion == 1, "Lifecycle renews every 30 seconds without domain version change")
    status(sessions.leave(1), "ok")
    status(sessions.heartbeat(1), "rejected", "SESSION_CLOSED")
    status(sessions.join(1), "ok")
    check(f.profile().coinBalance == 20 and #f.profile().receipts == 1, "Rejoin does not repeat starter grant")
    f.store.failBefore = true
    status(sessions.heartbeat(1), "pending")
    status(sessions.snapshot(1), "pending")
    f.store.failBefore = false
    status(sessions.heartbeat(1), "ok")
    check(f.profile().coinBalance == 20, "Lifecycle recovers after storage failure")

    f = fixture()
    f.store.beforeCall = function(backend) backend.failAfter = backend.calls == 3 end
    sessions = modules.Session.new(f.repo)
    status(sessions.join(1), "pending")
    f.store.beforeCall, f.store.failAfter = nil, false
    status(sessions.heartbeat(1), "ok")
    status(f.repo.issue(1, "Egg.Buy", "after-lost-starter-response", 1, function() return { result={} } end), "ok")
    check(f.profile().coinBalance == 20 and #f.profile().receipts == 1, "Lost starter response does not duplicate grant or block next intent")

    local runtime = { isStudio=true, gameId=123, placeId=456, getStore=function() contacted += 1; return {} end }
    check(not pcall(modules.RobloxStore.new, { mode="TestOnline", universeId=0, placeId=456, namespace="RobloxMVP_Test_v1" }, runtime), "Unknown environment rejected")
    check(not pcall(modules.RobloxStore.new, { mode="TestOnline", universeId=999, placeId=456, namespace="RobloxMVP_Test_v1" }, runtime), "Wrong universe rejected")
    check(not pcall(modules.RobloxStore.new, { mode="TestOnline", universeId=123, placeId=456, namespace="Production" }, runtime), "Production namespace rejected")
    check(contacted == 0, "Environment rejection occurs before storage access")
    local sleeps, attempts = {}, 0
    local backend = {}
    function backend:UpdateAsync(_, transform)
        attempts += 1
        if attempts < 3 then error("temporary outage") end
        local value, users, metadata = transform({ value=1 }, { GetUserIds=function() return { 7 } end, GetMetadata=function() return { tag="keep" } end })
        check(users[1] == 7 and metadata.tag == "keep", "Adapter preserves key metadata")
        return value
    end
    runtime.getStore = function() return backend end
    runtime.hasBudget = function() return true end
    runtime.sleep = function(seconds) table.insert(sleeps, seconds) end
    runtime.jitter = function() return 0 end
    local adapter = modules.RobloxStore.new({ mode="TestOnline", universeId=123, placeId=456, namespace="RobloxMVP_Test_v1" }, runtime)
    local value = adapter:UpdateAsync("player:1", function(current) return current end)
    check(value.value == 1 and attempts == 3 and sleeps[1] == 1 and sleeps[2] == 2, "Bounded retry with backoff")
    runtime.hasBudget = function() return false end
    sleeps = {}; attempts = 0
    check(not pcall(function() adapter:UpdateAsync("player:1", function() return {} end) end), "No budget leaves operation pending")
    check(attempts == 0 and #sleeps == 4 and sleeps[4] == 8, "Budget checked and retries bounded")

    return { checks=checks, faultRuns=faultRuns }
end
return Suite
