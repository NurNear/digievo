local Metrics = require("../src/ReplicatedStorage/Diagnostics/Metrics")
local meter = Metrics.new(100)
for i = 1, 100 do assert(meter.record("latency", i)) end
local s = meter.snapshot().latency
assert(s.p95 == 95 and s.mean == 50.5 and s.count == 100)
for i = 101, 200 do meter.record("latency", i) end
s = meter.snapshot().latency
assert(s.retained == 100 and s.count == 200 and s.p95 == 195 and s.max == 200)
assert(not meter.record("latency", 0/0))
assert(not meter.record("latency", math.huge))
assert(not meter.record("latency", -1))
meter.record("other", 0)
assert(meter.snapshot().other.p95 == 0)
s.p95 = -1
assert(meter.snapshot().latency.p95 == 195)
assert(not pcall(Metrics.new, 0))
print("Metrics PASS: percentile, bounded window, isolation and invalid samples")
