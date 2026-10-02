local Suite = {}
function Suite.run(Guide, Styles, Catalog)
    local checks = 0
    local function check(value, message)
        checks += 1
        assert(value, message)
    end
    local function creature(locked, xp)
        return {isLocked = locked or false, totalXP = xp or 0}
    end
    local function profile(creatures, eggs, coins)
        return {creatures = creatures, basicEggCount = eggs or 0, coinBalance = coins or 20,
            pendingEggRewards = 0, recentReceipts = {}, capacity = {eggs = 20, creatures = 30}}
    end
    local function expect(view, id, tab, battle, busy)
        local result = Guide.next(view, battle, busy)
        check(result.id == id and result.tab == tab, "Unexpected guide: " .. result.id .. " expected " .. id)
        check(#result.text > 0, "Every step needs explanatory text")
    end
    -- Follow the actual first-session loop, then boundary conditions that could
    -- otherwise recommend an impossible/destructive next action.
    expect(nil, "loading", nil)
    expect(profile({}, 1), "hatch", "eggs")
    expect(profile({creature()}, 0), "collect", "eggs")
    expect(profile({creature()}, 1), "hatch", "eggs")
    local pair = profile({creature(), creature()})
    expect(pair, "train", "pets")
    expect(pair, "battle", "battle", {status = "active"})
    expect(pair, "battle", "battle", {status = "resolving"})
    pair.creatures[1].totalXP = 20
    expect(pair, "mix", "mix", {status = "ended", outcome = "win"})
    expect(pair, "pending", nil, nil, true)
    pair.unresolvedOperationId = "pending-mix"
    expect(pair, "pending", nil)
    pair.unresolvedOperationId = nil
    pair.recentReceipts = {{kind = "Mix.Commit"}}
    expect(pair, "train", "pets")
    check(#pair.creatures == 2 and pair.creatures[1].totalXP == 20 and pair.coinBalance == 20, "Guide must not mutate profile")
    expect(profile({}, 0, 0), "collect", "eggs")
    expect(profile({creature(), creature()}, 0, 0), "train", "pets")
    expect(profile({creature(true), creature(true)}), "unlock", "pets")
    local full = profile({creature(), creature()}, 1)
    full.capacity.creatures = 2
    expect(full, "mix", "mix")
    full.coinBalance = 0
    expect(full, "train", "pets")
    full.creatures[1].isLocked = true
    expect(full, "unlock", "pets")
    local reward = profile({creature()}, 0)
    reward.pendingEggRewards = 1
    expect(reward, "claim", "eggs")
    reward.basicEggCount = 20
    expect(reward, "hatch", "eggs")
    expect(reward, "battle", "battle", {status = "active"})
    expect(reward, "pending", nil, {status = "active"}, true)
    check(Guide.world({timeOfDay = "Day", weather = "Clear"}) == "กลางวัน • ฟ้าใส", "Thai clear daytime")
    check(Guide.world({timeOfDay = "Night", weather = "Rain"}) == "กลางคืน • ฝนตก", "Thai rainy nighttime")
    local signatures, count = {}, 0
    for _, definition in ipairs(Catalog.creatures) do
        local style = Styles[definition.definitionId]
        check(style ~= nil, "Every catalog definition needs a visual")
        check(style.shape == definition.speciesId, "Visual species must match rules")
        check(style.marks >= 1 and style.marks <= 4, "Bounded geometry")
        for _, rgb in ipairs({style.body, style.accent}) do
            check(#rgb == 3, "RGB triplet")
            for _, channel in ipairs(rgb) do check(channel >= 0 and channel <= 255, "Valid color") end
        end
        local signature = style.shape .. table.concat(style.body, ",") .. table.concat(style.accent, ",") .. style.marks
        check(not signatures[signature], "Each pet needs a distinct variant")
        signatures[signature] = true
        count += 1
    end
    check(count == 8, "Eight prototype variants")
    local styleCount = 0
    for _ in pairs(Styles) do styleCount += 1 end
    check(styleCount == count, "No styles outside the catalog")
    return {checks = checks}
end
return Suite
