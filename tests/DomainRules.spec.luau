local Suite = {}

function Suite.run(DomainRules, Catalog)
    local rules = DomainRules.new(Catalog)
    local checks, cases = 0, 0
    local function check(condition, label)
        checks += 1
        assert(condition, label)
    end
    local function near(actual, expected, label)
        check(math.abs(actual - expected) < 1e-10, label)
    end
    local function rejects(callback, label)
        local success = pcall(callback)
        check(not success, label)
    end
    local function copy(value)
        if type(value) ~= "table" then return value end
        local result = {}
        for key, child in pairs(value) do result[key] = copy(child) end
        return result
    end
    local function creature(id, xp, stars, inherited)
        return { definitionId = id, totalXP = xp or 0, startingPotentialStars = stars or 0, winsSinceCreation = 0, inheritedSkillId = inherited }
    end
    local function candidate(preview, id)
        for _, item in ipairs(preview.candidates) do
            if item.definitionId == id then return item end
        end
        error("Missing candidate " .. id)
    end
    local function sameOutcomes(a, b, field)
        check(#a == #b, "Outcome counts match")
        for index, outcome in ipairs(a) do
            check(outcome[field] == b[index][field], "Outcome values match")
            near(outcome.probability, b[index].probability, "Outcome probabilities match")
        end
    end

    local expectedBase = {
        { "Common", "Common", "Uncommon", "Uncommon" },
        { "Common", "Uncommon", "Uncommon", "Rare" },
        { "Uncommon", "Uncommon", "Rare", "Rare" },
        { "Uncommon", "Rare", "Rare", "Epic" },
    }
    local expectedRarity = {
        Common = { Common = 0.9, Uncommon = 0.09, Rare = 0.01, Epic = 0 },
        Uncommon = { Common = 0, Uncommon = 0.9, Rare = 0.09, Epic = 0.01 },
        Rare = { Common = 0, Uncommon = 0, Rare = 0.9, Epic = 0.1 },
        Epic = { Common = 0, Uncommon = 0, Rare = 0, Epic = 1 },
    }
    local phaseTimes = { 0, 240, 360, 600 }
    for i = 1, 8 do
        for j = i, 8 do
            local a = creature(string.format("C%02d", i), 80, 2)
            local b = creature(string.format("C%02d", j), 480, 4)
            for _, time in ipairs(phaseTimes) do
                cases += 1
                local preview, swapped = rules.preview(a, b, time), rules.preview(b, a, time)
                local base = expectedBase[math.ceil(i / 2)][math.ceil(j / 2)]
                check(preview.baseRarity == base, "All ten base pairs")
                local sum, marginals = 0, { Common = 0, Uncommon = 0, Rare = 0, Epic = 0 }
                for _, outcome in ipairs(preview.candidates) do
                    local definition = rules.definition(outcome.definitionId)
                    check(outcome.probability > 0 and outcome.probability <= 1, "Positive candidate probability")
                    sum += outcome.probability
                    marginals[definition.rarity] += outcome.probability
                    local reverse = candidate(swapped, outcome.definitionId)
                    near(outcome.probability, reverse.probability, "Parent order invariance")
                    sameOutcomes(outcome.starsOutcomes, reverse.starsOutcomes, "stars")
                    sameOutcomes(outcome.inheritedOutcomes, reverse.inheritedOutcomes, "skillId")
                    local clear = candidate(rules.preview(a, b, 0), outcome.definitionId)
                    sameOutcomes(outcome.starsOutcomes, clear.starsOutcomes, "stars")
                    sameOutcomes(outcome.inheritedOutcomes, clear.inheritedOutcomes, "skillId")
                end
                near(sum, 1, "Total probability is one")
                for rarity, probability in pairs(marginals) do near(probability, expectedRarity[base][rarity], "World preserves rarity marginal") end
            end
        end
    end
    check(cases == 144, "All 36 pairs by four world phases")

    local first, second = creature("C01", 80, 2), creature("C03", 80, 4)
    near(candidate(rules.preview(first, second, 0), "C01").conditionalProbability, 9 / 11, "D-22 Day/Clear")
    local rainy = rules.preview(first, second, 600)
    for id, probability in pairs({ C01 = 0.45, C02 = 0.45, C03 = 0.072, C04 = 0.018, C05 = 0.005, C06 = 0.005 }) do
        near(candidate(rainy, id).probability, probability, "D-22 Night/Rain " .. id)
    end
    local waterSkills = rules.inheritedOutcomes(first, second, "C02")
    check(waterSkills[1].skillId == "U01" and waterSkills[2].skillId == "W01", "Water inherits compatible skills")
    near(waterSkills[1].probability, 0.5, "Equal skill weights")
    check(#rules.inheritedOutcomes(first, second, "C01") == 1, "Fire excludes Water skill")
    local duplicate = rules.inheritedOutcomes(creature("C01", 80, 0, "U01"), creature("C02", 80, 0, "U01"), "C01")
    near(duplicate[1].probability, 2 / 3, "Duplicate slots count once per parent")
    near(duplicate[2].probability, 1 / 3, "Single-parent weight")
    local empty = rules.inheritedOutcomes(creature("C01"), creature("C02"), "C01")
    check(#empty == 1 and empty[1].skillId == nil and empty[1].probability == 1, "Locked Growth gives empty inheritance")
    check(rules.inheritedOutcomes(creature("C01", 0, 0, "U01"), creature("C02"), "C02")[1].skillId == "U01", "Inherited is usable before Growth unlock")

    local stars, reset = rules.potentialOutcomes(creature("C01", 480, 2), creature("C03", 480, 4), "C02")
    check(not reset and stars[1].stars == 3 and stars[2].stars == 4, "Potential mean and cap")
    near(stars[2].probability, 0.019, "Level ten chance is 1.9 percent")
    local resetStars, didReset = rules.potentialOutcomes(first, second, "C05")
    check(didReset and #resetStars == 1 and resetStars[1].stars == 0, "New rarity resets before random bonus")
    check(#rules.potentialOutcomes(creature("C01", 80, 3), creature("C01", 80, 3), "C01") == 1, "Equal stars never exceed parental cap")

    for _, row in ipairs({ { 0, 1 }, { 19, 1 }, { 20, 2 }, { 79, 4 }, { 80, 5 }, { 119, 5 }, { 120, 6 }, { 180, 7 }, { 260, 8 }, { 360, 9 }, { 480, 10 } }) do
        check(rules.level(row[1]) == row[2], "XP boundary")
    end
    local trained = creature("C01")
    for win = 1, 30 do
        trained = rules.afterVictory(trained)
        if win == 4 then check(trained.totalXP == 80 and rules.level(trained.totalXP) == 5, "Four wins unlock Growth") end
        if win == 5 then check(rules.stars(0, trained.winsSinceCreation) == 1, "Fifth win grants first star") end
        if win >= 24 then check(trained.totalXP == 480, "XP caps after 24 wins") end
    end
    check(rules.stars(3, 5) == 4 and rules.stars(3, 10) == 5 and rules.stars(0, 30) == 5, "Training preserves starting stars")
    local stats = rules.stats(creature("C01", 80))
    check(stats.hp == 126 and stats.atk == 36 and stats.def == 26 and stats.spd == 20, "D-15 level five stats")
    check(rules.stats(creature("C01", 0, 5)).atk == 32, "D-15 Might bonus")
    check(rules.stats(creature("C02", 0, 5)).def == 32, "Guard bonus")
    check(rules.stats(creature("C01", 0, 5)).hp == 96, "Potential affects only matching stat")
    for _, definition in ipairs(Catalog.creatures) do
        for level = 1, 10 do
            for potential = 0, 5 do
                local actual = rules.stats(creature(definition.definitionId, Catalog.progression.xpThresholds[level], potential))
                -- Integer arithmetic is an independent reference for single final rounding.
                local atkBonus = if definition.speciesId == "Foxling" then 100 + 3 * potential else 100
                local defBonus = if definition.speciesId == "Shellkin" then 100 + 3 * potential else 100
                check(actual.atk == math.floor(definition.baseATK * (100 + 8 * (level - 1)) * atkBonus / 10000), "All level/star ATK combinations")
                check(actual.def == math.floor(definition.baseDEF * (100 + 8 * (level - 1)) * defBonus / 10000), "All level/star DEF combinations")
            end
        end
    end

    for _, row in ipairs({ { 239, "Day", "Clear", 240 }, { 240, "Day", "Rain", 360 }, { 359, "Day", "Rain", 360 }, { 360, "Night", "Clear", 600 }, { 599, "Night", "Clear", 600 }, { 600, "Night", "Rain", 720 }, { 719, "Night", "Rain", 720 }, { 720, "Day", "Clear", 960 } }) do
        local phase = rules.worldAt(row[1])
        check(phase.timeOfDay == row[2] and phase.weather == row[3] and phase.nextChangeAt == row[4], "World boundary")
    end
    check(rules.worldAt(0).phaseId ~= rules.worldAt(720).phaseId, "Phase ID includes cycle")
    check(rules.worldAt(239.99).weather == "Clear", "Fractional time before boundary")

    local a, b = rules.stats(creature("C01")), rules.stats(creature("C08"))
    local hpA, hpB = a.hp, b.hp
    for turn = 1, 4 do
        local aSkill, bSkill = if turn == 1 or turn == 4 then "S01" else "BASIC", if turn == 1 or turn == 4 then "S02" else "BASIC"
        hpB = math.max(0, hpB - rules.damage(a, b.def, aSkill, 0).hpDamage)
        hpA = math.max(0, hpA - rules.damage(b, a.def, bSkill, 0).hpDamage)
    end
    check(hpA == 0 and hpB == 18, "D-15 four-round damage example")
    check(rules.readyTurn("S01", 1) == 4, "Cooldown uses owner turns")
    check(rules.damage(a, b.def, "U01", 0).rawDamage == 27, "Pierce example")
    check(rules.damage(a, b.def, "U02", 0).rawDamage == 28, "Heavy Strike example")
    local shield = rules.damage({ atk = 20 }, 0, "BASIC", 8)
    check(shield.hpDamage == 12 and shield.remainingShield == 0, "Shield consumed once")
    check(rules.damage({ atk = 5 }, 0, "BASIC", 8).hpDamage == 0, "Shield can fully absorb damage")
    check(rules.shieldAmount("W01", 104) == 8, "Wave Guard grants eight percent MaxHP")
    check(rules.shieldAmount("BASIC", 104) == 0, "Basic attack has no shield")
    check(rules.rollEgg(function() return 0 end) == "C01", "Egg lower bound")
    check(rules.rollEgg(function() return 0.499999 end) == "C01", "Egg first half")
    check(rules.rollEgg(function() return 0.5 end) == "C02", "Egg second half")
    check(rules.rollEgg(function() return 0.999999 end) == "C02", "Egg upper interval")

    local function sequence(values)
        local index = 0
        return function()
            index += 1
            assert(values[index] ~= nil, "Unexpected extra RNG draw")
            return values[index]
        end
    end
    for _, boundary in ipairs({ { 0, "Common" }, { 0.899999, "Common" }, { 0.9, "Uncommon" }, { 0.989999, "Uncommon" }, { 0.99, "Rare" }, { 0.999999, "Rare" } }) do
        local child = rules.rollMix(creature("C01"), creature("C01"), 0, sequence({ boundary[1], 0 }))
        check(rules.definition(child.definitionId).rarity == boundary[2], "Rarity RNG interval")
        check(child.totalXP == 0 and child.winsSinceCreation == 0 and child.startingPotentialStars == 0, "New child progression resets")
    end
    local epicChild = rules.rollMix(creature("C07"), creature("C08"), 0, sequence({ 0 }))
    check(rules.definition(epicChild.definitionId).rarity == "Epic", "Deterministic Epic rarity needs no RNG draw")
    local before = first.totalXP
    rules.rollMix(first, second, 0, sequence({ 0, 0, 0 }))
    check(first.totalXP == before and first.startingPotentialStars == 2, "Rules do not mutate parents")

    rejects(function() rules.level(-1) end, "Negative XP")
    rejects(function() rules.level(481) end, "XP beyond schema cap")
    rejects(function() rules.level(0 / 0) end, "NaN XP")
    rejects(function() rules.stars(6, 0) end, "Stars beyond cap")
    rejects(function() rules.worldAt(math.huge) end, "Infinite time")
    rejects(function() rules.stats(creature("missing")) end, "Unknown definition")
    rejects(function() rules.stats(creature("C01", 0, 0, "S01")) end, "Species cannot be inherited")
    rejects(function() rules.stats(creature("C01", 0, 0, "W01")) end, "Incompatible inherited element")
    rejects(function() rules.rollMix(first, second, 0, function() return 1 end) end, "RNG excludes upper bound")
    rejects(function() Catalog.world.timeWeights.Day.Foxling = 9 end, "Catalog is deeply frozen")
    for _, badWeight in ipairs({ 0, -1, math.huge, 0 / 0 }) do
        local broken = copy(Catalog)
        broken.world.timeWeights.Day.Foxling = badWeight
        rejects(function() DomainRules.new(broken) end, "Reject invalid config weight")
    end
    local broken = copy(Catalog)
    broken.creatures[2].definitionId = "C01"
    rejects(function() DomainRules.new(broken) end, "Duplicate catalog ID")
    broken = copy(Catalog)
    broken.rarityProbabilities.Common.Common = 0.95
    rejects(function() DomainRules.new(broken) end, "Invalid probability sum")
    broken = copy(Catalog)
    broken.creatures[1].growthSkillId = "W01"
    rejects(function() DomainRules.new(broken) end, "Incompatible Growth config")
    broken = copy(Catalog)
    local isolated = DomainRules.new(broken)
    broken.world.timeWeights.Day.Foxling = 999
    near(candidate(isolated.preview(first, second, 0), "C01").conditionalProbability, 9 / 11, "Rules own immutable config snapshot")

    return { checks = checks, worldCases = cases }
end

return Suite
