-- Pure functions: no DataStore, network, clock or global random source.
local DomainRules = {}
local MAX_INTEGER = 9007199254740991

local function finite(value)
    return type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function integer(value, minimum, maximum)
    assert(finite(value) and value % 1 == 0 and value >= minimum and value <= maximum, "INVALID_INTEGER")
end

local function positive(value)
    assert(finite(value) and value > 0, "INVALID_WEIGHT")
end

local function frozenCopy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, child in pairs(value) do result[key] = frozenCopy(child) end
    return table.freeze(result)
end

local function compatible(skill, definition)
    if skill.compatibility == "Universal" then return true end
    if skill.compatibility == "Species" then
        return table.find(skill.allowedSpecies, definition.speciesId) ~= nil
    end
    if skill.compatibility == "Element" then
        return table.find(skill.allowedElements, definition.element) ~= nil
    end
    return false
end

function DomainRules.new(source)
    local config = frozenCopy(source)
    local definitions, rarityIndex = {}, {}
    assert(type(config.rulesVersion) == "string" and #config.rulesVersion > 0, "INVALID_VERSION")
    assert(#config.creatures == 8 and #config.rarities == 4, "INVALID_CATALOG_SIZE")
    for index, rarity in ipairs(config.rarities) do
        assert(not rarityIndex[rarity], "DUPLICATE_RARITY")
        rarityIndex[rarity] = index
    end
    for _, skill in pairs(config.skills) do
        positive(skill.multiplier)
        positive(skill.targetDefenseFactor)
        integer(skill.cooldownOwnerTurns, 0, MAX_INTEGER)
        assert(skill.sourceStat == "atk" or skill.sourceStat == "def", "INVALID_SOURCE_STAT")
        assert(finite(skill.shieldFraction) and skill.shieldFraction >= 0 and skill.shieldFraction <= 1, "INVALID_SHIELD")
        assert(skill.compatibility == "Species" or skill.compatibility == "Element" or skill.compatibility == "Universal", "INVALID_COMPATIBILITY")
        assert(type(skill.inheritable) == "boolean", "INVALID_INHERITANCE")
        assert(skill.compatibility ~= "Species" or not skill.inheritable, "SPECIES_INHERITANCE")
    end
    local buckets = {}
    for _, definition in ipairs(config.creatures) do
        assert(not definitions[definition.definitionId], "DUPLICATE_DEFINITION")
        assert(rarityIndex[definition.rarity], "INVALID_RARITY")
        local species = assert(config.species[definition.speciesId], "INVALID_SPECIES")
        assert(species.potentialType == "Might" or species.potentialType == "Guard" or species.potentialType == "Vitality", "INVALID_POTENTIAL_TYPE")
        assert(definition.element == "Fire" or definition.element == "Water", "INVALID_ELEMENT")
        for _, field in ipairs({ "baseHP", "baseATK", "baseDEF", "baseSPD" }) do integer(definition[field], 1, MAX_INTEGER) end
        local growth = assert(config.skills[definition.growthSkillId], "UNKNOWN_GROWTH")
        assert(growth.inheritable and compatible(growth, definition), "INCOMPATIBLE_GROWTH")
        assert(compatible(assert(config.skills[species.speciesSkillId], "UNKNOWN_SPECIES_SKILL"), definition), "INCOMPATIBLE_SPECIES")
        definitions[definition.definitionId] = definition
        buckets[definition.rarity] = buckets[definition.rarity] or {}
        table.insert(buckets[definition.rarity], definition)
    end
    for _, rarity in ipairs(config.rarities) do
        local bucket = assert(buckets[rarity], "EMPTY_RARITY")
        assert(#bucket == 2 and bucket[1].element ~= bucket[2].element, "INVALID_RARITY_COVERAGE")
        local sum = 0
        for outcome, probability in pairs(assert(config.rarityProbabilities[rarity], "MISSING_PROBABILITIES")) do
            assert(rarityIndex[outcome], "UNKNOWN_RARITY_OUTCOME")
            positive(probability)
            sum += probability
        end
        assert(math.abs(sum - 1) < 1e-12, "INVALID_PROBABILITY_SUM")
    end
    local progression, world = config.progression, config.world
    assert(#progression.xpThresholds == progression.levelCap and progression.xpThresholds[1] == 0, "INVALID_XP_CURVE")
    local previous = -1
    for _, threshold in ipairs(progression.xpThresholds) do
        integer(threshold, 0, MAX_INTEGER)
        assert(threshold > previous, "INVALID_XP_CURVE")
        previous = threshold
    end
    assert(previous == progression.xpCap, "INVALID_XP_CAP")
    integer(progression.winsPerStar, 1, MAX_INTEGER)
    integer(progression.starCap, 0, 5)
    integer(progression.growthLevel, 1, progression.levelCap)
    for _, field in ipairs({ "statGrowth", "starBonus", "inheritanceChance", "inheritancePerLevel", "inheritanceCap" }) do
        positive(progression[field])
    end
    assert(progression.inheritanceChance <= progression.inheritanceCap and progression.inheritanceCap <= 1, "INVALID_STAR_CHANCE")
    integer(world.epochUnix, 0, MAX_INTEGER)
    integer(world.cycleSeconds, 1, MAX_INTEGER)
    previous = 0
    assert(#world.phases == 4, "INVALID_PHASES")
    for _, phase in ipairs(world.phases) do
        integer(phase.endsAt, previous + 1, world.cycleSeconds)
        previous = phase.endsAt
        local timeWeights = assert(world.timeWeights[phase.timeOfDay], "INVALID_TIME")
        local weatherWeights = assert(world.weatherWeights[phase.weather], "INVALID_WEATHER")
        for _, definition in ipairs(config.creatures) do
            positive(timeWeights[definition.speciesId])
            positive(weatherWeights[definition.element])
        end
    end
    assert(previous == world.cycleSeconds, "INVALID_CYCLE")

    local rules = {}
    function rules.definition(id)
        return assert(definitions[id], "UNKNOWN_DEFINITION")
    end

    function rules.level(totalXP)
        integer(totalXP, 0, progression.xpCap)
        local level = 1
        for index, threshold in ipairs(progression.xpThresholds) do
            if totalXP < threshold then break end
            level = index
        end
        return level
    end

    function rules.stars(startingStars, wins)
        integer(startingStars, 0, progression.starCap)
        integer(wins, 0, MAX_INTEGER)
        return math.min(progression.starCap, startingStars + math.floor(wins / progression.winsPerStar))
    end

    function rules.validateCreature(creature)
        local definition = rules.definition(creature.definitionId)
        rules.level(creature.totalXP)
        rules.stars(creature.startingPotentialStars, creature.winsSinceCreation)
        if creature.inheritedSkillId then
            local skill = assert(config.skills[creature.inheritedSkillId], "UNKNOWN_SKILL")
            assert(skill.inheritable and compatible(skill, definition), "INVALID_INHERITED_SKILL")
        end
        return definition
    end

    function rules.stats(creature)
        local definition = rules.validateCreature(creature)
        local level = rules.level(creature.totalXP)
        local stars = rules.stars(creature.startingPotentialStars, creature.winsSinceCreation)
        local potentialType = config.species[definition.speciesId].potentialType
        -- Keep percentage factors integral to avoid flooring 29.999999... to 29.
        local growthPercent = 100 + (100 * progression.statGrowth) * (level - 1)
        local function stat(base, matchingType)
            local bonusPercent = if potentialType == matchingType then 100 + (100 * progression.starBonus) * stars else 100
            return math.floor(base * growthPercent * bonusPercent / 10000)
        end
        return { hp = stat(definition.baseHP, "Vitality"), atk = stat(definition.baseATK, "Might"), def = stat(definition.baseDEF, "Guard"), spd = definition.baseSPD + level - 1 }
    end

    function rules.afterVictory(creature)
        rules.validateCreature(creature)
        assert(creature.winsSinceCreation < MAX_INTEGER, "WINS_OVERFLOW")
        local result = table.clone(creature)
        result.totalXP = math.min(progression.xpCap, creature.totalXP + config.economy.victoryXP)
        result.winsSinceCreation += 1
        return result
    end

    function rules.worldAt(serverTime)
        assert(finite(serverTime) and serverTime >= 0 and serverTime <= MAX_INTEGER, "INVALID_TIME")
        local elapsed = serverTime - world.epochUnix
        local cycle = math.floor(elapsed / world.cycleSeconds)
        local offset = elapsed % world.cycleSeconds
        for index, phase in ipairs(world.phases) do
            if offset < phase.endsAt then
                return { cycleId = cycle, phaseId = tostring(cycle) .. ":" .. tostring(index), timeOfDay = phase.timeOfDay, weather = phase.weather, nextChangeAt = world.epochUnix + cycle * world.cycleSeconds + phase.endsAt, serverTime = serverTime, rulesVersion = config.rulesVersion }
            end
        end
        error("INVALID_PHASE")
    end

    function rules.baseRarity(firstId, secondId)
        local a = rarityIndex[rules.definition(firstId).rarity]
        local b = rarityIndex[rules.definition(secondId).rarity]
        return config.rarities[math.floor((a + b) / 2)]
    end

    function rules.potentialOutcomes(first, second, childId)
        local a, b, child = rules.validateCreature(first), rules.validateCreature(second), rules.definition(childId)
        if child.rarity ~= a.rarity and child.rarity ~= b.rarity then
            return { { stars = 0, probability = 1 } }, true
        end
        local firstStars = rules.stars(first.startingPotentialStars, first.winsSinceCreation)
        local secondStars = rules.stars(second.startingPotentialStars, second.winsSinceCreation)
        local base = math.floor((firstStars + secondStars) / 2)
        local cap = math.min(progression.starCap, math.max(firstStars, secondStars))
        if base >= cap then return { { stars = base, probability = 1 } }, false end
        local averageLevel = (rules.level(first.totalXP) + rules.level(second.totalXP)) / 2
        local chance = math.min(progression.inheritanceCap, progression.inheritanceChance + progression.inheritancePerLevel * (averageLevel - 1))
        return { { stars = base, probability = 1 - chance }, { stars = base + 1, probability = chance } }, false
    end

    function rules.inheritedOutcomes(first, second, childId)
        rules.validateCreature(first)
        rules.validateCreature(second)
        local child, weights = rules.definition(childId), {}
        for _, parent in ipairs({ first, second }) do
            local available = {}
            if parent.inheritedSkillId then available[parent.inheritedSkillId] = true end
            if rules.level(parent.totalXP) >= progression.growthLevel then
                available[rules.definition(parent.definitionId).growthSkillId] = true
            end
            for skillId in pairs(available) do
                local skill = config.skills[skillId]
                if skill.inheritable and compatible(skill, child) then weights[skillId] = (weights[skillId] or 0) + 1 end
            end
        end
        local ids, total = {}, 0
        for skillId, weight in pairs(weights) do table.insert(ids, skillId); total += weight end
        table.sort(ids)
        if total == 0 then return { { probability = 1 } } end
        local outcomes = {}
        for _, id in ipairs(ids) do table.insert(outcomes, { skillId = id, probability = weights[id] / total }) end
        return outcomes
    end

    function rules.preview(first, second, serverTime)
        local a, b = rules.validateCreature(first), rules.validateCreature(second)
        local current = rules.worldAt(serverTime)
        local base = rules.baseRarity(a.definitionId, b.definitionId)
        local result = { world = current, cost = config.economy.mixPrice, baseRarity = base, rarityProbabilities = {}, candidates = {} }
        for _, rarity in ipairs(config.rarities) do
            local probability = config.rarityProbabilities[base][rarity] or 0
            table.insert(result.rarityProbabilities, { rarity = rarity, probability = probability })
            if probability > 0 then
                local weights, total = {}, 0
                for _, child in ipairs(buckets[rarity]) do
                    local speciesFactor = 1 + (if a.speciesId == child.speciesId then 1 else 0) + (if b.speciesId == child.speciesId then 1 else 0)
                    local elementFactor = 1 + (if a.element == child.element then 1 else 0) + (if b.element == child.element then 1 else 0)
                    local weight = speciesFactor * elementFactor * world.timeWeights[current.timeOfDay][child.speciesId] * world.weatherWeights[current.weather][child.element]
                    positive(weight)
                    weights[child.definitionId] = weight
                    total += weight
                end
                positive(total)
                for _, child in ipairs(buckets[rarity]) do
                    local stars, reset = rules.potentialOutcomes(first, second, child.definitionId)
                    local conditional = weights[child.definitionId] / total
                    table.insert(result.candidates, { definitionId = child.definitionId, conditionalProbability = conditional, probability = probability * conditional, resetPotential = reset, starsOutcomes = stars, inheritedOutcomes = rules.inheritedOutcomes(first, second, child.definitionId) })
                end
            end
        end
        return result
    end

    local function pick(outcomes, nextNumber)
        if #outcomes == 1 then return outcomes[1] end
        local roll = nextNumber()
        assert(finite(roll) and roll >= 0 and roll < 1, "INVALID_RANDOM_VALUE")
        local sum = 0
        for _, outcome in ipairs(outcomes) do
            sum += outcome.probability
            if roll < sum then return outcome end
        end
        assert(math.abs(sum - 1) < 1e-12, "INVALID_DISTRIBUTION")
        return outcomes[#outcomes]
    end

    -- Evaluates a result only. Ownership, preview freshness and durable commit belong to I-02/I-03/I-05.
    function rules.rollMix(first, second, serverTime, nextNumber)
        local preview = rules.preview(first, second, serverTime)
        local rarities = {}
        for _, outcome in ipairs(preview.rarityProbabilities) do
            if outcome.probability > 0 then table.insert(rarities, outcome) end
        end
        local rarity = pick(rarities, nextNumber).rarity
        local candidates = {}
        for _, candidate in ipairs(preview.candidates) do
            if rules.definition(candidate.definitionId).rarity == rarity then
                local conditional = table.clone(candidate)
                conditional.probability = candidate.conditionalProbability
                table.insert(candidates, conditional)
            end
        end
        local child = pick(candidates, nextNumber)
        return { definitionId = child.definitionId, totalXP = 0, startingPotentialStars = pick(child.starsOutcomes, nextNumber).stars, winsSinceCreation = 0, inheritedSkillId = pick(child.inheritedOutcomes, nextNumber).skillId }
    end

    function rules.rollEgg(nextNumber)
        return pick(config.economy.eggOutcomes, nextNumber).definitionId
    end

    function rules.shieldAmount(skillId, maxHP)
        integer(maxHP, 1, MAX_INTEGER)
        return math.floor(maxHP * assert(config.skills[skillId], "UNKNOWN_SKILL").shieldFraction)
    end

    function rules.damage(attackerStats, targetDefense, skillId, shield)
        local skill = assert(config.skills[skillId], "UNKNOWN_SKILL")
        integer(attackerStats[skill.sourceStat], 1, MAX_INTEGER)
        integer(targetDefense, 0, MAX_INTEGER)
        integer(shield, 0, MAX_INTEGER)
        local raw = math.max(1, math.floor(attackerStats[skill.sourceStat] * skill.multiplier * 100 / (100 + targetDefense * skill.targetDefenseFactor)))
        return { rawDamage = raw, hpDamage = math.max(0, raw - shield), remainingShield = 0 }
    end

    function rules.readyTurn(skillId, usedTurn)
        integer(usedTurn, 1, MAX_INTEGER - 3)
        return usedTurn + assert(config.skills[skillId], "UNKNOWN_SKILL").cooldownOwnerTurns + 1
    end

    return table.freeze(rules)
end

return table.freeze(DomainRules)
