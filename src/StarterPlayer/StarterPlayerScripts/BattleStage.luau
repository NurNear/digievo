-- Client-only presentation. HP and event order always come from the server.
local TweenService = game:GetService("TweenService")
local replicated = game:GetService("ReplicatedStorage")
local Catalog = require(replicated:WaitForChild("Shared"):WaitForChild("Catalog"))
local PetModel = require(replicated:WaitForChild("Presentation"):WaitForChild("PetModel"))
local Stage = {}
local definitions = {}
for _, definition in ipairs(Catalog.creatures) do definitions[definition.definitionId] = definition end
function Stage.name(id)
    return if definitions[id] then definitions[id].displayName else id
end
local function make(class, parent, properties)
    local item = Instance.new(class)
    for key, value in pairs(properties) do item[key] = value end
    item.Parent = parent
    return item
end
local function tween(item, duration, properties)
    local animation = TweenService:Create(item, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), properties)
    animation:Play()
    return animation
end
function Stage.new()
    local fighters, meters = {}, {}
    local world, battleId, cameraState
    local generation = 0
    local function restoreCamera()
        if not cameraState then return end
        local camera = workspace.CurrentCamera
        if camera == cameraState.camera and camera.CameraType == Enum.CameraType.Scriptable then
            camera.CameraType = cameraState.kind
            if cameraState.subject and cameraState.subject.Parent then camera.CameraSubject = cameraState.subject end
            camera.FieldOfView = cameraState.fov
            camera.CFrame = cameraState.frame
        end
        cameraState = nil
    end
    local function clear()
        for _, fighter in pairs(fighters) do
            if fighter.connection then fighter.connection:Disconnect() end
            if fighter.animation then fighter.animation:Cancel() end
            if fighter.motion then fighter.motion:Destroy() end
        end
        if world then world:Destroy() end
        fighters, meters, world = {}, {}, nil
    end
    local function part(parent, size, position, color)
        return make("Part", parent, {Anchored = true, CanCollide = false, CanTouch = false, CanQuery = false,
            Size = size, Position = position, Color = color, Material = Enum.Material.Neon})
    end
    local function createScene(view)
        clear()
        generation += 1
        battleId = view.battleId
        local pad = workspace:FindFirstChild("TrainingArena")
        if not pad then return false end
        local center = pad.Position + Vector3.new(0, pad.Size.Y / 2 + 1.1, 0)
        world = make("Folder", workspace, {Name = "LocalBattlePets"})
        local camera = workspace.CurrentCamera
        if camera and not cameraState then
            cameraState = {camera = camera, kind = camera.CameraType, subject = camera.CameraSubject, frame = camera.CFrame, fov = camera.FieldOfView}
        end
        if camera then
            camera.CameraType = Enum.CameraType.Scriptable
            camera.FieldOfView = 55
            camera.CFrame = CFrame.lookAt(center + Vector3.new(0, 10, 16), center)
        end
        for _, side in ipairs({"player", "enemy"}) do
            local left = side == "player"
            local home = CFrame.new(center + Vector3.new(if left then -3.4 else 3.4, 0, 0)) * CFrame.Angles(0, if left then math.pi / 2 else -math.pi / 2, 0)
            local id = view[side].definitionId
            local model, body = PetModel.create(world, id, home)
            fighters[side] = {model = model, body = body, baseColor = body.Color, home = home, definitionId = id, flashId = 0}
            local billboard = make("BillboardGui", body, {Name = "Health", Size = UDim2.fromOffset(190, 66), StudsOffsetWorldSpace = Vector3.new(0, 3, 0), AlwaysOnTop = true})
            local title = make("TextLabel", billboard, {Size = UDim2.new(1, 0, 0, 48), BackgroundColor3 = Color3.fromRGB(22, 32, 45), BackgroundTransparency = 0.15,
                TextColor3 = Color3.new(1, 1, 1), TextSize = 14, TextWrapped = true, Text = ""})
            make("UICorner", title, {CornerRadius = UDim.new(0, 8)})
            local track = make("Frame", billboard, {Position = UDim2.fromOffset(6, 52), Size = UDim2.new(1, -12, 0, 8), BackgroundColor3 = Color3.fromRGB(58, 69, 82), BorderSizePixel = 0})
            local fill = make("Frame", track, {Size = UDim2.fromScale(1, 1), BackgroundColor3 = if left then Color3.fromRGB(73, 213, 167) else Color3.fromRGB(255, 139, 105), BorderSizePixel = 0})
            meters[side] = {title = title, fill = fill}
        end
        return true
    end
    local api = {}
    local function meter(side, fighter)
        meters[side].title.Text = (if side == "player" then "คุณ • " else "คู่ฝึก • ") .. Stage.name(fighter.definitionId) .. "\nHP " .. fighter.currentHP .. "/" .. fighter.stats.hp .. (if fighter.shield > 0 then " • โล่ " .. fighter.shield else "")
        tween(meters[side].fill, 0.2, {Size = UDim2.fromScale(math.clamp(fighter.currentHP / fighter.stats.hp, 0, 1), 1)})
    end
    function api.show(view)
        if battleId ~= view.battleId or not world then
            if not createScene(view) then return end
        end
        for _, side in ipairs({"player", "enemy"}) do
            local fighter = fighters[side]
            fighter.defeated = view[side].currentHP == 0
            if not fighter.motion then
                fighter.model:PivotTo(fighter.home * (if fighter.defeated then CFrame.Angles(0, 0, math.rad(70)) else CFrame.new()))
            end
            meter(side, view[side])
        end
    end
    function api.play(view, events)
        -- HP and cooldowns update immediately. Effects never block input/network.
        api.show(view)
        if not world then return end
        local sceneGeneration = generation
        for _, event in ipairs(events) do
            -- A recovery snapshot can contain historical hits; do not burst them.
            if workspace:GetServerTimeNow() - event.at > 1 then continue end
            local targetSide = if event.actor == "player" then "enemy" else "player"
            local attacker, target = fighters[event.actor], fighters[targetSide]
            if attacker.connection then attacker.connection:Disconnect() end
            if attacker.animation then attacker.animation:Cancel() end
            if attacker.motion then attacker.motion:Destroy() end
            local motion = Instance.new("CFrameValue")
            motion.Value = attacker.home
            attacker.motion = motion
            attacker.connection = motion.Changed:Connect(function(value) attacker.model:PivotTo(value) end)
            attacker.animation = tween(motion, 0.12, {Value = attacker.home + Vector3.new(if event.actor == "player" then 4.3 else -4.3, 0.25, 0)})
            task.delay(0.12, function()
                if generation ~= sceneGeneration or attacker.motion ~= motion then return end
                attacker.animation = tween(motion, 0.16, {Value = attacker.home})
                task.delay(0.16, function()
                    if generation ~= sceneGeneration or attacker.motion ~= motion then return end
                    attacker.connection:Disconnect()
                    motion:Destroy()
                    attacker.connection, attacker.motion, attacker.animation = nil, nil, nil
                    attacker.model:PivotTo(attacker.home * (if attacker.defeated then CFrame.Angles(0, 0, math.rad(70)) else CFrame.new()))
                end)
            end)
            target.flashId += 1
            local flashId, body = target.flashId, target.body
            body.Color = Color3.new(1, 1, 1)
            task.delay(0.12, function()
                if generation == sceneGeneration and target.flashId == flashId and target.body == body and body.Parent then body.Color = target.baseColor end
            end)
            local flash = part(world, Vector3.new(0.6, 0.6, 0.6), target.home.Position + Vector3.new(0, 0, 1.2), if event.skillId == "W01" then Color3.fromRGB(103, 210, 255) else Color3.fromRGB(255, 215, 94))
            flash.Shape = Enum.PartType.Ball
            tween(flash, 0.25, {Size = Vector3.new(3.4, 3.4, 3.4), Transparency = 1})
            game:GetService("Debris"):AddItem(flash, 0.3)
            local damage = make("BillboardGui", body, {Size = UDim2.fromOffset(150, 50), StudsOffsetWorldSpace = Vector3.new(0, 1.8, 0), AlwaysOnTop = true})
            local text = make("TextLabel", damage, {Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
                Text = "−" .. event.hpDamage .. (if event.shieldAbsorbed > 0 then " • โล่ " .. event.shieldAbsorbed else ""), TextSize = 24,
                TextColor3 = Color3.fromRGB(255, 218, 103), TextStrokeTransparency = 0.3})
            tween(damage, 0.6, {StudsOffsetWorldSpace = Vector3.new(0, 3.3, 0)})
            tween(text, 0.6, {TextTransparency = 1, TextStrokeTransparency = 1})
            game:GetService("Debris"):AddItem(damage, 0.65)
        end
    end
    function api.release()
        generation += 1
        clear()
        restoreCamera()
        battleId = nil
    end
    return api
end
return Stage
