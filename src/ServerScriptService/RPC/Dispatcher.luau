local Dispatcher = {}

local function fail(code, retry, retryAfterMs)
    error({ code = code, retry = retry or "none", retryAfterMs = retryAfterMs }, 0)
end

local function exactFields(value, allowed)
    if type(value) ~= "table" then fail("INVALID_INPUT") end
    for key in pairs(value) do
        if allowed[key] ~= true then fail("INVALID_INPUT") end
    end
end

local function isFiniteInteger(value, minimum, maximum)
    return type(value) == "number" and value == value and value % 1 == 0 and value >= minimum and value <= maximum
end

local function assertId(value)
    if type(value) ~= "string" or #value == 0 or #value > 128 or string.find(value, "%S") == nil or utf8.len(value) == nil then
        fail("INVALID_INPUT")
    end
end

local function stable(value: any, depth, seen, budget)
    depth, seen, budget = depth or 0, seen or {}, budget or {size = 0}
    if depth > 12 then fail("INVALID_INPUT") end
    budget.size += 8
    if type(value) == "string" then budget.size += #value end
    if budget.size > 8192 then fail("INVALID_INPUT") end
    local kind = type(value)
    if kind == "nil" or kind == "boolean" or kind == "number" or kind == "string" then
        if kind == "number" and (value ~= value or math.abs(value) == math.huge) then fail("INVALID_INPUT") end
        return if kind == "string" then "string:" .. #value .. ":" .. value else kind .. ":" .. tostring(value)
    end
    if kind ~= "table" then fail("INVALID_INPUT") end
    if seen[value] then fail("INVALID_INPUT") end
    seen[value] = true
    local keys = {}
    for key in pairs(value) do
        local keyType = type(key)
        if keyType ~= "string" and keyType ~= "number" then fail("INVALID_INPUT") end
        budget.entries = (budget.entries or 0) + 1
        if budget.entries > 256 then fail("INVALID_INPUT") end
        table.insert(keys, key)
    end
    table.sort(keys, function(a, b)
        if type(a) ~= type(b) then return type(a) < type(b) end
        return a < b
    end)
    local parts = { "table{" }
    for _, key in ipairs(keys) do
        table.insert(parts, stable(key, depth + 1, seen, budget) .. "=" .. stable(value[key], depth + 1, seen, budget) .. ";")
    end
    table.insert(parts, "}")
    seen[value] = nil
    return table.concat(parts)
end

local ERROR_POLICY = {
    STALE_BATTLE = { "refresh" },
    NOT_YOUR_TURN = { "refresh" },
    SKILL_LOCKED = { "refresh" },
    SKILL_COOLDOWN = { "refresh" },
    BATTLE_ENDED = { "refresh" },
    OPERATION_BUSY = { "later", 1000 },
    IN_BATTLE = { "later", 1000 },
    BUSY = { "later", 250 },
    SESSION_BUSY = { "later", 250 },
    PROFILE_NOT_OPEN = { "later", 1000 },
    PROFILE_NOT_READY = { "later", 1000 },
    STORAGE_UNAVAILABLE = { "same_operation", 1000 },
    OPERATION_PENDING = { "same_operation", 1000 },
    EXPIRED_INTENT = { "refresh" },
    STALE_PREVIEW = { "refresh" },
    STALE_PROFILE = { "refresh" },
    STALE_OPERATION = { "refresh" },
    IDEMPOTENCY_CONFLICT = { "refresh" },
    CAPACITY_FULL = { "refresh" },
    CREATURE_LOCKED = { "refresh" },
    INSUFFICIENT_FUNDS = { "none" },
    NO_EGG = { "none" },
    NOTHING_TO_CLAIM = { "refresh" },
    RATE_LIMITED = { "later", 500 },
}

