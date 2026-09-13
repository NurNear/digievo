-- Test backend only; data survives repository replacement, not a process restart.
local MemoryStore = {}
function MemoryStore.new(copy)
    local store = { values={}, calls=0, writes=0, callbackRepeats=1 }
    function store:UpdateAsync(key, transform)
        self.calls += 1
        if self.beforeCall then self.beforeCall(self, key) end
        if self.failBefore then error("simulated storage outage") end
        local proposed
        for _ = 1, self.callbackRepeats do proposed = transform(copy(self.values[key])) end
        if self.beforeCommit then
            self.beforeCommit(self, key)
            -- Simulate UpdateAsync retrying against a concurrent committed value.
            proposed = transform(copy(self.values[key]))
        end
        if proposed ~= nil then self.values[key] = copy(proposed); self.writes += 1 end
        if self.failAfter then error("simulated lost response") end
        return if proposed ~= nil then copy(self.values[key]) else nil
    end
    return store
end
return MemoryStore
