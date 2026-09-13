local Catalog = require("../src/ReplicatedStorage/Shared/Catalog")
local Rules = require("../src/ReplicatedStorage/Shared/DomainRules")
local Suite = require("./Persistence.spec")
local result = Suite.run({
    Schema=require("../src/ServerScriptService/Persistence/ProfileSchema"),
    Repository=require("../src/ServerScriptService/Persistence/ProfileRepository"),
    MemoryStore=require("../src/ServerScriptService/Persistence/MemoryStore"),
    RobloxStore=require("../src/ServerScriptService/Persistence/RobloxStore"),
    Session=require("../src/ServerScriptService/Persistence/ProfileSession"),
}, Rules.new(Catalog))
print(string.format("I-02 PASS: %d checks; %d injected fault runs (memory backend)", result.checks, result.faultRuns))

local rpc = require("./Rpc.spec").run({
    Schema=require("../src/ServerScriptService/Persistence/ProfileSchema"),
    Repository=require("../src/ServerScriptService/Persistence/ProfileRepository"),
    MemoryStore=require("../src/ServerScriptService/Persistence/MemoryStore"),
    Session=require("../src/ServerScriptService/Persistence/ProfileSession"),
    Dispatcher=require("../src/ServerScriptService/RPC/Dispatcher"),
    Views=require("../src/ServerScriptService/RPC/ViewModels"),
}, Rules.new(Catalog), Catalog)
print(string.format("I-03 PASS: %d RPC checks (memory backend)", rpc.checks))
