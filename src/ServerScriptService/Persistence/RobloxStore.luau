-- Test-online adapter only. No Roblox service is accessed until environment checks pass.
local RobloxStore = {}
function RobloxStore.new(config, runtime)
    assert(config.mode == "TestOnline", "TestOnline mode required")
    assert(type(config.universeId) == "number" and config.universeId > 0 and config.universeId % 1 == 0, "Verified test universe required")
    assert(type(config.placeId) == "number" and config.placeId > 0 and config.placeId % 1 == 0, "Verified test place required")
    assert(runtime.isStudio == true and runtime.gameId == config.universeId and runtime.placeId == config.placeId, "Test environment mismatch")
    assert(config.namespace == "RobloxMVP_Test_v1", "Test namespace required")
    local backend = runtime.getStore(config.namespace)
    local adapter = {}
    function adapter:UpdateAsync(key, transform)
        local lastError = "Storage unavailable"
        for attempt = 1, 5 do
            if attempt > 1 then runtime.sleep(2 ^ (attempt - 2) + runtime.jitter()) end
            if runtime.hasBudget() then
                local ok, value = pcall(function()
                    return backend:UpdateAsync(key, function(current, keyInfo)
                        local proposed = transform(current)
                        if proposed == nil then return nil end
                        -- Preserve metadata/user associations when replacing the value.
                        return proposed, if keyInfo then keyInfo:GetUserIds() else {}, if keyInfo then keyInfo:GetMetadata() else {}
                    end)
                end)
                if ok then return value end
                lastError = value
            end
        end
        error(lastError, 0)
    end
    return adapter
end
return RobloxStore
