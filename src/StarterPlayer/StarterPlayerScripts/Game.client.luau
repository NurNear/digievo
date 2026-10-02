local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local presentation = game:GetService("ReplicatedStorage"):WaitForChild("Presentation")
local Guide = require(presentation:WaitForChild("Guide"))
local PetModel = require(presentation:WaitForChild("PetModel"))
local BattleFeed = require(presentation:WaitForChild("BattleFeed"))
local battleFeed = BattleFeed.new()
local BattleStage = require(script.Parent:WaitForChild("BattleStage"))
local HttpService = game:GetService("HttpService")
local remotes = game:GetService("ReplicatedStorage"):WaitForChild("GameRemotes")
local gui = Instance.new("ScreenGui")
gui.Name = "Digievo"
gui.ResetOnSpawn = false
gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
local panel = Instance.new("ScrollingFrame")
panel.AutomaticCanvasSize = Enum.AutomaticSize.Y
panel.CanvasSize = UDim2.new()
panel.Size = UDim2.new(1, -24, 1, -64)
local sizeLimit = Instance.new("UISizeConstraint")
sizeLimit.MaxSize = Vector2.new(440, 10000)
sizeLimit.Parent = panel
panel.ScrollBarThickness = 4
panel.BorderSizePixel = 0
local padding = Instance.new("UIPadding")
padding.PaddingLeft = UDim.new(0, 12)
padding.PaddingRight = UDim.new(0, 12)
padding.PaddingTop = UDim.new(0, 10)
padding.PaddingBottom = UDim.new(0, 12)
padding.Parent = panel
panel.Position = UDim2.fromOffset(12, 56)
panel.BackgroundColor3 = Color3.fromRGB(24, 34, 47)
panel.Parent = gui
local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 7)
layout.Parent = panel
layout.SortOrder = Enum.SortOrder.LayoutOrder
local section, currentTab = "header", "pets"
local sections, tabButtons = {}, {}
local sequence = 0
local onTabChanged
local function register(item)
    sequence += 1
    item.LayoutOrder = sequence
    sections[item] = section
    item.Visible = section == "header" or section == currentTab
    return item
end
local function switchTab(tab)
    currentTab = tab
    for item, group in pairs(sections) do item.Visible = group == "header" or group == tab end
    for key, item in pairs(tabButtons) do
        item.BackgroundColor3 = if key == tab then Color3.fromRGB(48, 113, 105) else Color3.fromRGB(45, 57, 74)
    end
    panel.CanvasPosition = Vector2.zero
    if onTabChanged then onTabChanged(tab) end
end
local function styleButton(item)
    item.BorderSizePixel = 0
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = item
end
local function label(text, height)
    local item = Instance.new("TextLabel")
    item.Size = UDim2.new(1, 0, 0, height or 32)
    item.BackgroundTransparency = 1
    item.TextColor3 = Color3.new(1, 1, 1)
    item.TextSize = 16
    item.TextWrapped = true
    item.Text = text
    item.Parent = panel
    register(item)
    return item
end
label("DIGIEVO • WORLD AUTO v2", 32)
label("WASD เพื่อเดิน • โหมดทดลอง: หยุด Play แล้วข้อมูลรีเซ็ต", 36)
local balance = label("กำลังโหลดข้อมูล…")
local worldLabel = label("กำลังอ่านสภาพโลก…", 28)
local notice = label("เริ่มจากฟักไข่ฟรีในแท็บไข่", 44)
local guideButton = Instance.new("TextButton")
guideButton.Size = UDim2.new(1, 0, 0, 54)
guideButton.TextSize = 15
guideButton.TextWrapped = true
guideButton.TextColor3 = Color3.new(1, 1, 1)
guideButton.BackgroundColor3 = Color3.fromRGB(51, 88, 125)
guideButton.Parent = panel
styleButton(guideButton)
register(guideButton)
local toggle = Instance.new("TextButton")
toggle.Size = UDim2.fromOffset(190, 40)
toggle.Position = UDim2.fromOffset(12, 8)
toggle.TextSize = 16
toggle.TextColor3 = Color3.new(1, 1, 1)
toggle.BackgroundColor3 = Color3.fromRGB(24, 34, 47)
toggle.Parent = gui
styleButton(toggle)
local function showPanel(visible)
    panel.Visible = visible
    toggle.Text = if visible then "B • WORLD AUTO v2 ▾" else "B • WORLD AUTO v2 ▸"
