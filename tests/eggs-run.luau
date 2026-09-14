local Catalog = require("../src/ReplicatedStorage/Shared/Catalog")
local Rules = require("../src/ReplicatedStorage/Shared/DomainRules")
local result = require("./EggActions.spec").run({
    Schema = require("../src/ServerScriptService/Persistence/ProfileSchema"),
    Repository = require("../src/ServerScriptService/Persistence/ProfileRepository"),
    MemoryStore = require("../src/ServerScriptService/Persistence/MemoryStore"),
    Session = require("../src/ServerScriptService/Persistence/ProfileSession"),
    Dispatcher = require("../src/ServerScriptService/RPC/Dispatcher"),
    Views = require("../src/ServerScriptService/RPC/ViewModels"),
    Actions = require("../src/ServerScriptService/Gameplay/EggActions"),
}, Rules.new(Catalog), Catalog)
print(string.format("I-04 PASS: %d checks (memory backend)", result.checks))
