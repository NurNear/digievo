-- Fixed-capacity recent-sample window; count includes samples evicted from it.
local Metrics = {}
function Metrics.new(capacity)
    assert(type(capacity) == "number" and capacity >= 1 and capacity % 1 == 0, "positive integer capacity")
    local series = {}
    local meter = {}
    function meter.record(name, value)
        if type(value) ~= "number" or value ~= value or value < 0 or value == math.huge then return false end
        local item = series[name]
        if not item then item = {values = {}, count = 0}; series[name] = item end
        item.count += 1
        item.values[(item.count - 1) % capacity + 1] = value
        return true
    end
    function meter.snapshot()
        local result = {}
        for name, item in pairs(series) do
            local sorted = table.clone(item.values)
            table.sort(sorted)
            local n, sum = #sorted, 0
            for _, value in ipairs(sorted) do sum += value end
            result[name] = {count = item.count, retained = n, p95 = sorted[math.ceil(n * 0.95)],
                max = sorted[n], mean = sum / n}
        end
        return result
    end
    return meter
end
return Metrics