end
showPanel(true)
toggle.Activated:Connect(function() showPanel(not panel.Visible) end)
local tabs = Instance.new("Frame")
tabs.Size = UDim2.new(1, 0, 0, 42)
tabs.BackgroundTransparency = 1
tabs.Parent = panel
register(tabs)
for index, entry in ipairs({{"pets", "สัตว์เลี้ยง"}, {"eggs", "ไข่"}, {"mix", "ผสม"}, {"battle", "ต่อสู้"}}) do
    local tab = Instance.new("TextButton")
    tab.Size = UDim2.new(0.25, -4, 1, 0)
    tab.Position = UDim2.fromScale((index - 1) * 0.25, 0)
    tab.Text, tab.TextSize = entry[2], 15
    tab.TextColor3 = Color3.new(1, 1, 1)
    tab.Parent = tabs
    styleButton(tab)
    tabButtons[entry[1]] = tab
    tab.Activated:Connect(function() switchTab(entry[1]) end)
end
local pending, profile, busy = {}, nil, false
local presentingHatch, deferredView = false, nil
local battle, battleRequest, renderBattle
local battleLabel, combatLog, skillButtons
local battleBusy = false
local stage
local updateBattleControls
local castSkill
local function updateGuide()
    local nextStep = Guide.next(profile, battle, busy or battleBusy)
    guideButton.Text = nextStep.text .. (if nextStep.tab then "  ›" else "")
    guideButton.Active = nextStep.tab ~= nil
    guideButton.AutoButtonColor = guideButton.Active
