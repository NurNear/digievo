local Catalog = require("../src/ReplicatedStorage/Shared/Catalog")
local Rules = require("../src/ReplicatedStorage/Shared/DomainRules")
local result = require("./Battle.spec").run({
    Schema = require("../src/ServerScriptService/Persistence/ProfileSchema"),
    Repository = require("../src/ServerScriptService/Persistence/ProfileRepository"),
    MemoryStore = require("../src/ServerScriptService/Persistence/MemoryStore"),
    Session = require("../src/ServerScriptService/Persistence/ProfileSession"),
    Dispatcher = require("../src/ServerScriptService/RPC/Dispatcher"),
    Views = require("../src/ServerScriptService/RPC/ViewModels"),
    Battle = require("../src/ServerScriptService/Gameplay/BattleService"),
    Actions = require("../src/ServerScriptService/Gameplay/EggActions"),
    Mix = require("../src/ServerScriptService/Gameplay/MixService"),
}, Rules.new(Catalog), Catalog)
print(string.format("I-06 PASS: %d checks (memory backend)", result.checks))
