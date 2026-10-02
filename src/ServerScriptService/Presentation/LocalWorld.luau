-- Prototype scenery and interaction affordances for the unpublished test place.
local LocalWorld = {}
function LocalWorld.build(nodes, training)
    local folder = Instance.new("Folder")
    folder.Name = "LocalScenery"
    folder.Parent = workspace
    local function block(name, size, position, color)
        local part = Instance.new("Part")
        part.Name, part.Size, part.Position, part.Color = name, size, position, color
        part.Anchored, part.CanCollide = true, false
        part.Material = Enum.Material.SmoothPlastic
        part.Parent = folder
        return part
    end
    local function prompt(part, action, object)
        local item = Instance.new("ProximityPrompt")
        item.Name = "JourneyPrompt"
        item.ActionText, item.ObjectText = action, object
        item.KeyboardKeyCode = Enum.KeyCode.E
        item.MaxActivationDistance = 10
        item.RequiresLineOfSight = false
        item.HoldDuration = 0
        item.Parent = part
    end
    for _, id in ipairs({"N01", "N02", "N03"}) do
        local node = nodes[id]
        prompt(node, "เก็บไข่ฟรี", "จุดไข่ " .. id)
        block("EggPedestal", Vector3.new(6, 0.4, 6), Vector3.new(node.Position.X, 0.2, node.Position.Z), Color3.fromRGB(196, 160, 83))
        for z = -6, -18, -6 do block("EggTrail", Vector3.new(2, 0.12, 3), Vector3.new(node.Position.X, 0.08, z), Color3.fromRGB(235, 207, 134)) end
    end
    prompt(training, "เลือกสัตว์เลี้ยงฝึก", "สนามฝึก")
    for x = 6, 18, 6 do block("TrainingTrail", Vector3.new(3, 0.12, 2), Vector3.new(x, 0.08, 12), Color3.fromRGB(143, 199, 245)) end
    for _, offset in ipairs({-5, 5}) do
        block("ArenaEdge", Vector3.new(0.3, 0.15, 11), training.Position + Vector3.new(offset, 0.57, 0), Color3.fromRGB(201, 235, 255))
    end
    for _, x in ipairs({-42, 42}) do
        for _, z in ipairs({-36, 0, 30}) do
            block("Trunk", Vector3.new(1.5, 5, 1.5), Vector3.new(x, 2.5, z), Color3.fromRGB(112, 85, 69))
            block("Leaves", Vector3.new(6, 5, 6), Vector3.new(x, 6, z), Color3.fromRGB(65, 132, 101))
        end
    end
end
function LocalWorld.update(world)
    local lighting = game:GetService("Lighting")
    lighting.ClockTime = if world.timeOfDay == "Day" then 13 else 21
    lighting.Brightness = if world.timeOfDay == "Day" then 2 else 1
    lighting.Ambient = if world.weather == "Rain" then Color3.fromRGB(109, 122, 146) else Color3.fromRGB(145, 145, 161)
    lighting.OutdoorAmbient = Color3.fromRGB(115, 125, 146)
end
return LocalWorld
