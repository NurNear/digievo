--!strict
-- Baseline v1.0: docs/design/06_DOMAIN_RULES.md, D-01 through D-22.
local catalog = {
    rulesVersion = "mvp-1.1.0",
    rarities = { "Common", "Uncommon", "Rare", "Epic" },
    species = {
        Foxling = { potentialType = "Might", speciesSkillId = "S01" },
        Shellkin = { potentialType = "Guard", speciesSkillId = "S02" },
    },
    creatures = {
        { definitionId = "C01", displayName = "จิ้งจอกประกาย", speciesId = "Foxling", element = "Fire", rarity = "Common", baseHP = 96, baseATK = 28, baseDEF = 20, baseSPD = 16, growthSkillId = "U01" },
        { definitionId = "C02", displayName = "เต่าหยดน้ำ", speciesId = "Shellkin", element = "Water", rarity = "Common", baseHP = 120, baseATK = 22, baseDEF = 28, baseSPD = 8, growthSkillId = "U02" },
        { definitionId = "C03", displayName = "จิ้งจอกละออง", speciesId = "Foxling", element = "Water", rarity = "Uncommon", baseHP = 104, baseATK = 25, baseDEF = 22, baseSPD = 17, growthSkillId = "W01" },
        { definitionId = "C04", displayName = "เต่าถ่าน", speciesId = "Shellkin", element = "Fire", rarity = "Uncommon", baseHP = 112, baseATK = 25, baseDEF = 30, baseSPD = 7, growthSkillId = "F01" },
        { definitionId = "C05", displayName = "จิ้งจอกอำพัน", speciesId = "Foxling", element = "Fire", rarity = "Rare", baseHP = 90, baseATK = 31, baseDEF = 18, baseSPD = 18, growthSkillId = "F01" },
        { definitionId = "C06", displayName = "เต่าคราม", speciesId = "Shellkin", element = "Water", rarity = "Rare", baseHP = 126, baseATK = 20, baseDEF = 32, baseSPD = 6, growthSkillId = "W01" },
        { definitionId = "C07", displayName = "จิ้งจอกจันทรา", speciesId = "Foxling", element = "Water", rarity = "Epic", baseHP = 100, baseATK = 24, baseDEF = 26, baseSPD = 19, growthSkillId = "W01" },
        { definitionId = "C08", displayName = "เต่าลาวา", speciesId = "Shellkin", element = "Fire", rarity = "Epic", baseHP = 110, baseATK = 24, baseDEF = 34, baseSPD = 6, growthSkillId = "F01" },
    },
    skills = {
        BASIC = { compatibility = "Universal", inheritable = false, sourceStat = "atk", multiplier = 1, targetDefenseFactor = 1, cooldownSeconds = 0, shieldFraction = 0 },
        S01 = { compatibility = "Species", allowedSpecies = { "Foxling" }, inheritable = false, sourceStat = "atk", multiplier = 1.25, targetDefenseFactor = 1, cooldownSeconds = 6, shieldFraction = 0 },
        S02 = { compatibility = "Species", allowedSpecies = { "Shellkin" }, inheritable = false, sourceStat = "def", multiplier = 1.10, targetDefenseFactor = 1, cooldownSeconds = 6, shieldFraction = 0 },
        U01 = { compatibility = "Universal", inheritable = true, sourceStat = "atk", multiplier = 1.15, targetDefenseFactor = 0.5, cooldownSeconds = 6, shieldFraction = 0 },
        U02 = { compatibility = "Universal", inheritable = true, sourceStat = "atk", multiplier = 1.35, targetDefenseFactor = 1, cooldownSeconds = 6, shieldFraction = 0 },
        F01 = { compatibility = "Element", allowedElements = { "Fire" }, inheritable = true, sourceStat = "atk", multiplier = 1.50, targetDefenseFactor = 1, cooldownSeconds = 6, shieldFraction = 0 },
        W01 = { compatibility = "Element", allowedElements = { "Water" }, inheritable = true, sourceStat = "atk", multiplier = 1.10, targetDefenseFactor = 1, cooldownSeconds = 6, shieldFraction = 0.08 },
    },
    rarityProbabilities = {
        Common = { Common = 0.90, Uncommon = 0.09, Rare = 0.01 },
        Uncommon = { Uncommon = 0.90, Rare = 0.09, Epic = 0.01 },
        Rare = { Rare = 0.90, Epic = 0.10 },
        Epic = { Epic = 1 },
    },
    combat = {baseAttackSeconds = 2.4, speedSecondsPerPoint = 0.025, minAttackSeconds = 1, shieldSeconds = 4},
    progression = {
        xpThresholds = { 0, 20, 40, 60, 80, 120, 180, 260, 360, 480 },
        levelCap = 10, xpCap = 480, growthLevel = 5,
        winsPerStar = 5, starCap = 5, statGrowth = 0.08, starBonus = 0.03,
        inheritanceChance = 0.01, inheritancePerLevel = 0.001, inheritanceCap = 0.03,
    },
    economy = {
        starterEggs = 1, starterCoins = 20, eggPrice = 40, mixPrice = 20,
        victoryCoins = 20, victoryXP = 20, victoryEggChance = 0.20,
        creatureCapacity = 30, eggCapacity = 20, hatchSeconds = 3,
        nodeIds = { "N01", "N02", "N03" }, nodeCooldownSeconds = 90,
        eggOutcomes = { { definitionId = "C01", probability = 0.5 }, { definitionId = "C02", probability = 0.5 } },
    },
    world = {
        epochUnix = 0, cycleSeconds = 720,
        phases = {
            { endsAt = 240, timeOfDay = "Day", weather = "Clear" },
            { endsAt = 360, timeOfDay = "Day", weather = "Rain" },
            { endsAt = 600, timeOfDay = "Night", weather = "Clear" },
            { endsAt = 720, timeOfDay = "Night", weather = "Rain" },
        },
        timeWeights = { Day = { Foxling = 1.5, Shellkin = 1 }, Night = { Foxling = 1, Shellkin = 1.5 } },
        weatherWeights = { Clear = { Fire = 1, Water = 1 }, Rain = { Fire = 1, Water = 2 } },
    },
}

local function freeze(value: any): any
    if type(value) == "table" then
        for _, child in pairs(value) do freeze(child) end
        table.freeze(value)
    end
    return value
end

return freeze(catalog)
