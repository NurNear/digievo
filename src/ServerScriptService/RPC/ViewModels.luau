local ViewModels = {}

local function cloneArray(items)
    local result = {}
    for index, item in ipairs(items) do
        result[index] = table.clone(item)
    end
    return result
end

function ViewModels.creature(rules, catalog, creature)
    local definition = rules.definition(creature.definitionId)
    local species = catalog.species[definition.speciesId]
    local level = rules.level(creature.totalXP)
    local slots = {
        { role = "Species", skillId = species.speciesSkillId, unlocked = true },
        { role = "Inherited", skillId = creature.inheritedSkillId, unlocked = creature.inheritedSkillId ~= nil },
        { role = "Growth", skillId = definition.growthSkillId, unlocked = level >= catalog.progression.growthLevel },
    }
    return {
        instanceId = creature.instanceId,
        definitionId = creature.definitionId,
        level = level,
        totalXP = creature.totalXP,
        potentialType = species.potentialType,
        stars = rules.stars(creature.startingPotentialStars, creature.winsSinceCreation),
        isLocked = creature.isLocked,
        stats = rules.stats(creature),
        slots = slots,
    }
end

function ViewModels.receipt(receipt)
    return {
        operationId = receipt.operationId,
        seq = receipt.seq,
        kind = receipt.kind,
        committedAt = receipt.committedAt,
        result = receipt.result,
    }
end

function ViewModels.profile(rules, catalog, profile)
    local creatures, nodes, receipts = {}, {}, {}
    for _, creature in pairs(profile.creatures) do
        table.insert(creatures, ViewModels.creature(rules, catalog, creature))
    end
    table.sort(creatures, function(a, b) return a.instanceId < b.instanceId end)
    for _, nodeId in ipairs(catalog.economy.nodeIds) do
        table.insert(nodes, { nodeId = nodeId, nextAvailableAt = profile.nodeNextAvailableAt[nodeId] })
    end
    for _, receipt in ipairs(profile.receipts) do
        table.insert(receipts, ViewModels.receipt(receipt))
    end
    return {
        profileVersion = profile.profileVersion,
        coinBalance = profile.coinBalance,
        basicEggCount = profile.basicEggCount,
        pendingEggRewards = profile.pendingEggRewards,
        capacity = { creatures = catalog.economy.creatureCapacity, eggs = catalog.economy.eggCapacity },
        creatures = creatures,
        nodes = nodes,
        recentReceipts = receipts,
        unresolvedOperationId = if profile.preparedOperation then profile.preparedOperation.operationId else nil,
    }
end

function ViewModels.world(rules, serverTime)
    return rules.worldAt(serverTime)
end

function ViewModels.mixPreview(rules, previewId, expiresAt, profileVersion, parentIds, first, second, serverTime)
    local preview = rules.preview(first, second, serverTime)
    return {
        previewId = previewId,
        expiresAt = expiresAt,
        profileVersion = profileVersion,
        world = preview.world,
        cost = preview.cost,
        parentIds = table.clone(parentIds),
        baseRarity = preview.baseRarity,
        rarityProbabilities = cloneArray(preview.rarityProbabilities),
        candidates = cloneArray(preview.candidates),
    }
end

return table.freeze(ViewModels)
