local RunService = game:GetService("RunService")

-- This entry point is intentionally restricted to unpublished Studio places.
assert(RunService:IsStudio() and game.GameId == 0 and game.PlaceId == 0, "Local test only: published places are not allowed")

local shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local metrics = require(game:GetService("ReplicatedStorage").Diagnostics.StudioMetrics).start("server")
local Catalog = require(shared:WaitForChild("Catalog"))
local DomainRules = require(shared:WaitForChild("DomainRules"))
local Suite = require(game:GetService("ServerStorage"):WaitForChild("DomainRulesTests"))
local result = Suite.run(DomainRules, Catalog)
workspace:SetAttribute("Environment", "LocalTest")
workspace:SetAttribute("BuildLabel", "WORLD AUTO v2")
print("DIGIEVO WORLD AUTO v2: real-time server attacks, immediate skills, world arena.")
workspace:SetAttribute("PersistenceEnabled", false)
workspace:SetAttribute("DomainRulesReady", true)
workspace:SetAttribute("DomainTestAssertions", result.checks)
workspace:SetAttribute("DomainWorldCases", result.worldCases)
print(string.format("I-01 PASS: %d assertions, %d world cases. Local-only; no player data is saved.", result.checks, result.worldCases))

local persistence = script.Parent:WaitForChild("Persistence")
local modules = {
    Schema = require(persistence.ProfileSchema),
    Repository = require(persistence.ProfileRepository),
    MemoryStore = require(persistence.MemoryStore),
    RobloxStore = require(persistence.RobloxStore),
    Session = require(persistence.ProfileSession),
}
local HttpService = game:GetService("HttpService")
local function measure(profile)
    return #HttpService:JSONEncode(profile)
end
local rules = DomainRules.new(Catalog)
local persistenceResult = require(game:GetService("ServerStorage").PersistenceTests).run(modules, rules, measure)
workspace:SetAttribute("PersistenceTestsReady", true)
workspace:SetAttribute("PersistenceTestChecks", persistenceResult.checks)
print(string.format("I-02 PASS: %d checks, %d fault runs. Memory backend only; no cloud writes.", persistenceResult.checks, persistenceResult.faultRuns))

local rpcModules = {
    Schema = modules.Schema,
    Repository = modules.Repository,
    MemoryStore = modules.MemoryStore,
    Session = modules.Session,
    Dispatcher = require(script.Parent.RPC.Dispatcher),
    Views = require(script.Parent.RPC.ViewModels),
}
local rpcResult = require(game:GetService("ServerStorage").RpcTests).run(rpcModules, rules, Catalog)
workspace:SetAttribute("RpcTestsReady", true)
workspace:SetAttribute("RpcTestChecks", rpcResult.checks)
print(string.format("I-03 PASS: %d RPC checks. Memory backend only; server boundary verified.", rpcResult.checks))

rpcModules.Actions = require(script.Parent.Gameplay.EggActions)
local eggResult = require(game:GetService("ServerStorage").EggActionsTests).run(rpcModules, rules, Catalog)
workspace:SetAttribute("EggTestChecks", eggResult.checks)
print(string.format("I-04 PASS: %d checks. Memory backend only.", eggResult.checks))

rpcModules.Mix = require(script.Parent.Gameplay.MixService)
local mixResult = require(game:GetService("ServerStorage").MixTests).run(rpcModules, rules, Catalog)
workspace:SetAttribute("MixTestChecks", mixResult.checks)
print(string.format("I-05 PASS: %d checks. Memory backend only.", mixResult.checks))

rpcModules.Battle = require(script.Parent.Gameplay.BattleService)
local battleResult = require(game:GetService("ServerStorage").BattleTests).run(rpcModules, rules, Catalog)
workspace:SetAttribute("BattleTestChecks", battleResult.checks)
print(string.format("I-06 PASS: %d checks. Memory backend only.", battleResult.checks))

local presentation = game:GetService("ReplicatedStorage"):WaitForChild("Presentation")
local feedResult = require(game:GetService("ServerStorage").BattleFeedTests).run(require(presentation.BattleFeed))
print(string.format("Battle feed PASS: %d checks.", feedResult.checks))
local journeyResult = require(game:GetService("ServerStorage").JourneyTests).run(require(presentation.Guide), require(presentation.PetStyles), Catalog)
workspace:SetAttribute("JourneyTestChecks", journeyResult.checks)
print(string.format("I-07 PASS: %d checks. Journey guidance and visual catalog; rendering requires Play verification.", journeyResult.checks))

