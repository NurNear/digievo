-- Server-only repository. Inject storage, time and IDs; never generate random results in UpdateAsync.
local ProfileRepository = {}

function ProfileRepository.new(options)
    local schema, store = options.schema, options.store
    local check, copy = schema.check, schema.copy
    schema.id(options.sessionId); schema.id(options.rulesVersion)
    local states, repository = {}, {}
    local function now()
        local value = options.clock()
        schema.integer(value, 0, 9007199254740871)
        return value
    end
    local function locked(userId, work)
        schema.integer(userId, 1, 9007199254740991)
        local state = states[userId]
        if not state then state = {}; states[userId] = state end
        if state.busy then return { status="pending", code="BUSY" } end
        state.busy = true
        local ok, result = pcall(work, state)
        state.busy = false
        if ok then return result end
        local failure = if type(result) == "table" then result else { code="INTERNAL_ERROR" }
        return { status=if failure.pending then "pending" else "rejected", code=failure.code }
    end
    local function fence(profile, state)
        local lease = profile.lease
        check(lease and lease.sessionId == options.sessionId and lease.generation == state.generation and lease.expiresAt > now(), "FENCED")
    end
    local function update(userId, state, transform, allowNew)
        local observed, domainFailure
        local ok, value = pcall(function()
            return store:UpdateAsync("player:" .. tostring(userId), function(current)
                -- These variables describe only the final callback invocation, never an earlier retry.
                observed, domainFailure = nil, nil
                local valid, proposed = pcall(function()
                    if current == nil then
                        check(allowNew == true and state.generation == nil, "PROFILE_MISSING")
                        current = schema.newProfile()
                    end
                    schema.validate(current)
                    observed = copy(current)
                    local changed = transform(copy(current))
                    if changed then schema.validate(changed) end
                    return changed
                end)
                if not valid then domainFailure = proposed; return nil end
                return proposed
            end)
        end)
        if not ok then
            state.uncertain = true
            error({ code="STORAGE_UNAVAILABLE", pending=true }, 0)
        end
        if domainFailure then
            state.profile = observed
            error(domainFailure, 0)
        end
        local confirmed = value or observed
        check(confirmed ~= nil, "PROFILE_MISSING")
        schema.validate(confirmed)
        state.profile = copy(confirmed)
        return confirmed
    end
    local function receipt(profile, operationId, fingerprint)
        for _, item in ipairs(profile.receipts) do
            if item.operationId == operationId then
                check(item.inputFingerprint == fingerprint, "IDEMPOTENCY_CONFLICT")
                return item
            end
        end
        return nil
    end
    local function ready(state)
        check(state.profile ~= nil, "PROFILE_NOT_OPEN")
        if state.uncertain or state.profile.preparedOperation then error({ code="OPERATION_PENDING", pending=true }, 0) end
        fence(state.profile, state)
    end
    local function commit(userId, state, operationId, fingerprint)
        local profile = update(userId, state, function(current)
            fence(current, state)
            if receipt(current, operationId, fingerprint) then return nil end
            local prepared = current.preparedOperation
            check(prepared and prepared.operationId == operationId, "STALE_OPERATION")
            check(prepared.inputFingerprint == fingerprint, "IDEMPOTENCY_CONFLICT")
            local result = schema.commit(current, now())
            result.lease.expiresAt = now() + 120
            return result
        end)
        state.uncertain, state.pendingId = false, nil
        if state.intent and state.intent.operationId == operationId then state.intent = nil end
        return { status="committed", receipt=copy(receipt(profile, operationId, fingerprint)) }
    end
    local function prepare(userId, state, operationId, fingerprint)
        schema.id(operationId); schema.id(fingerprint)
        check(state.profile ~= nil, "PROFILE_NOT_OPEN")
        if state.uncertain and state.pendingId ~= operationId then error({ code="OPERATION_PENDING", pending=true }, 0) end
        local cachedReceipt = receipt(state.profile, operationId, fingerprint)
        if cachedReceipt then
            if state.intent and state.intent.operationId == operationId then state.intent = nil end
            return { status="committed", receipt=copy(cachedReceipt) }
        end
        local intent, existing = state.intent, state.profile.preparedOperation
        check((intent and intent.operationId == operationId) or (existing and existing.operationId == operationId), "STALE_OPERATION")
        if intent and intent.buildPlan and not existing then
            check(now() < intent.expiresAt, "EXPIRED_INTENT")
            check(state.profile.profileVersion == intent.expectedProfileVersion, "STALE_PROFILE")
            -- Materialize randomness once outside UpdateAsync; retain this plan on retry.
            local plan = copy(intent.buildPlan(operationId, copy(state.profile), false))
            schema.apply(state.profile, plan, operationId, intent.kind)
            intent.resultPlan = plan
            intent.buildPlan = nil
        end
        state.pendingId = operationId
        local profile = update(userId, state, function(current)
            fence(current, state)
            if receipt(current, operationId, fingerprint) then return nil end
            if current.preparedOperation then
                check(current.preparedOperation.operationId == operationId, "OPERATION_PENDING")
                check(current.preparedOperation.inputFingerprint == fingerprint, "IDEMPOTENCY_CONFLICT")
                return nil
            end
            check(intent ~= nil and intent.operationId == operationId, "STALE_OPERATION")
            check(intent.inputFingerprint == fingerprint, "IDEMPOTENCY_CONFLICT")
            check(now() < intent.expiresAt, "EXPIRED_INTENT")
            check(current.profileVersion == intent.expectedProfileVersion, "STALE_PROFILE")
            current.preparedOperation = {
                operationId=operationId, seq=current.lastAppliedSeq + 1, kind=intent.kind,
                inputFingerprint=fingerprint, expectedProfileVersion=intent.expectedProfileVersion,
                preparedAt=now(), rulesVersion=options.rulesVersion, worldPhaseId=intent.worldPhaseId,
                resultPlan=copy(intent.resultPlan),
            }
            current.lease.expiresAt = now() + 120
            -- Check both durable states before accepting an operation that might not fit on commit.
            schema.validate(current)
            schema.commit(current, now())
            return current
        end)
        state.uncertain = false
        local committed = receipt(profile, operationId, fingerprint)
        if committed then
            state.pendingId, state.intent = nil, nil
            return { status="committed", receipt=copy(committed) }
        end
        return { status="prepared", operationId=operationId }
    end

    function repository.open(userId)
        return locked(userId, function(state)
            local profile = update(userId, state, function(current)
                local lease = current.lease
                check(not lease or lease.expiresAt <= now() or lease.sessionId == options.sessionId, "LEASE_HELD")
                local generation = if lease then lease.generation else 0
                if not lease or lease.sessionId ~= options.sessionId or lease.expiresAt <= now() then generation += 1 end
                current.lease = { sessionId=options.sessionId, generation=generation, expiresAt=now() + 120 }
                return current
            end, true)
            state.generation = profile.lease.generation
            state.uncertain = false
            if profile.preparedOperation then
                local operation = profile.preparedOperation
                commit(userId, state, operation.operationId, operation.inputFingerprint)
            end
            state.pendingId = nil
            if state.intent and receipt(state.profile, state.intent.operationId, state.intent.inputFingerprint) then state.intent = nil end
            return { status="ok", profile=copy(state.profile) }
        end)
    end

    -- Only a server domain service may supply a plan builder. This is not a client API.
    function repository.issue(userId, kind, fingerprint, expectedVersion, buildPlan, expiry, worldPhaseId, deferred)
        return locked(userId, function(state)
            ready(state); schema.id(fingerprint)
            check(expectedVersion == state.profile.profileVersion, "STALE_PROFILE")
            if state.intent and state.intent.expiresAt > now() then
                check(state.intent.kind == kind and state.intent.inputFingerprint == fingerprint and state.intent.expectedProfileVersion == expectedVersion, "INTENT_BUSY")
                return { status="ok", operationId=state.intent.operationId }
            end
            local operationId = options.newId()
            schema.id(operationId)
            check(not receipt(state.profile, operationId, fingerprint), "REUSED_OPERATION_ID")
            local expiresAt = math.min(now() + 60, expiry or now() + 60)
            schema.integer(expiresAt, now() + 1, now() + 60)
            if worldPhaseId then schema.id(worldPhaseId) end
            local plan = copy(buildPlan(operationId, copy(state.profile), deferred == true))
            schema.apply(state.profile, plan, operationId, kind)
            state.intent = { operationId=operationId, kind=kind, inputFingerprint=fingerprint, expectedProfileVersion=expectedVersion, expiresAt=expiresAt, resultPlan=plan, worldPhaseId=worldPhaseId, buildPlan=if deferred then buildPlan else nil }
            return { status="ok", operationId=operationId }
        end)
    end

    function repository.prepare(userId, operationId, fingerprint)
        return locked(userId, function(state) return prepare(userId, state, operationId, fingerprint) end)
    end

    function repository.execute(userId, operationId, fingerprint)
        return locked(userId, function(state)
            local result = prepare(userId, state, operationId, fingerprint)
            if result.status == "committed" then return result end
            return commit(userId, state, operationId, fingerprint)
        end)
    end

    function repository.recover(userId)
        return locked(userId, function(state)
            local profile = update(userId, state, function(current) fence(current, state); return nil end)
            if profile.preparedOperation then
                local operation = profile.preparedOperation
                commit(userId, state, operation.operationId, operation.inputFingerprint)
            end
            state.uncertain, state.pendingId = false, nil
            if state.intent and receipt(state.profile, state.intent.operationId, state.intent.inputFingerprint) then state.intent = nil end
            return { status="ok", profile=copy(state.profile) }
        end)
    end

    function repository.snapshot(userId)
        return locked(userId, function(state) ready(state); return { status="ok", profile=copy(state.profile) } end)
    end

    function repository.renew(userId)
        return locked(userId, function(state)
            update(userId, state, function(current) fence(current, state); current.lease.expiresAt = now() + 120; return current end)
            return { status="ok" }
        end)
    end

    function repository.release(userId)
        return locked(userId, function(state)
            update(userId, state, function(current) fence(current, state); current.lease.expiresAt = 0; return current end)
            states[userId] = nil
            return { status="ok" }
        end)
    end
    return repository
end

return ProfileRepository
