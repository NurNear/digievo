local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local remotes = game:GetService("ReplicatedStorage"):WaitForChild("GameRemotes")
local gui = Instance.new("ScreenGui")
gui.Name = "Digievo"
gui.ResetOnSpawn = false
gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
local panel = Instance.new("ScrollingFrame")
panel.AutomaticCanvasSize = Enum.AutomaticSize.Y
panel.CanvasSize = UDim2.new()
panel.Size = UDim2.new(0, 360, 0.9, 0)
panel.Position = UDim2.new(0, 16, 0.05, 0)
panel.BackgroundColor3 = Color3.fromRGB(24, 34, 47)
panel.Parent = gui
local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 7)
layout.Parent = panel
local function label(text, height)
    local item = Instance.new("TextLabel")
    item.Size = UDim2.new(1, 0, 0, height or 32)
    item.BackgroundTransparency = 1
    item.TextColor3 = Color3.new(1, 1, 1)
    item.TextSize = 16
    item.TextWrapped = true
    item.Text = text
    item.Parent = panel
    return item
end
label("DIGIEVO • ทดลองในเครื่อง", 36)
label("เดินด้วย WASD • ข้อมูลหายเมื่อหยุด Play", 28)
local balance = label("กำลังโหลดข้อมูล…")
local worldLabel = label("กำลังอ่านสภาพโลก…", 28)
local notice = label("เดินเข้าใกล้ลูกบอลสีทองเพื่อเก็บไข่", 44)
local pending, profile, busy = {}, nil, false
local presentingHatch, deferredView = false, nil
local errors = {OUT_OF_RANGE = "เดินเข้าใกล้จุดเก็บไข่ (ไม่เกิน 12 studs)", NODE_UNAVAILABLE = "จุดนี้ยังไม่พร้อม รอครบ 90 วินาที", INSUFFICIENT_FUNDS = "เหรียญไม่พอ", NO_EGG = "ยังไม่มีไข่", CAPACITY_FULL = "ช่องเก็บเต็ม", NOTHING_TO_CLAIM = "ไม่มีไข่รอรับ", RATE_LIMITED = "ทำรายการเร็วเกินไป กรุณารอสักครู่", STALE_PROFILE = "ข้อมูลเปลี่ยนแล้ว กรุณาลองใหม่", INTENT_BUSY = "มีรายการรอยืนยัน รอสักครู่แล้วลองใหม่"}
remotes.GameResponse.OnClientEvent:Connect(function(response)
    local slot = pending[response.requestId]
    if slot then slot.response = response end
end)
local function request(action, args)
    local id = HttpService:GenerateGUID(false)
    local slot = {}
    pending[id] = slot
    local envelope = {apiVersion = 1, requestId = id, action = action, args = args or {}}
    -- Retransmit the identical request ID if transport loses the response.
    while not slot.response do
        remotes.GameRequest:FireServer(envelope)
        local untilAt = os.clock() + 5
        repeat task.wait(0.05) until slot.response or os.clock() >= untilAt
        if not slot.response then notice.Text = "กำลังตรวจสถานะ กรุณารอ…" end
    end
    pending[id] = nil
    return slot.response
