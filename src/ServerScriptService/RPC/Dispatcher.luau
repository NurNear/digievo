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
        return kind .. ":" .. tostring(value)
    end
    if kind ~= "table" then fail("INVALID_INPUT") end
    if seen[value] then fail("INVALID_INPUT") end
    seen[value] = true
    local keys = {}
    for key in pairs(value) do
        local keyType = type(key)
        if keyType ~= "string" and keyType ~= "number" then fail("INVALID_INPUT") end
        table.insert(keys, key)
    end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local parts = { "table{" }
    for _, key in ipairs(keys) do
        table.insert(parts, stable(key, depth + 1, seen, budget) .. "=" .. stable(value[key], depth + 1, seen, budget) .. ";")
    end
    table.insert(parts, "}")
    seen[value] = nil
    return table.concat(parts)
end

local ERROR_POLICY = {
    BUSY = { "later", 250 },
    SESSION_BUSY = { "later", 250 },
    PROFILE_NOT_OPEN = { "later", 1000 },
    PROFILE_NOT_READY = { "later", 1000 },
    STORAGE_UNAVAILABLE = { "same_operation", 1000 },
    OPERATION_PENDING = { "same_operation", 1000 },
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
    local replay, buckets, operationFingerprints = {}, {}, {}
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
            response.error = { code = result.code or "OPERATION_PENDING", messageKey = "error.operation_pending", retry = "same_operation", retryAfterMs = 1000 }
        else
            local policy = ERROR_POLICY[result.code or "INVALID_INPUT"] or { "none" }
            response.status = "rejected"
            response.error = { code = result.code or "INVALID_INPUT", messageKey = "error." .. string.lower(result.code or "invalid_input"), retry = policy[1], retryAfterMs = policy[2] }
        end
        return response
    end

    local function throttle(userId, action)
        local limits = if action == "Mix.Preview" then { rate = 2, burst = 4 } elseif action == "Profile.Get" or action == "World.Get" or action == "Operation.Get" then { rate = 1, burst = 2 } else { rate = 1, burst = 2 }
        local key = tostring(userId) .. ":" .. action
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

    function handlers.Operation_Create(userId, args)
        exactFields(args, { kind = true, params = true })
        assertId(args.kind)
        if type(args.params) ~= "table" then fail("INVALID_INPUT") end
        local builder = operationBuilders[args.kind]
        if not builder then fail("INVALID_INPUT") end
        local snapshot = sessions.snapshot(userId)
        if snapshot.status ~= "ok" then return snapshot end
        local fingerprint = "op:" .. args.kind .. ":" .. stable(args.params)
        local issued = repository.issue(userId, args.kind, fingerprint, snapshot.profile.profileVersion, function(operationId, profile, dryRun)
            return builder(operationId, profile, args.params, now(), userId, dryRun)
        end, now() + 60, nil, true)
        if issued.status ~= "ok" then return issued end
        operationFingerprints[issued.operationId] = fingerprint
        operationParams[issued.operationId] = { userId = userId, kind = args.kind, params = args.params }
        return { status = "ok", data = { operationId = issued.operationId, expiresAt = now() + 60 }, profile = snapshot.profile }
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
            if not accepted and options.validateExecute then
                options.validateExecute(userId, meta.kind, meta.params)
            end
        end
        local executed = repository.execute(userId, args.operationId, fingerprint)
        return executed
    end

    function handlers.Operation_Get(userId, args)
        exactFields(args, { operationId = true })
        assertId(args.operationId)
        local snapshot = sessions.snapshot(userId)
        if snapshot.status ~= "ok" then return snapshot end
        for _, receipt in ipairs(snapshot.profile.receipts) do
            if receipt.operationId == args.operationId then
                return { status = "committed", receipt = receipt }
            end
        end
        if snapshot.profile.preparedOperation and snapshot.profile.preparedOperation.operationId == args.operationId then
            return { status = "prepared", operationId = args.operationId }
        end
        if operationParams[args.operationId] and operationParams[args.operationId].userId == userId then
            return { status = "pending", code = "OPERATION_PENDING" }
        end
        return { status = "rejected", code = "STALE_OPERATION" }
    end

    local actionMap = {
        ["Profile.Get"] = handlers.Profile_Get,
        ["World.Get"] = handlers.World_Get,
        ["Operation.Create"] = handlers.Operation_Create,
        ["Operation.Execute"] = handlers.Operation_Execute,
        ["Operation.Get"] = handlers.Operation_Get,
    }

    function service.handle(userId, request)
        local requestId = "unknown"
        local ok, response = pcall(function()
            if not isFiniteInteger(userId, 1, 9007199254740991) then fail("INVALID_INPUT") end
            exactFields(request, { apiVersion = true, requestId = true, action = true, args = true })
            if request.apiVersion ~= 1 then fail("UNSUPPORTED_VERSION") end
            assertId(request.requestId)
            assertId(request.action)
            if type(request.args) ~= "table" then fail("INVALID_INPUT") end
            requestId = request.requestId
            local fingerprint = stable(request)
            replay[userId] = replay[userId] or {}
            local cached = replay[userId][request.requestId]
            if cached then
                if cached.fingerprint ~= fingerprint then fail("IDEMPOTENCY_CONFLICT") end
                return cached.response
            end
            throttle(userId, request.action)
            local handler = actionMap[request.action]
            if not handler then fail("INVALID_INPUT") end
            local result = handler(userId, request.args)
            local converted = convert(request.requestId, result, result.data)
            replay[userId][request.requestId] = { fingerprint = fingerprint, response = converted }
            return converted
        end)
        if ok then return response end
        local failure = if type(response) == "table" then response else { code = "INVALID_INPUT" }
        return errorResponse(requestId, failure.code or "INVALID_INPUT", failure.retry, failure.retryAfterMs)
    end

    function service.forget(userId)
        replay[userId] = nil
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