-- Heavy fault injection is opt-in so ordinary playtesting starts quickly.
if workspace:GetAttribute("RunSafetyTests") == true then
    local safetyResult = require(game:GetService("ServerStorage").SafetyTests).run(rpcModules, rules, Catalog)
    workspace:SetAttribute("SafetyTestChecks", safetyResult.checks)
    workspace:SetAttribute("SafetyFaultRuns", safetyResult.faultRuns)
    print(string.format("I-08 PASS: %d checks; %d simulated fault scenarios.", safetyResult.checks, safetyResult.faultRuns))
end

local schema = modules.Schema.new(rules, measure)
local repository = modules.Repository.new({
    schema = schema,
    store = modules.MemoryStore.new(schema.copy),
    sessionId = HttpService:GenerateGUID(false),
    rulesVersion = Catalog.rulesVersion,
    clock = os.time,
    newId = function() return HttpService:GenerateGUID(false) end,
})
local sessions = modules.Session.new(repository)
local Players = game:GetService("Players")
local active = {}
local nodes = {}
for index, nodeId in ipairs(Catalog.economy.nodeIds) do
    local node = Instance.new("Part")
    node.Name = nodeId
    node.Shape = Enum.PartType.Ball
    node.Size = Vector3.new(3, 3, 3)
    node.Position = Vector3.new((index - 2) * 24, 2, -24)
    node.Anchored = true
    node.Color = Color3.fromRGB(255, 209, 102)
    node.Parent = workspace
    local label = Instance.new("BillboardGui")
    label.Size = UDim2.fromOffset(140, 40)
    label.StudsOffset = Vector3.new(0, 3, 0)
    label.AlwaysOnTop = true
    label.Parent = node
    local text = Instance.new("TextLabel")
    text.Size = UDim2.fromScale(1, 1)
    text.BackgroundTransparency = 1
    text.Text = "จุดเก็บไข่ " .. nodeId
    text.TextColor3 = Color3.new(1, 1, 1)
    text.TextSize = 18
    text.Parent = label
    nodes[nodeId] = node
end
local function nearNode(userId, nodeId)
    for player, key in pairs(active) do
        if key == userId then
            local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
            return root ~= nil and nodes[nodeId] ~= nil and (root.Position - nodes[nodeId].Position).Magnitude <= 12
        end
    end
    return false
end
local function validateExecute(userId, kind, params)
    if kind == "Egg.Collect" and not nearNode(userId, params.nodeId) then error({code = "OUT_OF_RANGE"}, 0) end
end
local training = Instance.new("Part")
training.Name = "TrainingArena"
training.Size = Vector3.new(12, 1, 12)
training.Position = Vector3.new(24, 0.5, 12)
training.Anchored = true
training.Color = Color3.fromRGB(91, 153, 232)
training.Parent = workspace
nodes.TRAINING = training
local sign = Instance.new("BillboardGui")
sign.Size = UDim2.fromOffset(240, 60)
sign.StudsOffset = Vector3.new(0, 4, 0)
sign.AlwaysOnTop = true
sign.Parent = training
local trainingText = Instance.new("TextLabel")
trainingText.Size = UDim2.fromScale(1, 1)
trainingText.BackgroundTransparency = 1
trainingText.TextColor3 = Color3.new(1, 1, 1)
trainingText.TextSize = 18
trainingText.TextWrapped = true
trainingText.Text = "สนามฝึก • คู่ฝึก HP 60%\nเลือกตัวละครแล้วกดฝึก"
trainingText.Parent = sign
local LocalWorld = require(script.Parent.Presentation.LocalWorld)
LocalWorld.build(nodes, training)
LocalWorld.update(rules.worldAt(os.time()))
local random = Random.new()
local battle
local gameplayOptions = {clock = function() return workspace:GetServerTimeNow() end, rules = rules, catalog = Catalog, views = rpcModules.Views,
    nearNode = nearNode, inBattle = function(userId) return battle and battle.inBattle(userId) or false end,
    nextNumber = function() return random:NextNumber() end,
    newId = function() return HttpService:GenerateGUID(false) end,
}
gameplayOptions.repository = repository
gameplayOptions.copy = schema.copy
gameplayOptions.nearTraining = function(userId) return nearNode(userId, "TRAINING") end
battle = rpcModules.Battle.new(gameplayOptions)
local mix = require(script.Parent.Gameplay.MixService).new(gameplayOptions)
local builders = rpcModules.Actions.new(gameplayOptions)
builders["Mix.Commit"] = mix.build
local dispatcher = rpcModules.Dispatcher.new({repository = repository, sessions = sessions,
    rules = rules, catalog = Catalog, views = rpcModules.Views, clock = os.time,
    validateExecute = validateExecute, operationBuilders = builders, mix = mix, battle = battle,
})
local remotes = Instance.new("Folder")
remotes.Name = "GameRemotes"
for _, name in ipairs({"GameRequest", "GameResponse", "GamePush"}) do
    local remote = Instance.new("RemoteEvent")
    remote.Name = name
    remote.Parent = remotes
