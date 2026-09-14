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
local errors = {EXPIRED_INTENT = "รายการหมดอายุ กรุณาดูโอกาสและยืนยันใหม่", STALE_PREVIEW = "ตัวอย่างหมดอายุหรือข้อมูลเปลี่ยน กรุณาดูโอกาสใหม่", CREATURE_LOCKED = "ปลดล็อกตัวละครก่อนผสม", CREATURE_NOT_FOUND = "ไม่พบตัวละครต้นทาง กรุณาเลือกใหม่", IN_BATTLE = "รอให้การต่อสู้จบก่อน", OUT_OF_RANGE = "เดินเข้าใกล้จุดเก็บไข่ (ไม่เกิน 12 studs)", NODE_UNAVAILABLE = "จุดนี้ยังไม่พร้อม รอครบ 90 วินาที", INSUFFICIENT_FUNDS = "เหรียญไม่พอ", NO_EGG = "ยังไม่มีไข่", CAPACITY_FULL = "ช่องเก็บเต็ม", NOTHING_TO_CLAIM = "ไม่มีไข่รอรับ", RATE_LIMITED = "ทำรายการเร็วเกินไป กรุณารอสักครู่", STALE_PROFILE = "ข้อมูลเปลี่ยนแล้ว กรุณาลองใหม่", INTENT_BUSY = "มีรายการรอยืนยัน รอสักครู่แล้วลองใหม่"}
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
local selected, preview = {}, nil
local selectionLabel, previewText, confirmButton
local function clearPreview()
    preview = nil
    if previewText then previewText.Text = "เลือก 2 ตัวแล้วกดดูโอกาสก่อนยืนยัน" end
    if confirmButton then confirmButton.Text = "ยืนยันผสม (ดูโอกาสก่อน)" end
end
local function updateSelection()
    if selectionLabel then selectionLabel.Text = "เลือกแล้ว " .. #selected .. "/2 ตัว" end
end
local function apply(view)
    if presentingHatch then
        if not deferredView or view.profileVersion >= deferredView.profileVersion then deferredView = view end
        return
    end
    if profile and view.profileVersion < profile.profileVersion then return end
    if profile and view.profileVersion ~= profile.profileVersion then clearPreview() end
    local available = {}
    for _, creature in ipairs(view.creatures) do if not creature.isLocked then available[creature.instanceId] = true end end
    for index = #selected, 1, -1 do
        if not available[selected[index]] then table.remove(selected, index); clearPreview() end
    end
    updateSelection()
    profile = view
    balance.Text = string.format("เหรียญ %d  |  ไข่ %d/%d  |  ตัวละคร %d/%d", view.coinBalance, view.basicEggCount, view.capacity.eggs, #view.creatures, view.capacity.creatures)
    for _, child in ipairs(collection:GetChildren()) do if child:IsA("Frame") then child:Destroy() end end
    for _, creature in ipairs(view.creatures) do
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, -8, 0, 56)
        row.BackgroundTransparency = 1
        row.Parent = collection
        local choose = Instance.new("TextButton")
        choose.Size = UDim2.new(0.72, -4, 1, 0)
        choose.TextSize = 14
        choose.TextWrapped = true
        local picked = table.find(selected, creature.instanceId) ~= nil
        choose.Text = string.format("%s%s • Lv.%d • %d ดาว\nเลือกเป็นต้นทางผสม", if picked then "✓ " else "", creature.definitionId, creature.level, creature.stars)
        choose.BackgroundColor3 = if picked then Color3.fromRGB(48, 113, 105) else Color3.fromRGB(55, 75, 94)
        choose.TextColor3 = Color3.new(1, 1, 1)
        choose.Parent = row
        choose.Activated:Connect(function()
            if busy then return end
            if creature.isLocked then notice.Text = errors.CREATURE_LOCKED; return end
            local index = table.find(selected, creature.instanceId)
            if index then table.remove(selected, index)
            elseif #selected < 2 then table.insert(selected, creature.instanceId)
            else notice.Text = "เลือกครบ 2 ตัวแล้ว กดตัวเดิมเพื่อยกเลิก"; return end
            clearPreview()
            apply(profile)
        end)
        local lock = Instance.new("TextButton")
        lock.Size = UDim2.new(0.28, 0, 1, 0)
        lock.Position = UDim2.fromScale(0.72, 0)
        lock.Text = if creature.isLocked then "ปลดล็อก" else "ล็อก"
        lock.TextSize = 14
        lock.Parent = row
        lock.Activated:Connect(function() mutate("Creature.SetLocked", {creatureId = creature.instanceId, locked = not creature.isLocked}) end)
    end
end
local function refresh()
    local response = request("Profile.Get")
    if response.status == "ok" then apply(response.data) end
    return response