function Dispatcher.new(options)
    local repository, sessions = options.repository, options.sessions
    local rules, catalog, views = options.rules, options.catalog, options.views
    local clock = options.clock
    local operationBuilders = options.operationBuilders or {}
    local operationParams = {}
    local replay, buckets, operationFingerprints, ingress = {}, {}, {}, {}
    local service = {}

    local function now()
        local value = clock()
        if not isFiniteInteger(value, 0, 9007199254740991) then fail("INVALID_INPUT") end
        return value
    end

    local function errorResponse(requestId, code, retry, retryAfterMs)
        return {
            apiVersion = 1,
            requestId = requestId,
            status = "rejected",
            error = { code = code, messageKey = "error." .. string.lower(code), retry = retry or "none", retryAfterMs = retryAfterMs },
        }
    end

    local function convert(requestId, result, data)
        local response = { apiVersion = 1, requestId = requestId, status = result.status }
        if result.status == "ok" then
            response.data = data or result.data
            if result.profile then response.profileVersion = result.profile.profileVersion end
        elseif result.status == "committed" then
            response.data = views.receipt(result.receipt)
            response.profileVersion = result.receipt.resultingProfileVersion
        elseif result.status == "prepared" then
            response.data = { operationId = result.operationId }
        elseif result.status == "pending" then
            response.data = data or result.data
            response.error = { code = result.code or "OPERATION_PENDING", messageKey = "error.operation_pending", retry = "same_operation", retryAfterMs = 1000 }
        else
            local policy = ERROR_POLICY[result.code or "INVALID_INPUT"] or { "none" }
            response.status = "rejected"
            response.error = { code = result.code or "INVALID_INPUT", messageKey = "error." .. string.lower(result.code or "invalid_input"), retry = policy[1], retryAfterMs = policy[2] }
        end
        return response
    end

    -- Runs before envelope traversal, serialization and replay responses, so
    -- malformed/unknown/replayed requests cannot bypass the per-player budget.
    local function admit(userId)
        local current = now()
        local bucket = ingress[userId] or {tokens = 40, at = current}
        bucket.tokens = math.min(40, bucket.tokens + math.max(0, current - bucket.at) * 20)
        bucket.at = current
        ingress[userId] = bucket
        if bucket.tokens < 1 then fail("RATE_LIMITED", "later", 500) end
        bucket.tokens -= 1
    end

    local function throttle(userId, action)
        local limits = if action == "Battle.Action" or action == "Battle.Forfeit" then {rate = 2, burst = 2} elseif action == "Mix.Preview" then { rate = 2, burst = 4 } else { rate = 1, burst = 2 }
        local category = if action == "Battle.Action" or action == "Battle.Forfeit" then "battle" else action
        local key = tostring(userId) .. ":" .. category
        local bucket = buckets[key] or { tokens = limits.burst, at = now() }
        local current = now()
        bucket.tokens = math.min(limits.burst, bucket.tokens + (current - bucket.at) * limits.rate)
        bucket.at = current
        buckets[key] = bucket
        if bucket.tokens < 1 then fail("RATE_LIMITED", "later", 500) end
        bucket.tokens -= 1
    end

    local handlers = {}

    function handlers.Profile_Get(userId, args)
        exactFields(args, {})
        local snapshot = sessions.snapshot(userId)
        if snapshot.status ~= "ok" then return { status = "pending", code = "PROFILE_NOT_READY" } end
        return { status = "ok", data = views.profile(rules, catalog, snapshot.profile), profile = snapshot.profile }
    end

    function handlers.World_Get(_, args)
        exactFields(args, {})
        return { status = "ok", data = views.world(rules, now()) }
    end

    function handlers.Mix_Preview(userId, args)
        if not options.mix then fail("INVALID_INPUT") end
        local snapshot = sessions.snapshot(userId)
        if snapshot.status ~= "ok" then return snapshot end
        return {status = "ok", data = options.mix.preview(userId, snapshot.profile, args, now()), profile = snapshot.profile}
    end

    function handlers.Operation_Create(userId, args)
        exactFields(args, { kind = true, params = true })
        assertId(args.kind)
        if type(args.params) ~= "table" then fail("INVALID_INPUT") end
        if options.battle and options.battle.inBattle(userId) then fail("IN_BATTLE") end
        local builder = operationBuilders[args.kind]
        if not builder then fail("INVALID_INPUT") end
        local snapshot = sessions.snapshot(userId)
        if snapshot.status ~= "ok" then return snapshot end
        local worldPhaseId
        if args.kind == "Mix.Commit" and options.mix then
            worldPhaseId = options.mix.validate(userId, snapshot.profile, args.params, now()).phaseId
        end
        local fingerprint = "op:" .. args.kind .. ":" .. stable(args.params)
        local issued = repository.issue(userId, args.kind, fingerprint, snapshot.profile.profileVersion, function(operationId, profile, dryRun)
            return builder(operationId, profile, args.params, now(), userId, dryRun)
        end, now() + 60, worldPhaseId, true, if args.kind == "Mix.Commit" and options.mix then function(profile, timestamp)
            options.mix.validate(userId, profile, args.params, timestamp)
        end else nil)
        if issued.status ~= "ok" then return issued end
        operationFingerprints[issued.operationId] = fingerprint
        operationParams[issued.operationId] = operationParams[issued.operationId] or { userId = userId, kind = args.kind, params = args.params, expiresAt = issued.expiresAt }
        return { status = "ok", data = { operationId = issued.operationId, expiresAt = issued.expiresAt }, profile = snapshot.profile }
    end

    function handlers.Operation_Execute(userId, args)
        exactFields(args, { operationId = true })
        assertId(args.operationId)
        local fingerprint = operationFingerprints[args.operationId]
        if not fingerprint then return { status = "rejected", code = "STALE_OPERATION" } end
        local meta = operationParams[args.operationId]
        if not meta or meta.userId ~= userId then fail("STALE_OPERATION") end
        local snapshot = sessions.snapshot(userId)
        if snapshot.status == "ok" then
            local accepted = snapshot.profile.preparedOperation ~= nil
            for _, receipt in ipairs(snapshot.profile.receipts) do
                if receipt.operationId == args.operationId then accepted = true end
            end
            if not accepted and options.battle and options.battle.inBattle(userId) then fail("IN_BATTLE") end
            if not accepted and options.validateExecute then
                options.validateExecute(userId, meta.kind, meta.params)
            end
        end
        meta.executionRequested = true
        local executed = repository.execute(userId, args.operationId, fingerprint)
        return executed
    end

    function handlers.Operation_Get(userId, args)
        exactFields(args, { operationId = true })
        assertId(args.operationId)
        local snapshot = sessions.snapshot(userId)
        -- Observe the backend before deciding an uncertain operation did not
        -- commit. Recovery can finish a PREPARED plan without rerolling it.
        if snapshot.status == "pending" then snapshot = repository.recover(userId) end
        if snapshot.status ~= "ok" then return snapshot end
        for _, receipt in ipairs(snapshot.profile.receipts) do
            if receipt.operationId == args.operationId then return { status = "committed", receipt = receipt } end
        end
        if snapshot.profile.preparedOperation and snapshot.profile.preparedOperation.operationId == args.operationId then
            return { status = "prepared", operationId = args.operationId }
        end
        local meta = operationParams[args.operationId]
        if not meta or meta.userId ~= userId then return { status = "rejected", code = "STALE_OPERATION" } end
        if now() >= meta.expiresAt then return {status = "rejected", code = "EXPIRED_INTENT"} end
        -- Only resume an Execute the client already requested. Merely inspecting
        -- an issued token does not start it. Reuse its frozen plan and validation.
        if meta.executionRequested then return handlers.Operation_Execute(userId, args) end
        return { status = "pending", code = "OPERATION_PENDING" }
    end

    local actionMap = {
        ["Profile.Get"] = handlers.Profile_Get,
        ["World.Get"] = handlers.World_Get,
        ["Mix.Preview"] = handlers.Mix_Preview,
        ["Operation.Create"] = handlers.Operation_Create,
        ["Operation.Execute"] = handlers.Operation_Execute,
        ["Operation.Get"] = handlers.Operation_Get,
    }

    if options.battle then
        actionMap["Battle.Start"] = options.battle.start
        actionMap["Battle.Get"] = options.battle.get
        actionMap["Battle.Action"] = options.battle.action
        actionMap["Battle.Forfeit"] = options.battle.forfeit
    end

    function service.handle(userId, request)
        local requestId = "unknown"
        local ok, response = pcall(function()
            if not isFiniteInteger(userId, 1, 9007199254740991) then fail("INVALID_INPUT") end
            if type(request) == "table" and type(request.requestId) == "string" and #request.requestId <= 128 then requestId = request.requestId end
            admit(userId)
            exactFields(request, { apiVersion = true, requestId = true, action = true, args = true })
            if request.apiVersion ~= 1 then fail("UNSUPPORTED_VERSION") end
            assertId(request.requestId)
            assertId(request.action)
            if type(request.args) ~= "table" then fail("INVALID_INPUT") end
            requestId = request.requestId
            local handler = actionMap[request.action]
            if not handler then fail("INVALID_INPUT") end
            local fingerprint = stable(request)
            replay[userId] = replay[userId] or {}
            local cached = replay[userId][request.requestId]
            if cached then
                if cached.fingerprint ~= fingerprint then fail("IDEMPOTENCY_CONFLICT") end
                return cached.response
            end
            throttle(userId, request.action)
            local result = handler(userId, request.args)
            local converted = convert(request.requestId, result, result.data)
            replay[userId][request.requestId] = { fingerprint = fingerprint, response = converted }
            return converted
        end)
        if ok then return response end
        local failure = if type(response) == "table" then response else { code = "INVALID_INPUT" }
        local policy = ERROR_POLICY[failure.code] or {}
        return errorResponse(requestId, failure.code or "INVALID_INPUT", failure.retry or policy[1], failure.retryAfterMs or policy[2])
    end

    function service.forget(userId)
        replay[userId], ingress[userId] = nil, nil
        if options.mix then options.mix.forget(userId) end
        if options.battle then options.battle.forget(userId) end
        for id, meta in pairs(operationParams) do
            if meta.userId == userId then operationParams[id] = nil; operationFingerprints[id] = nil end
        end
        for key in pairs(buckets) do
            if string.sub(tostring(key), 1, #tostring(userId) + 1) == tostring(userId) .. ":" then buckets[key] = nil end
        end
    end
    return service
end

return Dispatcher
