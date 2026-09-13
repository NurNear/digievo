local RunService = game:GetService("RunService")

-- This entry point is intentionally restricted to unpublished Studio places.
assert(RunService:IsStudio() and game.GameId == 0 and game.PlaceId == 0, "Local test only: published places are not allowed")

local shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Catalog = require(shared:WaitForChild("Catalog"))
local DomainRules = require(shared:WaitForChild("DomainRules"))
local Suite = require(game:GetService("ServerStorage"):WaitForChild("DomainRulesTests"))
local result = Suite.run(DomainRules, Catalog)
workspace:SetAttribute("Environment", "LocalTest")
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
print(string.format("I-03 PASS: %d RPC checks. Memory backend only; no client UI yet.", rpcResult.checks))

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
local function joined(player)
    if active[player] then return end
    -- Negative IDs are reserved for Studio's simulated clients, mapped only in this memory harness.
    local key = if player.UserId > 0 then player.UserId else 9000000000000000 + math.abs(player.UserId)
    active[player] = key
    local opened = sessions.join(key)
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
    if key then sessions.leave(key) end
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
