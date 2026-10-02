-- Pure presentation decisions: never authorizes or changes gameplay state.
local Guide = {}
local function step(id, tab, text)
    return {id = id, tab = tab, text = text}
end
function Guide.next(profile, battle, busy)
    if not profile then return step("loading", nil, "กำลังโหลดสัตว์เลี้ยงของคุณ…") end
    if busy or profile.unresolvedOperationId then return step("pending", nil, "กำลังตรวจผลรายการ • รอให้ยืนยันก่อนทำต่อ") end
    if battle and battle.status ~= "ended" then
        return step("battle", "battle", if battle.status == "resolving" then "กำลังยืนยันรางวัล…" else "กำลังต่อสู้อัตโนมัติ • กดสกิลเมื่อพร้อม")
    end
    local count, unlocked = #profile.creatures, 0
    for _, creature in ipairs(profile.creatures) do if not creature.isLocked then unlocked += 1 end end
    if profile.pendingEggRewards > 0 and profile.basicEggCount < profile.capacity.eggs then
        return step("claim", "eggs", "มีไข่รางวัลรอรับ • เปิดแท็บไข่เพื่อรับ")
    end
    if count >= profile.capacity.creatures then
        return if unlocked >= 2 and profile.coinBalance >= 20 then step("mix", "mix", "สัตว์เลี้ยงเต็ม • ผสม 2 ตัวเป็นลูก 1 ตัวเพื่อเพิ่มที่ว่าง")
            elseif unlocked < 2 then step("unlock", "pets", "สัตว์เลี้ยงเต็ม • ปลดล็อก 2 ตัวที่ต้องการผสม")
            else step("train", "pets", "ฝึกต่อสู้หาเหรียญ 20 เหรียญสำหรับผสม")
    end
    if count == 0 or count == 1 then
        if profile.basicEggCount > 0 then return step("hatch", "eggs", "มีไข่พร้อมฟัก • เปิดแท็บไข่แล้วกดฟัก") end
        return step("collect", "eggs", "เดินไปจุดไข่สีทองแล้วกด E • เก็บฟรีเพื่อนำมาฟัก")
    end
    if unlocked < 2 then return step("unlock", "pets", "ปลดล็อกสัตว์เลี้ยง 2 ตัวที่ต้องการใช้ผสม") end
    if profile.coinBalance < 20 then return step("train", "pets", "เดินไปสนามสีน้ำเงิน • ฝึกชนะเพื่อหาเหรียญผสม") end
    local trained, mixed = false, false
    for _, creature in ipairs(profile.creatures) do if creature.totalXP > 0 then trained = true end end
    for _, receipt in ipairs(profile.recentReceipts or {}) do if receipt.kind == "Mix.Commit" then mixed = true end end
    if mixed then return step("train", "pets", "ลองฝึกสัตว์เลี้ยงตัวใหม่ • เลเวล 5 ปลดล็อกสกิลเติบโต") end
    if not trained then return step("train", "pets", "พร้อมฝึกแล้ว • เดินไปสนามสีน้ำเงินแล้วเลือกสัตว์เลี้ยง") end
    return step("mix", "mix", "ลองผสม 2 ตัว • ดูโอกาสก่อนยืนยัน ใช้ 20 เหรียญ")
end
function Guide.world(world)
    local time = if world.timeOfDay == "Day" then "กลางวัน" else "กลางคืน"
    local weather = if world.weather == "Rain" then "ฝนตก" else "ฟ้าใส"
    return time .. " • " .. weather
end
return table.freeze(Guide)