end
guideButton.Activated:Connect(function()
    local nextStep = Guide.next(profile, battle, busy or battleBusy)
    if nextStep.tab then switchTab(nextStep.tab) end
end)
local skillNames = {S01 = "ตะปบ", S02 = "กระแทกกระดอง", U01 = "เจาะเกราะ", U02 = "โจมตีหนัก", F01 = "เปลวไฟ", W01 = "คลื่นคุ้มกัน"}
local errors = {EXPIRED_INTENT = "รายการหมดอายุ กรุณาดูโอกาสและยืนยันใหม่", STALE_PREVIEW = "ตัวอย่างหมดอายุหรือข้อมูลเปลี่ยน กรุณาดูโอกาสใหม่", CREATURE_LOCKED = "ปลดล็อกตัวละครก่อนผสม", CREATURE_NOT_FOUND = "ไม่พบตัวละครต้นทาง กรุณาเลือกใหม่", IN_BATTLE = "รอให้การต่อสู้จบก่อน", OUT_OF_RANGE = "เดินเข้าใกล้จุดเก็บไข่หรือสนามฝึก (ไม่เกิน 12 studs)", NODE_UNAVAILABLE = "จุดนี้ยังไม่พร้อม รอครบ 90 วินาที", INSUFFICIENT_FUNDS = "เหรียญไม่พอ", NO_EGG = "ยังไม่มีไข่", CAPACITY_FULL = "ช่องเก็บเต็ม", NOTHING_TO_CLAIM = "ไม่มีไข่รอรับ", RATE_LIMITED = "ทำรายการเร็วเกินไป กรุณารอสักครู่", STALE_PROFILE = "ข้อมูลเปลี่ยนแล้ว กรุณาลองใหม่", INTENT_BUSY = "มีรายการรอยืนยัน รอสักครู่แล้วลองใหม่"}
remotes.GameResponse.OnClientEvent:Connect(function(response)
    local slot = pending[response.requestId]
    if slot then slot.response = response end
end)
errors.PROFILE_NOT_READY = "ยังโหลดข้อมูลไม่สำเร็จ • กำลังรอตรวจสถานะ"
errors.PROFILE_INVALID = "ข้อมูลมีปัญหา • หยุดรายการไว้เพื่อตรวจสอบ"
errors.STORAGE_UNAVAILABLE = "ยังยืนยันการบันทึกไม่ได้ • กรุณารอ"
errors.SESSION_LOST = "เซสชันเปลี่ยนแล้ว • กรุณาเข้าเกมใหม่"
errors.STALE_BATTLE = "ข้อมูลการต่อสู้เปลี่ยนแล้ว กำลังอ่านสถานะใหม่"
errors.SKILL_LOCKED = "สกิลนี้ยังไม่ปลดล็อก"
errors.SKILL_COOLDOWN = "สกิลยังไม่พร้อม • รอตามเวลาบนปุ่ม"
errors.BATTLE_ENDED = "แมตช์จบแล้ว"
errors.OPERATION_BUSY = "มีรายการค้างอยู่ รอให้เสร็จหรือหมดอายุก่อนเข้าสนาม"
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
collection.ScrollBarThickness = 4
local list = Instance.new("UIListLayout")
list.Padding = UDim.new(0, 4)
list.Parent = collection
local mutate
local selected, preview = {}, nil
local selectionLabel, previewText, confirmButton
local resultCard, resultTitle, resultDetail, resultArt
local emptyCollection
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
    updateGuide()
    if emptyCollection then emptyCollection.Visible = #view.creatures == 0 and (currentTab == "pets" or currentTab == "mix") end
    balance.Text = string.format("เหรียญ %d  |  ไข่ %d/%d  |  ตัวละคร %d/%d", view.coinBalance, view.basicEggCount, view.capacity.eggs, #view.creatures, view.capacity.creatures)
    for _, child in ipairs(collection:GetChildren()) do if child:IsA("Frame") then child:Destroy() end end
    for _, creature in ipairs(view.creatures) do
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, -8, 0, 92)
        row.BackgroundTransparency = 1
        row.Parent = collection
        local portrait = Instance.new("Frame")
        portrait.Size = UDim2.fromOffset(68, 64)
        portrait.BackgroundTransparency = 1
        portrait.Parent = row
        PetModel.preview(portrait, creature.definitionId)
        local choose = Instance.new("TextButton")
        choose.Size = UDim2.new(1, -140, 0, 64)
        choose.Position = UDim2.fromOffset(70, 0)
        choose.TextSize = 14
        choose.TextWrapped = true
        local picked = table.find(selected, creature.instanceId) ~= nil
        choose.Text = string.format("%s%s • Lv.%d • %d ดาว\n%s", if picked then "✓ " else "", BattleStage.name(creature.definitionId), creature.level, creature.stars, if currentTab == "mix" then "กดเลือกเป็นต้นทางผสม" else "XP " .. creature.totalXP)
        choose.BackgroundColor3 = if picked then Color3.fromRGB(48, 113, 105) else Color3.fromRGB(55, 75, 94)
        choose.TextColor3 = Color3.new(1, 1, 1)
        choose.Parent = row
        styleButton(choose)
        choose.Activated:Connect(function()
            if busy or currentTab ~= "mix" then return end
            if creature.isLocked then notice.Text = errors.CREATURE_LOCKED; return end
            local index = table.find(selected, creature.instanceId)
            if index then table.remove(selected, index)
            elseif #selected < 2 then table.insert(selected, creature.instanceId)
            else notice.Text = "เลือกครบ 2 ตัวแล้ว กดตัวเดิมเพื่อยกเลิก"; return end
            clearPreview()
            apply(profile)
        end)
        local lock = Instance.new("TextButton")
        lock.Size = UDim2.fromOffset(62, 44)
        lock.Position = UDim2.new(1, -66, 0, 10)
        lock.Text = if creature.isLocked then "ปลดล็อก" else "ล็อก"
        lock.TextSize = 14
        lock.Parent = row
        styleButton(lock)
        lock.Activated:Connect(function() mutate("Creature.SetLocked", {creatureId = creature.instanceId, locked = not creature.isLocked}) end)
        local train = Instance.new("TextButton")
        train.Size = UDim2.new(1, 0, 0, 30)
        train.Position = UDim2.fromOffset(0, 132)
        train.TextSize = 14
        train.Text = "ฝึกด้วย " .. BattleStage.name(creature.definitionId) .. " • XP " .. creature.totalXP
        train.BackgroundColor3 = Color3.fromRGB(65, 99, 155)
        train.TextColor3 = Color3.new(1, 1, 1)
        train.Parent = row
        train.Visible = currentTab ~= "mix"
        row.Size = UDim2.new(1, -8, 0, if currentTab == "mix" then 70 else 176)
        train.Size = UDim2.new(1, 0, 0, 40)
        styleButton(train)
        local details = Instance.new("TextLabel")
        details.Size = UDim2.new(1, -4, 0, 62)
        details.Position = UDim2.fromOffset(0, 66)
        details.BackgroundTransparency = 1
        details.TextColor3 = Color3.fromRGB(197, 216, 231)
        details.TextSize, details.TextWrapped = 13, true
        details.Visible = currentTab ~= "mix"
        local skills = {}
        for _, slot in ipairs(creature.slots) do
            if slot.skillId then
                table.insert(skills, (skillNames[slot.skillId] or slot.skillId) .. (if slot.unlocked then "" else " (เลเวล 5)"))
            end
        end
        details.Text = string.format("HP %d • โจมตี %d • ป้องกัน %d • เร็ว %d\n%s", creature.stats.hp, creature.stats.atk, creature.stats.def, creature.stats.spd, table.concat(skills, " • "))
        details.Parent = row
        train.Activated:Connect(function()
            battleRequest("Battle.Start", {creatureId = creature.instanceId, encounterId = "TRAINING"})
        end)
    end
