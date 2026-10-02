-- Merge server pushes/responses without replaying hits or rolling HP backwards.
local BattleFeed = {}
function BattleFeed.new()
    local current, lastSeq = nil, 0
    local retired = {}
    return {
        accept = function(view)
            if retired[view.battleId] then return nil end
            if current and current.battleId == view.battleId and view.revision <= current.revision then return nil end
            if current and current.battleId ~= view.battleId then
                retired[current.battleId] = true
                lastSeq = 0
            end
            current = view
            local events = {}
            for _, event in ipairs(view.events or {}) do
                if event.seq > lastSeq then table.insert(events, event); lastSeq = event.seq end
            end
            return events
        end,
    }
end
function BattleFeed.remaining(skill, now)
    return math.max(0, skill.readyAt - now)
end
return table.freeze(BattleFeed)