end
remotes.GamePush.OnClientEvent:Connect(function(push)
    if push.event == "ProfileChanged" then apply(push.data) end
    if push.event == "WorldChanged" then
        worldLabel.Text = push.data.timeOfDay .. " • " .. push.data.weather
        if preview and preview.world.phaseId ~= push.data.phaseId then clearPreview() end
    end
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
        elseif kind == "Mix.Commit" then
            notice.Text = "ผสมสำเร็จ! ได้ " .. response.data.result.creature.definitionId
            selected = {}; clearPreview(); updateSelection()
        else notice.Text = "สำเร็จ" end
    else
        local code = response.error and response.error.code or "PROFILE_NOT_READY"
        notice.Text = errors[code] or ("ยังทำรายการไม่ได้: " .. code)
    end
    if kind == "Mix.Commit" then clearPreview() end
    presentingHatch = false
    if deferredView then apply(deferredView); deferredView = nil end
    task.wait(1)
    refresh()
    busy = false
end
local nodeButtons = {}
local function button(text, kind, params, callback)
    local item = Instance.new("TextButton")
    item.Size = UDim2.new(1, 0, 0, 34)
    item.Text = text
    item.TextSize = 16
    item.BackgroundColor3 = Color3.fromRGB(48, 113, 105)
    item.TextColor3 = Color3.new(1, 1, 1)
    item.Parent = panel
    item.Activated:Connect(function() if callback then callback() else mutate(kind, params) end end)
    return item
end
button("ฟักไข่", "Egg.Hatch", {})
button("ซื้อไข่ • 40 เหรียญ", "Egg.Buy", {quantity = 1})
for _, id in ipairs({"N01", "N02", "N03"}) do nodeButtons[id] = button("เก็บไข่ " .. id, "Egg.Collect", {nodeId = id}) end
local claimButton = button("รับไข่รางวัลค้าง", "Reward.ClaimPendingEggs", {})
label("คอลเลกชัน • เลือกต้นทาง 2 ตัวเพื่อผสม")
collection.Parent = panel
selectionLabel = label("เลือกแล้ว 0/2 ตัว")
button("ดูโอกาสผสม", nil, nil, function()
    if busy or not profile then return end
    if #selected ~= 2 then notice.Text = "เลือกตัวละครที่ไม่ล็อก 2 ตัวก่อน"; return end
    busy = true
    clearPreview()
    local response = request("Mix.Preview", {parentIds = table.clone(selected)})
    if response.status == "ok" and response.data.profileVersion == profile.profileVersion then
        preview = response.data
        local lines = {"ใช้ต้นทางทั้ง 2 ตัว + " .. preview.cost .. " เหรียญ → ลูก 1 ตัว", "ต้นทางจะถูกใช้ไป • ลูกเริ่ม Level 1", "โลก: " .. preview.world.timeOfDay .. " / " .. preview.world.weather, "โอกาสระดับความหายาก:"}
        for _, rarity in ipairs(preview.rarityProbabilities) do
            table.insert(lines, string.format("%s %.2f%%", rarity.rarity, rarity.probability * 100))
        end
        table.insert(lines, "ผลลัพธ์ที่เป็นไปได้ (ดาว/สกิลเป็นโอกาสเมื่อได้ตัวนั้น):")
        for _, candidate in ipairs(preview.candidates) do
            local stars, skills = {}, {}
            for _, outcome in ipairs(candidate.starsOutcomes) do table.insert(stars, string.format("%d ดาว %.1f%%", outcome.stars, outcome.probability * 100)) end
            for _, outcome in ipairs(candidate.inheritedOutcomes) do table.insert(skills, string.format("%s %.1f%%", outcome.skillId or "ไม่มีสกิลสืบทอด", outcome.probability * 100)) end
            table.insert(lines, string.format("\n%s: %.2f%%\n%s%s\n%s", candidate.definitionId, candidate.probability * 100, table.concat(stars, ", "), if candidate.resetPotential then " • รีเซ็ตดาว" else "", table.concat(skills, ", ")))
        end
        previewText.Text = table.concat(lines, "\n")
        confirmButton.Text = "ยืนยันใช้ 2 ตัว + " .. preview.cost .. " เหรียญ"
        notice.Text = "ตรวจโอกาสและการสืบทอดก่อนยืนยัน"
    else
        local code = response.error and response.error.code or "STALE_PREVIEW"
        notice.Text = errors[code] or code
    end
    busy = false
end)
previewText = label("เลือก 2 ตัวแล้วกดดูโอกาสก่อนยืนยัน", 0)
previewText.AutomaticSize = Enum.AutomaticSize.Y
previewText.TextXAlignment = Enum.TextXAlignment.Left
confirmButton = button("ยืนยันผสม (ดูโอกาสก่อน)", nil, nil, function()
    if busy then return end
    if not preview or workspace:GetServerTimeNow() >= preview.expiresAt then
        clearPreview(); notice.Text = errors.STALE_PREVIEW; return
    end
    local token = preview.previewId
    clearPreview()
    mutate("Mix.Commit", {previewId = token})
end)
button("ยกเลิกการเลือกผสม", nil, nil, function()
    if busy then return end
    selected = {}; clearPreview(); updateSelection()
    if profile then apply(profile) end
end)
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
        if preview and workspace:GetServerTimeNow() >= preview.expiresAt then clearPreview() end
        if profile then
            claimButton.Text = "รับไข่รางวัลค้าง • " .. profile.pendingEggRewards
            for _, node in ipairs(profile.nodes) do
                local remaining = math.max(0, node.nextAvailableAt - math.floor(workspace:GetServerTimeNow()))
                nodeButtons[node.nodeId].Text = "เก็บไข่ " .. node.nodeId .. (if remaining > 0 then " • รอ " .. remaining .. " วินาที" else " • พร้อม")
            end
        end
    end
end)