end
local collection = Instance.new("ScrollingFrame")
collection.Size = UDim2.new(1, 0, 0, 220)
collection.BackgroundTransparency = 1
collection.AutomaticCanvasSize = Enum.AutomaticSize.Y
collection.CanvasSize = UDim2.new()
local list = Instance.new("UIListLayout")
list.Padding = UDim.new(0, 4)
list.Parent = collection
local mutate
local function apply(view)
    if presentingHatch then
        if not deferredView or view.profileVersion >= deferredView.profileVersion then deferredView = view end
        return
    end
    if profile and view.profileVersion < profile.profileVersion then return end
    profile = view
    balance.Text = string.format("เหรียญ %d  |  ไข่ %d/%d  |  ตัวละคร %d/%d", view.coinBalance, view.basicEggCount, view.capacity.eggs, #view.creatures, view.capacity.creatures)
    for _, child in ipairs(collection:GetChildren()) do if child:IsA("TextButton") then child:Destroy() end end
    for _, creature in ipairs(view.creatures) do
        local row = Instance.new("TextButton")
        row.Size = UDim2.new(1, -8, 0, 48)
        row.TextSize = 15
        row.Text = string.format("%s • Lv.%d • %d ดาว\n%s", creature.definitionId, creature.level, creature.stars, if creature.isLocked then "ล็อกอยู่ — คลิกเพื่อปลดล็อก" else "คลิกเพื่อล็อกตัวละคร")
        row.BackgroundColor3 = Color3.fromRGB(55, 75, 94)
        row.TextColor3 = Color3.new(1, 1, 1)
        row.Parent = collection
        row.Activated:Connect(function() mutate("Creature.SetLocked", {creatureId = creature.instanceId, locked = not creature.isLocked}) end)
    end
end
local function refresh()
    local response = request("Profile.Get")
    if response.status == "ok" then apply(response.data) end
    return response
end
remotes.GamePush.OnClientEvent:Connect(function(push)
    if push.event == "ProfileChanged" then apply(push.data) end
    if push.event == "WorldChanged" then worldLabel.Text = push.data.timeOfDay .. " • " .. push.data.weather end
end)
mutate = function(kind, params)
    if busy or not profile then return end
    busy = true
    presentingHatch = kind == "Egg.Hatch"
    notice.Text = "กำลังบันทึก…"
    local response = request("Operation.Create", {kind = kind, params = params})
    if response.status == "ok" then
        local operationId = response.data.operationId
        response = request("Operation.Execute", {operationId = operationId})
        while response.status == "pending" or response.status == "prepared" do
            notice.Text = "กำลังตรวจสถานะรายการ…"
            task.wait(1)
            response = request("Operation.Get", {operationId = operationId})
            if response.status == "prepared" then response = request("Operation.Execute", {operationId = operationId}) end
        end
    end
    if response.status == "committed" then
        if kind == "Egg.Hatch" then
            notice.Text = "กำลังฟักไข่…"
            task.wait(3)
            notice.Text = "ฟักสำเร็จ! ได้ " .. response.data.result.creature.definitionId
        else notice.Text = "สำเร็จ" end
    else
        local code = response.error and response.error.code or "PROFILE_NOT_READY"
        notice.Text = errors[code] or ("ยังทำรายการไม่ได้: " .. code)
    end
    presentingHatch = false
    if deferredView then apply(deferredView); deferredView = nil end
    task.wait(1)
    refresh()
    busy = false
end
local nodeButtons = {}
local function button(text, kind, params)
    local item = Instance.new("TextButton")
    item.Size = UDim2.new(1, 0, 0, 34)
    item.Text = text
    item.TextSize = 16
    item.BackgroundColor3 = Color3.fromRGB(48, 113, 105)
    item.TextColor3 = Color3.new(1, 1, 1)
    item.Parent = panel
    item.Activated:Connect(function() mutate(kind, params) end)
    return item
end
button("ฟักไข่", "Egg.Hatch", {})
button("ซื้อไข่ • 40 เหรียญ", "Egg.Buy", {quantity = 1})
for _, id in ipairs({"N01", "N02", "N03"}) do nodeButtons[id] = button("เก็บไข่ " .. id, "Egg.Collect", {nodeId = id}) end
local claimButton = button("รับไข่รางวัลค้าง", "Reward.ClaimPendingEggs", {})
label("คอลเลกชัน • คลิกตัวละครเพื่อล็อก/ปลดล็อก")
collection.Parent = panel
task.spawn(function()
    repeat
        local result = refresh()
        if result.status == "ok" then break end
        task.wait(1)
    until false
end)

task.spawn(function()
    local world = request("World.Get")
    if world.status == "ok" then worldLabel.Text = world.data.timeOfDay .. " • " .. world.data.weather end
    while task.wait(1) do
        if profile then
            claimButton.Text = "รับไข่รางวัลค้าง • " .. profile.pendingEggRewards
            for _, node in ipairs(profile.nodes) do
                local remaining = math.max(0, node.nextAvailableAt - math.floor(workspace:GetServerTimeNow()))
                nodeButtons[node.nodeId].Text = "เก็บไข่ " .. node.nodeId .. (if remaining > 0 then " • รอ " .. remaining .. " วินาที" else " • พร้อม")
            end
        end
    end
end)