end
local function refresh()
    local response = request("Profile.Get")
    if response.status == "ok" then apply(response.data)
    else notice.Text = errors[response.error and response.error.code or "PROFILE_NOT_READY"] or errors.PROFILE_NOT_READY end
    return response
end
remotes.GamePush.OnClientEvent:Connect(function(push)
    if push.event == "ProfileChanged" then apply(push.data) end
    if push.event == "BattleChanged" and renderBattle then
        renderBattle(push.data)
    end
    if push.event == "WorldChanged" then
        worldLabel.Text = Guide.world(push.data)
        if preview and preview.world.phaseId ~= push.data.phaseId then clearPreview() end
    end
end)
mutate = function(kind, params)
    if busy or battleBusy or not profile then return end
    if battle and battle.status ~= "ended" then notice.Text = errors.IN_BATTLE; return end
    busy = true
    updateGuide()
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
            notice.Text = "ฟักสำเร็จ! ได้ " .. BattleStage.name(response.data.result.creature.definitionId)
        elseif kind == "Mix.Commit" then
            notice.Text = "ผสมสำเร็จ! ได้ " .. BattleStage.name(response.data.result.creature.definitionId)
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
    if response.status == "committed" and response.data.result.creature and (kind == "Egg.Hatch" or kind == "Mix.Commit") then
        local creature = response.data.result.creature
        for _, child in ipairs(resultArt:GetChildren()) do child:Destroy() end
        PetModel.preview(resultArt, creature.definitionId)
        resultTitle.Text = (if kind == "Egg.Hatch" then "ฟักสำเร็จ! " else "ผสมสำเร็จ! ") .. BattleStage.name(creature.definitionId)
        local skills = {}
        for _, slot in ipairs(creature.slots) do
            if slot.skillId then table.insert(skills, (skillNames[slot.skillId] or slot.skillId) .. (if slot.unlocked then "" else " • ปลดล็อกเลเวล 5")) end
        end
        resultDetail.Text = "เลเวล " .. creature.level .. " • " .. creature.stars .. " ดาว\n" .. table.concat(skills, " / ")
        resultCard:SetAttribute("HasResult", true)
        switchTab("pets")
    end
    updateGuide()
end
local nodeButtons = {}
local function button(text, kind, params, callback)
    local item = Instance.new("TextButton")
    item.Size = UDim2.new(1, 0, 0, 44)
    item.Text = text
    item.TextSize = 16
    item.BackgroundColor3 = Color3.fromRGB(48, 113, 105)
    item.TextColor3 = Color3.new(1, 1, 1)
    item.Parent = panel
    register(item)
    styleButton(item)
    item.Activated:Connect(function() if callback then callback() else mutate(kind, params) end end)
    return item
