-- Lifecycle policy; scheduling and Player identity are supplied by the server entry point.
local ProfileSession = {}
function ProfileSession.new(repository)
    local sessions, service = {}, {}
    function service.join(userId)
        local opened = repository.open(userId)
        sessions[userId] = true
        if opened.status ~= "ok" then return opened end
        if not opened.profile.starterGrantClaimed then
            local token = repository.issue(userId, "StarterGrant", "starter:v1", opened.profile.profileVersion, function()
                return { coinDelta=20, eggDelta=1, starterGrantClaimed=true, result={ coinDelta=20, eggDelta=1 } }
            end)
            if token.status ~= "ok" then return token end
            local granted = repository.execute(userId, token.operationId, "starter:v1")
            if granted.status ~= "committed" then return granted end
        end
        return repository.snapshot(userId)
    end
    function service.heartbeat(userId)
        if not sessions[userId] then return { status="rejected", code="SESSION_CLOSED" } end
        local snapshot = repository.snapshot(userId)
        if snapshot.status ~= "ok" then return service.join(userId) end
        return repository.renew(userId)
    end
    function service.leave(userId)
        sessions[userId] = nil
        return repository.release(userId)
    end
    function service.snapshot(userId)
        return repository.snapshot(userId)
    end
    return service
end
return ProfileSession
