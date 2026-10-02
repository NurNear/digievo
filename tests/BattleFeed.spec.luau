local Suite = {}
function Suite.run(Feed)
    local checks = 0
    local function check(value, message) checks += 1; assert(value, message) end
    local feed = Feed.new()
    local function view(id, revision, seqs)
        local events = {}
        for _, seq in ipairs(seqs) do table.insert(events, {seq = seq}) end
        return {battleId = id, revision = revision, events = events}
    end
    check(#feed.accept(view("a", 1, {})) == 0, "start")
    check(#feed.accept(view("a", 3, {1, 2})) == 2, "push contains two hits")
    check(feed.accept(view("a", 2, {1})) == nil, "stale response cannot roll HP back")
    check(feed.accept(view("a", 3, {1, 2})) == nil, "duplicate response does not replay hits")
    local events = feed.accept(view("a", 5, {1, 2, 3, 4}))
    check(#events == 2 and events[1].seq == 3, "recover missed push from history without duplicates")
    check(#feed.accept(view("b", 1, {})) == 0, "new battle resets event sequence")
    check(feed.accept(view("a", 99, {5})) == nil, "retired battle ignored")
    check(#feed.accept(view("b", 2, {1})) == 1, "new battle hit")
    check(Feed.remaining({readyAt = 10}, 9.75) == 0.25, "fractional seconds")
    check(Feed.remaining({readyAt = 10}, 10) == 0, "exact deadline")
    check(Feed.remaining({readyAt = 10}, 20) == 0, "no negative cooldown")
    return {checks = checks}
end
return Suite
