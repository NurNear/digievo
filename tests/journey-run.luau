local result = require("./Journey.spec").run(
    require("../src/ReplicatedStorage/Presentation/Guide"),
    require("../src/ReplicatedStorage/Presentation/PetStyles"),
    require("../src/ReplicatedStorage/Shared/Catalog")
)
print(string.format("I-07 PASS: %d checks (journey guidance and visual catalog)", result.checks))