end
section = "eggs"
label("เก็บไข่ → ฟัก → เลือกสัตว์เลี้ยงไปฝึก", 36)
button("ฟักไข่", "Egg.Hatch", {})
button("ซื้อไข่ • 40 เหรียญ", "Egg.Buy", {quantity = 1})
for _, id in ipairs({"N01", "N02", "N03"}) do nodeButtons[id] = button("เก็บไข่ " .. id, "Egg.Collect", {nodeId = id}) end
local claimButton = button("รับไข่รางวัลค้าง", "Reward.ClaimPendingEggs", {})
section = "battle"
label("สนามฝึก • เดินไปแท่นสีน้ำเงิน", 32)
stage = BattleStage.new()
label("สู้บนสนามจริง • โจมตีอัตโนมัติ\nปุ่มสกิลจะแสดงด้านล่างจอเมื่อเริ่มสู้", 56)
local battleHud = Instance.new("Frame")
battleHud.Name = "RealtimeSkills"
battleHud.AnchorPoint = Vector2.new(0.5, 1)
battleHud.Position = UDim2.new(0.5, 0, 1, -16)
battleHud.Size = UDim2.new(1, -24, 0, 150)
battleHud.BackgroundColor3 = Color3.fromRGB(24, 34, 47)
battleHud.BackgroundTransparency = 0.08
battleHud.Visible = false
battleHud.Parent = gui
local hudLimit = Instance.new("UISizeConstraint")
hudLimit.MaxSize = Vector2.new(620, 150)
hudLimit.Parent = battleHud
local hudCorner = Instance.new("UICorner")
hudCorner.CornerRadius = UDim.new(0, 12)
hudCorner.Parent = battleHud
local function hudLabel(text, y, height)
    local item = Instance.new("TextLabel")
    item.Position, item.Size = UDim2.fromOffset(12, y), UDim2.new(1, -24, 0, height)
    item.BackgroundTransparency, item.TextSize, item.TextWrapped = 1, 15, true
    item.TextColor3, item.Text = Color3.new(1, 1, 1), text
    item.Parent = battleHud
    return item
end
battleLabel = hudLabel("REALTIME • โจมตีอัตโนมัติ", 6, 26)
battleLabel.Size = UDim2.new(1, -154, 0, 26)
combatLog = hudLabel("กด 1–3 หรือคลิกสกิลเพื่อใช้ทันที • คูลดาวน์เป็นวินาที", 33, 30)
local cooldownBars = {}
local hudGeneration = 0
castSkill = function(index)
    if busy or battleBusy or not battle or battle.status ~= "active" then return end
    local skill = battle.player.skills[index]
    if not skill then return end
    if BattleFeed.remaining(skill, workspace:GetServerTimeNow()) > 0 then
        notice.Text = "สกิลกำลังคูลดาวน์"; return
    end
    battleRequest("Battle.Action", {battleId = battle.battleId, expectedRevision = battle.revision, command = "SKILL", skillId = skill.skillId})
end
skillButtons = {}
for index = 1, 3 do
    local item = Instance.new("TextButton")
    item.Position = UDim2.new((index - 1) / 3, 8, 0, 74)
    item.Size = UDim2.new(1 / 3, -16, 0, 56)
    item.TextSize, item.TextWrapped = 16, true
    item.TextColor3 = Color3.new(1, 1, 1)
    item.Parent = battleHud
    styleButton(item)
    item.Activated:Connect(function() castSkill(index) end)
    skillButtons[index] = item
    local track = Instance.new("Frame")
    track.Size, track.Position = UDim2.new(1, -12, 0, 4), UDim2.new(0, 6, 1, -7)
    track.BackgroundColor3, track.BorderSizePixel = Color3.fromRGB(40, 48, 60), 0
    track.Parent = item
    local fill = Instance.new("Frame")
    fill.Size, fill.BorderSizePixel = UDim2.fromScale(1, 1), 0
    fill.BackgroundColor3 = Color3.fromRGB(112, 223, 183)
    fill.Parent = track
    cooldownBars[index] = fill