end
local function publish(player, response)
    if response.data and response.data.battle then
        remotes.GamePush:FireClient(player, {apiVersion = 1, event = "BattleChanged", data = response.data.battle})
    end
    if response.status == "committed" or (response.data and response.data.battle and response.data.battle.status == "ended") then
        local key = active[player]
        if not key then return end
        local snapshot = sessions.snapshot(key)
        if snapshot.status == "ok" then
            remotes.GamePush:FireClient(player, {apiVersion = 1, event = "ProfileChanged", data = rpcModules.Views.profile(rules, Catalog, snapshot.profile)})
        end
    end
end
remotes.GameRequest.OnServerEvent:Connect(function(player, request)
    local key = active[player]
    if not key then return end
    local started = os.clock()
    local response = dispatcher.handle(key, request)
    metrics.record("dispatchMs", (os.clock() - started) * 1000)
    if active[player] ~= key then return end
    remotes.GameResponse:FireClient(player, response)
    publish(player, response)
end)
-- A slow reward write for one player must not stop other players' fights.
local ticking = {}
task.spawn(function()
    while task.wait(0.05) do
        for player, key in pairs(active) do
            if not ticking[player] then
                ticking[player] = true
                task.spawn(function()
                    local ok, response = pcall(battle.tick, key)
                    ticking[player] = nil
                    if not ok then warn("Battle tick failed", response); return end
                    if response and active[player] == key then publish(player, response) end
                end)
            end
        end
    end
end)
remotes.Parent = game:GetService("ReplicatedStorage")
local function joined(player)
    if active[player] then return end
    -- Negative IDs are reserved for Studio's simulated clients, mapped only in this memory harness.
    local key = if player.UserId > 0 then player.UserId else 9000000000000000 + math.abs(player.UserId)
    active[player] = key
    local started = os.clock()
    local opened = sessions.join(key)
    metrics.record("joinMs." .. opened.status, (os.clock() - started) * 1000)
    if opened.profile then metrics.record("profileBytes", #HttpService:JSONEncode(opened.profile)) end
    player:SetAttribute("ProfileStatus", opened.status)
    if opened.profile then
        player:SetAttribute("TestCoins", opened.profile.coinBalance)
        player:SetAttribute("TestEggs", opened.profile.basicEggCount)
        print("I-02 local profile ready: starter initialized in memory; no cloud writes.")
    end
end
Players.PlayerAdded:Connect(joined)
Players.PlayerRemoving:Connect(function(player)
    local key = active[player]
    active[player] = nil
    if key then dispatcher.forget(key); sessions.leave(key) end
end)
for _, player in ipairs(Players:GetPlayers()) do joined(player) end
task.spawn(function()
    while task.wait(30) do
        for player, key in pairs(active) do
            local refreshed = sessions.heartbeat(key)
            player:SetAttribute("ProfileStatus", refreshed.status)
        end
    end
end)
game:BindToClose(function()
    for _, key in pairs(active) do sessions.leave(key) end
end)

task.spawn(function()
    local previousPhase
    while task.wait(1) do
        local world = rpcModules.Views.world(rules, os.time())
        if world.phaseId ~= previousPhase then
            previousPhase = world.phaseId
            LocalWorld.update(world)
            remotes.GamePush:FireAllClients({apiVersion = 1, event = "WorldChanged", data = world})
        end
    end
end)
