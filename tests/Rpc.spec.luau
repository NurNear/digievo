local Suite = {}

function Suite.run(modules, rules, catalog)
    local checks = 0
    local function check(value, label)
        checks += 1
        assert(value, label)
    end
    local function status(response, expected, code)
        check(response.status == expected, "Expected " .. expected .. ", got " .. tostring(response.status))
        if code then check(response.error and response.error.code == code, "Expected error " .. code) end
        return response
    end
    local function fixture()
        local schema = modules.Schema.new(rules, function() return 100 end)
        local store = modules.MemoryStore.new(schema.copy)
        local time, nextId = 1000, 0
        local repository = modules.Repository.new({
            schema = schema,
            store = store,
            sessionId = "rpc-session",
            rulesVersion = catalog.rulesVersion,
            clock = function() return time end,
            newId = function()
                nextId += 1
                return "rpc-op-" .. tostring(nextId)
            end,
        })
        local sessions = modules.Session.new(repository)
        local dispatcher = modules.Dispatcher.new({
            repository = repository,
            sessions = sessions,
            rules = rules,
            catalog = catalog,
            views = modules.Views,
            clock = function() return time end,
            operationBuilders = {
                ["Egg.Buy"] = function(_, profile, params)
                    if params.quantity ~= 1 then error({ code = "INVALID_INPUT" }, 0) end
                    if profile.coinBalance < catalog.economy.eggPrice then error({ code = "INSUFFICIENT_FUNDS" }, 0) end
                    if profile.basicEggCount >= catalog.economy.eggCapacity then error({ code = "CAPACITY_FULL" }, 0) end
                    return { coinDelta = -catalog.economy.eggPrice, eggDelta = 1, result = { coinDelta = -catalog.economy.eggPrice, eggDelta = 1 } }
                end,
            },
        })
        return { schema = schema, store = store, repository = repository, sessions = sessions, dispatcher = dispatcher, advance = function(seconds) time += seconds end }
    end
    local function request(id, action, args)
        return { apiVersion = 1, requestId = id, action = action, args = args or {} }
    end

    local f = fixture()
    status(f.sessions.join(1), "ok")
    local profile = status(f.dispatcher.handle(1, request("r1", "Profile.Get")), "ok").data
    check(profile.coinBalance == 20 and profile.basicEggCount == 1, "Profile view exposes starter state")
    check(profile.lease == nil and profile.preparedOperation == nil and profile.creatures ~= nil, "Profile view hides internal fields")
    check(#profile.nodes == 3 and profile.capacity.creatures == 30 and profile.capacity.eggs == 20, "Profile view includes capacities and nodes")

    local world = status(f.dispatcher.handle(1, request("r2", "World.Get")), "ok").data
    check(world.phaseId == "1:2" and world.timeOfDay == "Day" and world.weather == "Rain", "World view derives server phase")

    status(f.dispatcher.handle(1, { apiVersion = 2, requestId = "bad-version", action = "Profile.Get", args = {} }), "rejected", "UNSUPPORTED_VERSION")
    status(f.dispatcher.handle(1, { apiVersion = 1, requestId = "bad-extra", action = "Profile.Get", args = {}, extra = true }), "rejected", "INVALID_INPUT")
    status(f.dispatcher.handle(1, request("bad-action", "Unknown.Route")), "rejected", "INVALID_INPUT")
    status(f.dispatcher.handle(999, request("not-open", "Profile.Get")), "pending")

    f = fixture()
    status(f.sessions.join(1), "ok")
    local create = status(f.dispatcher.handle(1, request("buy-create", "Operation.Create", { kind = "Egg.Buy", params = { quantity = 1 } })), "rejected", "INSUFFICIENT_FUNDS")
    check(create.error.retry == "none", "Insufficient funds is not retried")
    local starterSnapshot = status(f.sessions.snapshot(1), "ok").profile
    check(starterSnapshot.coinBalance == 20 and starterSnapshot.basicEggCount == 1, "Rejected buy does not mutate resources")

    local grant = status(f.repository.issue(1, "BattleReward", "seed-coins", starterSnapshot.profileVersion, function()
        return { coinDelta = 40, result = { coinDelta = 40 } }
    end), "ok")
    status(f.repository.execute(1, grant.operationId, "seed-coins"), "committed")
    local issued = status(f.dispatcher.handle(1, request("buy-ok", "Operation.Create", { kind = "Egg.Buy", params = { quantity = 1 } })), "ok")
    check(type(issued.data.operationId) == "string" and issued.data.expiresAt == 1060, "Operation.Create returns server intent")
    check(status(f.dispatcher.handle(1, request("buy-ok", "Operation.Create", { kind = "Egg.Buy", params = { quantity = 1 } })), "ok").data.operationId == issued.data.operationId, "Request replay returns same operation")
    status(f.dispatcher.handle(1, request("buy-ok", "Operation.Create", { kind = "Egg.Buy", params = { quantity = 2 } })), "rejected", "IDEMPOTENCY_CONFLICT")
    status(f.dispatcher.handle(1, request("op-get-unaccepted", "Operation.Get", { operationId = issued.data.operationId })), "pending")
    local committed = status(f.dispatcher.handle(1, request("buy-execute", "Operation.Execute", { operationId = issued.data.operationId })), "committed")
    check(committed.profileVersion == 3 and committed.data.kind == "Egg.Buy" and committed.data.result.eggDelta == 1, "Execute commits through repository")
    check(status(f.dispatcher.handle(1, request("buy-execute", "Operation.Execute", { operationId = issued.data.operationId })), "committed").data.operationId == issued.data.operationId, "Execute replay is cached")
    status(f.dispatcher.handle(1, request("unknown-execute", "Operation.Execute", { operationId = "client-made-up" })), "rejected", "STALE_OPERATION")
    status(f.dispatcher.handle(1, request("op-get-committed", "Operation.Get", { operationId = issued.data.operationId })), "committed")
    local afterBuy = status(f.dispatcher.handle(1, request("profile-after-buy", "Profile.Get")), "ok").data
    check(afterBuy.coinBalance == 20 and afterBuy.basicEggCount == 2 and afterBuy.profileVersion == 3, "Profile.Get reflects committed buy")

    f = fixture()
    status(f.sessions.join(1), "ok")
    status(f.dispatcher.handle(1, request("rate-1", "World.Get")), "ok")
    status(f.dispatcher.handle(1, request("rate-2", "World.Get")), "ok")
    status(f.dispatcher.handle(1, request("rate-3", "World.Get")), "rejected", "RATE_LIMITED")
    f.advance(1)
    status(f.dispatcher.handle(1, request("rate-4", "World.Get")), "ok")

    return { checks = checks }
end

return Suite