end
local forfeitButton = Instance.new("TextButton")
forfeitButton.Position, forfeitButton.Size = UDim2.new(1, -128, 0, 7), UDim2.fromOffset(116, 30)
forfeitButton.Text, forfeitButton.TextSize = "ถอนตัว", 14
forfeitButton.TextColor3, forfeitButton.BackgroundColor3 = Color3.new(1, 1, 1), Color3.fromRGB(80, 62, 73)
forfeitButton.Parent = battleHud
styleButton(forfeitButton)
forfeitButton.Activated:Connect(function()
    if battle and battle.status == "active" then battleRequest("Battle.Forfeit", {battleId = battle.battleId, expectedRevision = battle.revision}) end
end)
updateBattleControls = function()
    local active = battle and battle.status == "active"
    forfeitButton.Visible = active == true
    forfeitButton.Active = active == true and not battleBusy
    forfeitButton.AutoButtonColor = forfeitButton.Active
    forfeitButton.TextTransparency = if forfeitButton.Active then 0 else 0.5
    for index, item in ipairs(skillButtons) do
        local skill = battle and battle.player.skills[index]
        item.Visible = active == true and skill ~= nil
        if skill then
            local remaining = BattleFeed.remaining(skill, workspace:GetServerTimeNow())
            cooldownBars[index].Size = UDim2.fromScale(1 - math.clamp(remaining / math.max(0.001, skill.cooldownSeconds), 0, 1), 1)
            item.Active = active == true and not busy and not battleBusy and remaining <= 0
            item.AutoButtonColor = item.Active
            item.TextTransparency = if item.Active then 0 else 0.5
            item.Text = index .. " • " .. (skillNames[skill.skillId] or skill.skillId)
                .. (if remaining > 0 then string.format(" • %.1f วิ", math.ceil(remaining * 10) / 10) elseif battleBusy then " • กำลังส่ง" else " • พร้อม")
            item.BackgroundColor3 = if remaining > 0 then Color3.fromRGB(75, 80, 90) else Color3.fromRGB(48, 113, 105)
        end
    end
end
onTabChanged = function(key)
    if key == "mix" or key == "pets" then
        sections[collection] = key
        collection.Visible = true
        if profile then apply(profile) end
    else collection.Visible = false end
    if emptyCollection then emptyCollection.Visible = profile ~= nil and #profile.creatures == 0 and (key == "pets" or key == "mix") end
    if resultCard then resultCard.Visible = key == "pets" and resultCard:GetAttribute("HasResult") == true end
    updateBattleControls()
