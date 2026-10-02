local result = require("./BattleFeed.spec").run(require("../src/ReplicatedStorage/Presentation/BattleFeed"))
print(string.format("Battle feed PASS: %d checks", result.checks))
