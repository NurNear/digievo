-- Session-scoped previews contain no random outcome; only server plans consume parents.
local MixService = {}
function MixService.new(options)
    local rules, catalog, views = options.rules, options.catalog, options.views
    local previews, service = {}, {}
    local function check(value, code)
        if not value then error({code = code}, 0) end
    end
    local function fields(value, allowed)
        check(type(value) == "table", "INVALID_INPUT")
        for key in pairs(value) do check(allowed[key] == true, "INVALID_INPUT") end
    end
    local function parents(profile, ids, userId)
        check(not options.inBattle(userId), "IN_BATTLE")
        fields(ids, {[1] = true, [2] = true})
        for index = 1, 2 do
            check(type(ids[index]) == "string" and #ids[index] > 0 and #ids[index] <= 128, "INVALID_INPUT")
        end
        check(ids[1] ~= ids[2], "INVALID_INPUT")
        local first, second = profile.creatures[ids[1]], profile.creatures[ids[2]]
        check(first ~= nil and second ~= nil, "CREATURE_NOT_FOUND")
        check(not first.isLocked and not second.isLocked, "CREATURE_LOCKED")
        return first, second
    end
    function service.preview(userId, profile, args, now)
        fields(args, {parentIds = true})
        local first, second = parents(profile, args.parentIds, userId)
        local bucket = previews[userId] or {}
        previews[userId] = bucket
        for id, preview in pairs(bucket) do
            if now >= preview.expiresAt or preview.profileVersion ~= profile.profileVersion then bucket[id] = nil end
        end
        local count = 0
        for _ in pairs(bucket) do count += 1 end
        check(count < 128, "RATE_LIMITED")
        local id = options.newId()
        local view = views.mixPreview(rules, id, now + 60, profile.profileVersion, args.parentIds, first, second, now)
        bucket[id] = {expiresAt = view.expiresAt, profileVersion = profile.profileVersion, parentIds = table.clone(args.parentIds), phaseId = view.world.phaseId}
        return view
    end
    function service.validate(userId, profile, params, now)
        fields(params, {previewId = true})
        check(type(params.previewId) == "string" and #params.previewId > 0 and #params.previewId <= 128, "INVALID_INPUT")
        local preview = previews[userId] and previews[userId][params.previewId]
        check(preview ~= nil, "STALE_PREVIEW")
        check(now < preview.expiresAt and preview.profileVersion == profile.profileVersion and rules.worldAt(now).phaseId == preview.phaseId, "STALE_PREVIEW")
        local first, second = parents(profile, preview.parentIds, userId)
        check(profile.coinBalance >= catalog.economy.mixPrice, "INSUFFICIENT_FUNDS")
        return preview, first, second
    end
    function service.build(operationId, profile, params, now, userId, dryRun)
        local preview, first, second = service.validate(userId, profile, params, now)
        local child
        if dryRun then
            -- A valid deterministic shape for repository preflight; no RNG is called.
            child = {definitionId = first.definitionId, totalXP = 0, startingPotentialStars = 0, winsSinceCreation = 0}
        else
            child = rules.rollMix(first, second, now, options.nextNumber)
        end
        child.instanceId, child.originOperationId = operationId, operationId
        child.createdAt, child.isLocked = now, false
        return {coinDelta = -catalog.economy.mixPrice, removeIds = table.clone(preview.parentIds), createCreatures = {child},
            result = {coinDelta = -catalog.economy.mixPrice, consumedIds = table.clone(preview.parentIds), creature = views.creature(rules, catalog, child)}}
    end
    function service.forget(userId) previews[userId] = nil end
    return service
end
return MixService