end
renderBattle = function(view)
    local events = battleFeed.accept(view)
    if not events then return end
    local newBattle = not battle or battle.battleId ~= view.battleId
    local finished = view.status == "ended" and (not battle or battle.status ~= "ended")
    battle = view
    if newBattle then
        hudGeneration += 1
        battleHud.Visible = true
        showPanel(false)
        local prompt = workspace:FindFirstChild("TrainingArena")
        prompt = prompt and prompt:FindFirstChild("JourneyPrompt")
        if prompt then prompt.Enabled = false end
    end
    if finished then
        local generation = hudGeneration
        task.delay(3, function()
            if hudGeneration ~= generation then return end
            battleHud.Visible = false
            stage.release()
            local pad = workspace:FindFirstChild("TrainingArena")
            local prompt = pad and pad:FindFirstChild("JourneyPrompt")
            if prompt then prompt.Enabled = true end
            showPanel(true)
            switchTab("pets")
        end)
    end
    local status = if view.status == "resolving" then "กำลังยืนยันรางวัล…" elseif view.status == "active" then "ต่อสู้เรียลไทม์ • AUTO" elseif view.outcome == "win" then "ชนะ • บันทึกรางวัลแล้ว" elseif view.outcome == "loss" then "แพ้ • ลองใหม่ได้" else "ถอนตัวแล้ว"
    battleLabel.Text = status
    stage.play(view, events)
    if #events > 0 then
        local event = events[#events]
        combatLog.Text = (if event.actor == "player" then "คุณ" else "คู่ฝึก") .. " • " .. (skillNames[event.skillId] or "โจมตีปกติ") .. " • −" .. event.hpDamage .. " HP"
    end
    updateGuide()
    updateBattleControls()
end
battleRequest = function(action, args)
    if busy or battleBusy then return end
    battleBusy = true
    updateGuide()
    updateBattleControls()
    local response = request(action, args)
    if response.data and response.data.battle then
        if action == "Battle.Start" then
            showPanel(false)
        end
        updateBattleControls()
        renderBattle(response.data.battle)
    end
    if response.status == "rejected" then
        local code = response.error and response.error.code or "PROFILE_NOT_READY"
        notice.Text = errors[code] or code
        if action ~= "Battle.Get" then
            local snapshot = request("Battle.Get")
            if snapshot.data and snapshot.data.battle then renderBattle(snapshot.data.battle) end
        end
    elseif response.status == "pending" then notice.Text = "กำลังตรวจสถานะการต่อสู้หรือรางวัล…"
    elseif battle and battle.status == "ended" then
        refresh()
        notice.Text = if battle.outcome == "win" then "รับรางวัลแล้ว • ดู Level/ดาว/ไข่ในคอลเลกชัน" else "เริ่มแมตช์ใหม่ได้ด้วย HP เต็ม"
    else notice.Text = "โจมตีอัตโนมัติ • กดสกิลได้เมื่อพร้อม" end
    battleBusy = false
    updateGuide()
    updateBattleControls()
end
-- Display countdowns locally; only the server schedules attacks and accepts skills.
task.spawn(function()
    while task.wait(0.1) do updateBattleControls() end
end)
-- Read recovery snapshots with fresh request IDs; a cached pending response is not final.
task.spawn(function()
    while task.wait(1) do
        if battle and battle.status == "resolving" and not battleBusy and not busy then battleRequest("Battle.Get", {}) end
    end
end)
section = "pets"
resultCard = Instance.new("Frame")
resultCard.Size = UDim2.new(1, 0, 0, 166)
resultCard.BackgroundColor3 = Color3.fromRGB(37, 71, 70)
resultCard.Parent = panel
register(resultCard)
resultArt = Instance.new("Frame")
resultArt.Size = UDim2.new(0.35, 0, 1, 0)
resultArt.BackgroundTransparency = 1
resultArt.Parent = resultCard
resultTitle = Instance.new("TextLabel")
resultTitle.Position, resultTitle.Size = UDim2.fromScale(0.35, 0.05), UDim2.fromScale(0.63, 0.4)
resultTitle.BackgroundTransparency, resultTitle.TextWrapped, resultTitle.TextSize = 1, true, 17
resultTitle.TextColor3 = Color3.new(1, 1, 1)
resultTitle.Parent = resultCard
resultDetail = resultTitle:Clone()
resultDetail.Position, resultDetail.Size = UDim2.fromScale(0.35, 0.45), UDim2.fromScale(0.63, 0.5)
resultDetail.TextSize = 14
resultDetail.Parent = resultCard
emptyCollection = label("ยังไม่มีสัตว์เลี้ยง • กดคำแนะนำด้านบนเพื่อฟักไข่ตัวแรก", 52)
label("สัตว์เลี้ยงของคุณ • เดินไปแท่นน้ำเงินแล้วกดฝึก", 42)
collection.Parent = panel
collection.Size = UDim2.new(1, 0, 0, 300)
register(collection)
section = "mix"
label("เลือกสัตว์เลี้ยง 2 ตัว • ดูโอกาสก่อนยืนยัน", 40)
selectionLabel = label("เลือกแล้ว 0/2 ตัว")
button("ดูโอกาสผสม", nil, nil, function()
    if busy or not profile then return end
    if #selected ~= 2 then notice.Text = "เลือกตัวละครที่ไม่ล็อก 2 ตัวก่อน"; return end
    busy = true
    updateGuide()
    clearPreview()
    local response = request("Mix.Preview", {parentIds = table.clone(selected)})
    if response.status == "ok" and response.data.profileVersion == profile.profileVersion then
        preview = response.data
        local lines = {"ใช้ต้นทางทั้ง 2 ตัว + " .. preview.cost .. " เหรียญ → ลูก 1 ตัว", "ต้นทางจะถูกใช้ไป • ลูกเริ่ม Level 1", "โลก: " .. Guide.world(preview.world), "โอกาสระดับความหายาก:"}
        for _, rarity in ipairs(preview.rarityProbabilities) do
            table.insert(lines, string.format("%s %.2f%%", ({Common = "ทั่วไป", Uncommon = "ไม่ธรรมดา", Rare = "หายาก", Epic = "พิเศษ"})[rarity.rarity] or rarity.rarity, rarity.probability * 100))
        end
        table.insert(lines, "ผลลัพธ์ที่เป็นไปได้ (ดาว/สกิลเป็นโอกาสเมื่อได้ตัวนั้น):")
        for _, candidate in ipairs(preview.candidates) do
            local stars, skills = {}, {}
            for _, outcome in ipairs(candidate.starsOutcomes) do table.insert(stars, string.format("%d ดาว %.1f%%", outcome.stars, outcome.probability * 100)) end
            for _, outcome in ipairs(candidate.inheritedOutcomes) do table.insert(skills, string.format("%s %.1f%%", skillNames[outcome.skillId] or "ไม่มีสกิลสืบทอด", outcome.probability * 100)) end
            table.insert(lines, string.format("\n%s: %.2f%%\n%s%s\n%s", BattleStage.name(candidate.definitionId), candidate.probability * 100, table.concat(stars, ", "), if candidate.resetPotential then " • รีเซ็ตดาว" else "", table.concat(skills, ", ")))
        end
        previewText.Text = table.concat(lines, "\n")
        confirmButton.Text = "ยืนยันใช้ 2 ตัว + " .. preview.cost .. " เหรียญ"
        notice.Text = "ตรวจโอกาสและการสืบทอดก่อนยืนยัน"
    else
        local code = response.error and response.error.code or "STALE_PREVIEW"
        notice.Text = errors[code] or code
    end
    busy = false
    updateGuide()
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
switchTab("pets")
updateBattleControls()
updateGuide()
UserInputService.InputBegan:Connect(function(input, processed)
    if processed or UserInputService:GetFocusedTextBox() then return end
    if input.KeyCode == Enum.KeyCode.B then showPanel(not panel.Visible); return end
    if not battleHud.Visible or busy or not battle or battle.status ~= "active" then return end
    local index = ({[Enum.KeyCode.One] = 1, [Enum.KeyCode.Two] = 2, [Enum.KeyCode.Three] = 3})[input.KeyCode]
    if index then castSkill(index) end
end)
local function bindPrompt(item)
    if not item:IsA("ProximityPrompt") or item.Name ~= "JourneyPrompt" then return end
    item.Triggered:Connect(function()
        if busy or battleBusy then return end
        showPanel(true)
        if item.Parent.Name == "TrainingArena" then
            switchTab(if battle and battle.status ~= "ended" then "battle" else "pets")
            notice.Text = "เลือกปุ่มฝึกใต้สัตว์เลี้ยงที่ต้องการ"
        else
            switchTab("eggs")
            mutate("Egg.Collect", {nodeId = item.Parent.Name})
        end
    end)
end
for _, item in ipairs(workspace:GetDescendants()) do bindPrompt(item) end
workspace.DescendantAdded:Connect(bindPrompt)
task.spawn(function()
    repeat
        local result = refresh()
        if result.status == "ok" then break end
        task.wait(1)
    until false
end)

task.spawn(function()
    local world = request("World.Get")
    if world.status == "ok" then worldLabel.Text = Guide.world(world.data) end
    while task.wait(1) do
        if preview and workspace:GetServerTimeNow() >= preview.expiresAt then clearPreview() end
        if profile then
            claimButton.Text = "รับไข่รางวัลค้าง • " .. profile.pendingEggRewards
            updateGuide()
            for _, node in ipairs(profile.nodes) do
                local remaining = math.max(0, node.nextAvailableAt - math.floor(workspace:GetServerTimeNow()))
                nodeButtons[node.nodeId].Text = "เก็บไข่ " .. node.nodeId .. (if remaining > 0 then " • รอ " .. remaining .. " วินาที" else " • พร้อม")
            end
        end
    end
end)
