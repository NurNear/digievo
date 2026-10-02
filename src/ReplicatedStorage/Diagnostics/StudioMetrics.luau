local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local Metrics = require(script.Parent.Metrics)
local StudioMetrics = {}
function StudioMetrics.start(role)
    local enabled = RunService:IsStudio() and workspace:GetAttribute("MeasurePerformance") == true
    local meter = Metrics.new(65536)
    local started = os.clock()
    local api = {}
    function api.record(name, value)
        if enabled then meter.record(name, value) end
    end
    if enabled then
        if role == "client" then
            RunService.RenderStepped:Connect(function(dt) meter.record("frameMs", dt * 1000) end)
        end
        task.spawn(function()
            while task.wait(60) do
                local report = {role = role, elapsedSeconds = os.clock() - started,
                    backend = "simulated-memory", metrics = meter.snapshot()}
                if role == "client" then
                    local camera = workspace.CurrentCamera
                    if camera then report.viewport = {camera.ViewportSize.X, camera.ViewportSize.Y} end
                end
                print("I-09 METRICS " .. HttpService:JSONEncode(report))
            end
        end)
    end
    return api
end
return StudioMetrics
