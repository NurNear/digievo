local Styles = require(script.Parent:WaitForChild("PetStyles"))
local PetModel = {}
function PetModel.create(parent, definitionId, pivot)
    local style = assert(Styles[definitionId], "Missing pet style")
    local bodyColor, accent = Color3.fromRGB(table.unpack(style.body)), Color3.fromRGB(table.unpack(style.accent))
    local model = Instance.new("Model")
    model.Name = definitionId
    local function box(name, size, position, color)
        local part = Instance.new("Part")
        part.Name, part.Size, part.Position, part.Color = name, size, position, color
        part.Anchored, part.CanCollide, part.CanTouch, part.CanQuery = true, false, false, false
        part.Material = Enum.Material.SmoothPlastic
        part.Parent = model
        return part
    end
    local body = box("Body", Vector3.new(2, 1.7, 2), Vector3.zero, bodyColor)
    model.PrimaryPart = body
    local faceZ = 1.05
    if style.shape == "Foxling" then
        for _, x in ipairs({-0.67, 0.67}) do
            box("Ear", Vector3.new(0.55, 0.85, 0.6), Vector3.new(x, 1.08, 0), bodyColor)
            box("InnerEar", Vector3.new(0.28, 0.5, 0.08), Vector3.new(x, 1.15, 0.33), accent)
        end
        box("Muzzle", Vector3.new(1.15, 0.5, 0.25), Vector3.new(0, -0.3, 1.08), accent)
        box("Tail", Vector3.new(0.65, 0.65, 1.3), Vector3.new(0, -0.15, -1.5), bodyColor)
        box("TailTip", Vector3.new(0.7, 0.7, 0.45), Vector3.new(0, -0.15, -2.03), accent)
    else
        body.Size = Vector3.new(2.3, 1.45, 2.3)
        box("Shell", Vector3.new(2.4, 0.6, 2.4), Vector3.new(0, 0.6, -0.12), accent)
        box("Head", Vector3.new(1.5, 1.1, 0.85), Vector3.new(0, -0.15, 1.25), bodyColor)
        faceZ = 1.7
    end
    for _, x in ipairs({-0.42, 0.42}) do
        box("Eye", Vector3.new(0.2, 0.28, 0.1), Vector3.new(x, 0.17, faceZ), Color3.fromRGB(19, 30, 45))
    end
    for _, x in ipairs({-0.75, 0.75}) do
        for _, z in ipairs({-0.6, 0.6}) do box("Foot", Vector3.new(0.55, 0.4, 0.6), Vector3.new(x, -0.9, z), bodyColor) end
    end
    for index = 1, style.marks do
        box("Mark", Vector3.new(0.22, 0.12, 0.55), Vector3.new((index - (style.marks + 1) / 2) * 0.4, 0.95, 0), accent:Lerp(Color3.new(1, 1, 1), 0.5))
    end
    model:PivotTo(pivot or CFrame.new())
    model.Parent = parent
    return model, body
end
function PetModel.preview(parent, definitionId)
    local viewport = Instance.new("ViewportFrame")
    viewport.Name = "PetPreview"
    viewport.Size = UDim2.fromScale(1, 1)
    viewport.BackgroundTransparency = 1
    viewport.Ambient = Color3.fromRGB(205, 205, 220)
    local world = Instance.new("WorldModel")
    world.Parent = viewport
    PetModel.create(world, definitionId, CFrame.Angles(0, math.rad(-20), 0))
    local camera = Instance.new("Camera")
    camera.CFrame = CFrame.lookAt(Vector3.new(0, 2, 6.5), Vector3.zero)
    camera.FieldOfView = 38
    camera.Parent = viewport
    viewport.CurrentCamera = camera
    viewport.Parent = parent
    return viewport
end
return PetModel
