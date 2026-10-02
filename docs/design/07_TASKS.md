# Development Tasks — v1.0

ผู้ใช้สั่งเริ่ม I-00 และให้เดินต่อวันที่ 2026-09-12 แล้ว ปัจจุบันพัฒนาถึง I-07 รวม journey/งานภาพต้นแบบแบบทดสอบในเครื่อง (2026-10-02); CLI ผ่านแล้ว แต่ I-06/I-07 ยังรอ Studio Play/manual walkthrough และยังไม่มีการบันทึกออนไลน์. Scope/ข้อเปิด [PRD](01_PRD_REVIEW.md), ตัวเลข [Domain](06_DOMAIN_RULES.md), contracts [API](05_API_SPEC.md)

## I-00: เริ่มแล้ว 2026-09-12
- คำสั่งผู้ใช้เริ่ม I-00 ปิด O-05 และแทนสถานะ T-06 ที่ยังไม่อนุญาตในบันทึก Discovery เดิมด้านล่าง
- ยึด MVP baseline v1.0: พื้นที่เล็ก, catalog 8 ตัว, ไข่/ฟัก/คอลเลกชัน, ผสมพร้อม preview/inheritance, Level/Growth, PvE 1 ต่อ 1 (ปรับเป็น realtime auto + immediate skill cooldown วินาที ตามคำสั่ง 2026-10-02), World Condition และ profile/recovery
- คงงานนอก MVP และ O-01 ถึง O-04 ตาม PRD
- เริ่มพัฒนาจาก place ใหม่ในเครื่อง ไม่บันทึกทับ place จริง; เปิด Studio อย่างเดียวไม่ถือว่าสร้างหรือเชื่อม place แล้ว
- ก่อนทดสอบข้อมูลออนไลน์ ใช้ test experience แยกจาก production และบันทึก UniverseId/PlaceId ที่ตรวจสอบแล้ว ปัจจุบันยังไม่ได้สร้างหรือยืนยัน ID และยังไม่ publish
- namespace ข้อมูลทดสอบกำหนดเป็น `RobloxMVP_Test_v1`; ก่อนยืนยัน test experience ใช้ข้อมูลจำลองในหน่วยความจำและคง Studio API access ปิดไว้ แผนนี้ยังไม่ได้ตั้งค่าหรือทดสอบจริง
- I-02 ต้องตรวจ environment/UniverseId ก่อนเข้าถึงข้อมูลถาวร และปฏิเสธการเขียนเมื่อไม่รู้ environment; ห้ามใช้ข้อมูลจริงทดสอบ migration/reset
- ยืนยัน scope และแผนแล้ว แต่การสร้าง test experience และตรวจการแยกข้อมูลจริงยังค้างก่อนทดสอบออนไลน์ จึงยังไม่ปิด I-00 ว่าเสร็จครบ
- สร้าง `build/RobloxMVP_LocalTest.rbxlx` ผ่าน Rojo และเปิดใน Studio แล้ว; มีพื้น/จุดเกิดและชุดทดสอบ ไม่มีระบบบันทึกข้อมูล
- Rojo จำกัด localhost และ `servePlaceIds: [0]` ตรวจจาก API ของ server แล้ว; ตัวเริ่มทดสอบปฏิเสธเมื่อไม่ใช่ Studio หรือ GameId/PlaceId ไม่ใช่ 0 ผู้ใช้กด Connect/Play และตรวจ log พบ I-01 PASS แล้ว
- ไม่มีการสร้าง test experience บนคลาวด์หรือ publish; การแยก DataStore จริงยังต้องทำก่อน I-02 ทดสอบออนไลน์

## I-01: โมดูลกฎและการตรวจแบบ offline
- เพิ่ม `Catalog.luau`: definitions 8 ตัว, 6 สกิลและ BASIC, progression/economy/world config แบบ versioned และ immutable; epochUnix = 0 ตาม Data Model
- เพิ่ม `DomainRules.luau`: stats/XP/Potential, Growth และ inherited compatibility, phase ID รวม cycle, preview และการสุ่ม rarity ก่อน candidate, ไข่ 50/50, สูตร damage/shield/cooldown
- ตรวจด้วย Luau 0.738: 144 คู่ผสม/world cases, rarity marginal, สลับต้นทาง, skill/star independence จาก world, ขอบเขตสุ่ม/เวลา/XP, stats ทุก level/star, ตัวอย่าง damage และ config ผิด
- ชุดทดสอบอยู่ `tests/DomainRules.spec.luau`; รัน CLI ผ่าน `tests/run.luau` และบรรจุชุดเดียวกันใน ServerStorage สำหรับกด Play ใน Studio
- แก้การปัด stats ที่คลาดจาก floating point โดยใช้ percentage factors ก่อน floor ครั้งสุดท้าย; ตรวจเทียบ integer reference ครบทุก definition/level/star
- Luau analyzer และ Rojo build ผ่าน; รายละเอียดผลและข้อจำกัดดู [บันทึกทดสอบ](../testing/I-01_RESULTS.md)
- I-01 ส่วน pure rules เสร็จ: CLI และ Studio ผ่าน 14,322 assertions รวม 144 world cases; ผู้ใช้ยืนยัน live sync/Play และตรวจ log จริงแล้ว ไม่ใช่ผล playtest, persistence/fault, network/load หรือ FPS

## I-02: ระบบข้อมูลและ recovery (local implementation)
- เพิ่ม ProfileSchema/ProfileRepository/ProfileSession, MemoryStore สำหรับทดสอบ และ RobloxStore adapter ที่ตรวจ environment ก่อนเข้าถึง DataStore
- มี lease 120 วินาที ต่ออายุ 30 วินาที, fencing generation, intent 60 วินาที, prepare/commit, receipt 100 รายการ และ sequence ถาวร
- คำตอบบันทึกหายให้ pending และพักรายการใหม่จนตรวจ backend; schema ผิดไม่สร้าง default ทับ; ตรวจขนาดทั้ง prepare และผล commit ก่อนเขียน
- CLI ผ่าน 5,534 checks รวม fault จำลอง 400 รอบ; I-01 regression ยังผ่านทั้งหมด; Rojo 7.7.0 build ผ่าน
- LocalTest เปิดโปรไฟล์และแจกเงิน/ไข่เริ่มต้นแบบจำลองในหน่วยความจำเท่านั้น ปิด Play แล้วข้อมูลไม่คงอยู่
- I-02 ยังไม่ปิดครบด้าน online persistence: ต้องมี test experience/IDs และตรวจ DataStore จริงก่อน งานที่ทำและข้อจำกัดดู [รายงาน I-02](../testing/I-02_RESULTS.md)

## I-03: RPC boundary (local implementation)
- เพิ่ม server-side `RPC/Dispatcher.luau` และ `RPC/ViewModels.luau` สำหรับ envelope validation, response mapping, profile/world/receipt views, request replay และ rate limit เบื้องต้น
- `Operation.Create` รับเฉพาะ kind ที่ server register builder ไว้ และ `Operation.Execute` ใช้ fingerprint ที่ผูกไว้ฝั่ง server จาก create เดิม ไม่รับ params ใหม่จาก client
- เพิ่ม `tests/Rpc.spec.luau` และ map `RpcTests` เข้า ServerStorage; LocalTest จะรัน suite นี้ร่วมกับ I-01/I-02
- CLI ผ่าน I-03 จำนวน 44 checks; I-01 regression 14,322 assertions และ I-02 regression 5,534 checks/400 fault runs ยังผ่าน; luau-analyze และ Rojo build ผ่าน
- RemoteEvent/UI เชื่อมแล้วใน I-04 และ Studio log ยืนยัน I-01–I-05 ผ่าน; เพิ่ม routes ต่อสู้ใน I-06 ซึ่งยังรอ Studio Play
- รายละเอียดผลและข้อจำกัดดู [รายงาน I-03](../testing/I-03_RESULTS.md)

## I-04: ไข่และคอลเลกชัน (local implementation, 2026-09-14)
- เพิ่ม EggActions สำหรับ Collect/Buy/Hatch/SetLocked/ClaimPendingEggs พร้อมตรวจ params, ราคา, ช่องเต็ม, cooldown และระยะฝั่ง server
- เชื่อม GameRequest/GameResponse/GamePush กับ Player identity และเพิ่ม UI ภาษาไทย จุดสำรวจ 3 จุด ตัวนับ cooldown และคอลเลกชัน
- Create ตรวจแผนโดยไม่สุ่ม; Execute สุ่มครั้งเดียวก่อน prepare นอก callback และ recovery ใช้ผลเดิม
- ฟักแสดงผลหลัง committed และ presentation 3 วินาที; client ใช้ requestId เดิมเมื่อคำตอบหายและไม่ลด profileVersion ย้อนหลัง
- ผล CLI/build และข้อจำกัดดู [รายงาน I-04](../testing/I-04_RESULTS.md); Studio log ยืนยัน I-01–I-04 PASS แล้ว และผู้ใช้ยืนยันทดสอบฟัก/เดินเก็บไข่/ล็อก–ปลดล็อกครบโดยไม่ได้รายงานปัญหา; ยังไม่ทดสอบเครือข่ายหลาย client
- ใช้ memory backend เท่านั้น; ระบบผสมต่อยอดใน I-05 และระบบต่อสู้ใน I-06 ด้านล่าง

## I-05: Mix/preview (local implementation, 2026-09-14)
- เพิ่ม MixService และ route Mix.Preview พร้อม token ฝั่ง server อายุ 60 วินาที ผูกผู้เล่น/ต้นทาง/profileVersion/world phase
- แสดงโอกาส rarity, ตัวละคร, ดาว/การรีเซ็ตดาว และสกิลสืบทอด ก่อนยืนยันใช้ต้นทาง 2 ตัวและ 20 เหรียญ
- Create ไม่สุ่ม; Execute สุ่มครั้งเดียวและใช้ prepare/commit เดิม ตรวจ freshness ซ้ำใน callback ก่อน PREPARE; prepared/receipt มีสิทธิ์เหนือ expiry/phase ใหม่
- ตรวจ ownership/lock/เงิน/in-battle และยอมผสมเมื่อช่องตัวละครเต็ม เพราะจำนวนสุทธิลด 1
- เพิ่ม UI เลือกต้นทาง ปุ่มล็อกแยก ดูโอกาส ยืนยัน และยกเลิก; preview ถูกล้างเมื่อข้อมูลเปลี่ยน/โลกเปลี่ยน/หมดเวลา
- CLI และข้อจำกัดดู [รายงาน I-05](../testing/I-05_RESULTS.md); Studio log ยืนยัน I-01–I-05 PASS แล้ว (2026-09-14); ผู้ใช้ยืนยันทดลองผสมผ่าน UI แล้วโดยไม่ได้รายงานปัญหา; ยังไม่ยืนยัน manual expiry และ multi-client
- ระบบต่อสู้ต่อยอดใน I-06 ด้านล่าง; online DataStore ยังไม่เปิด

## I-06: Battle/progression (local implementation, 2026-09-16)
- เพิ่ม BattleService และ Battle.Start/Get/Action/Forfeit สำหรับ TRAINING 1 ต่อ 1; ศัตรู C01/C02 50/50, Level 1, 0 ดาว, HP เริ่ม 60% และใช้ BASIC
- server จัดลำดับ Speed; เสมอสุ่มครั้งแรกแล้วสลับผู้เริ่มแต่ละรอบ; ตรวจ revision/ownership/สกิล/cooldown และจบเมื่อ HP 0 ทันที
- Shield รับการโจมตีถัดไปหนึ่งครั้งหรือหมดเมื่อเริ่มเทิร์นเจ้าของ; Growth/Inherited ID ซ้ำแสดงเป็นท่าเดียว
- ชนะให้ 20 Coin/20 XP/หนึ่งชัยชนะ Potential; Growth ปลดล็อก Level 5, XP cap 480/Level 10, ดาว cap 5; ไข่ชัยชนะแรกแน่นอนแล้ว 20%, เต็มให้ pending
- reservation ฝั่ง repository กันรายการเศรษฐกิจระหว่างต่อสู้และระหว่างยืนยันรางวัล; reward operationId ผูก battleId และ PREPARE/COMMIT เก็บผลเดิมเมื่อ retry
- เพิ่มแท่นสนามฝึกสีน้ำเงินและปุ่มฝึกต่อ creature รวมตัวที่ล็อก; UI แสดง HP/Shield/รอบ/สกิล/ผลโจมตี/ถอนตัว และ poll รางวัล pending
- CLI ผ่าน 188 checks รวม flow ฟัก → สู้ → ปลดล็อก Growth → ผสม, callback ซ้ำ 100 ครั้ง, lost prepare/commit response, session takeover, outage เกิน intent expiry, overflow และกันรางวัลซ้ำ
- Regression I-01–I-05 ผ่าน; analyzer/syntax/Rojo build ผ่าน ตาม [รายงาน I-06](../testing/I-06_RESULTS.md)
- ยังไม่ยืนยัน Studio Play/UI/manual battle walkthrough, multi-client, DataStore จริงหรือ performance; I-06 ยังไม่ปิดครบด้านเล่นจริง งานถัดจากนั้นคือ I-07 รวม journey/งานภาพ

## I-07: รวม journey และงานภาพต้นแบบ (local implementation, 2026-10-02)
- UI 4 แท็บพร้อมคำแนะนำขั้นถัดไปตาม inventory/เหรียญ/lock/capacity/pending; กดคำแนะนำเพื่อเปิดแท็บที่เกี่ยวข้อง ไม่มีการบังคับลำดับเล่น
- รูปทรงกล่องฐานจิ้งจอก/เต่าแยกกันชัดเจน พร้อมสีและลายครบ 8 definitions ใช้โมเดลเดียวกันในคอลเลกชัน ผลฟัก/ผสม และสนามต่อสู้
- สนาม ViewportFrame แสดงพุ่งโจมตี แสงกระทบ HP/โล่ และผลแพ้ชนะตาม event ฝั่ง server; ระหว่างแสดงผลพักปุ่มและ snapshot push
- เพิ่มทางเดิน จุดกด E เก็บไข่/เลือกสัตว์เลี้ยงฝึก และแสงกลางวัน/กลางคืน/ฝนตาม world phase; B เปิดปิดเมนู, 1–3 ใช้สกิลทันทีเมื่อเปิดแท็บต่อสู้; โจมตีพื้นฐาน auto
- แสดงชื่อไทย สกิล/เงื่อนไขปลดล็อกเลเวล 5 stats และ result card หลัง committed เท่านั้น
- I-07 CLI ผ่าน 143 checks (guide transitions/boundaries/visual catalog), I-01–I-06 regression ผ่าน; compiler/analyzer/build ผ่าน รายละเอียด [รายงาน I-07](../testing/I-07_RESULTS.md)
- ยังไม่ปิด I-07 ครบ: Studio rendering/input/full journey ยังไม่ยืนยัน, O-01 รูปลักษณ์เติบโต/evo ยังเปิดอยู่; ชุดนี้เป็นภาพต้นแบบทุกเลเวล ไม่ใช่งานภาพ final
- I-08 local fault suite ผ่านตามสถานะด้านล่าง; online/two-server ต้องมี test experience ที่ตรวจ IDs ก่อนตาม I-00

## I-08: Fault/data safety (local verification, 2026-10-02)
- ผ่าน 27,680 checks / 2,000 fault scenarios ด้วย memory backend จำลอง; hatch/mix/reward ครบ 5 จุดผิดพลาด จุดละ 100 ครั้ง
- แก้ Operation.Get ให้ฟื้น prepared operation และ retry งานที่เคย Execute แล้วเมื่อ backend กลับมา; intent ที่ยังไม่ execute จะไม่เริ่มงานจากการอ่านสถานะ
- คืน expiresAt เดิมเมื่อ reuse intent และ reject intent ที่หมดอายุโดยไม่มี prepared/receipt แทน pending ไม่สิ้นสุด
- เพิ่ม ingress bucket ก่อนตรวจ/serialize/replay คำขอ รวม unknown routes; จำกัดจำนวน entries และใช้ fingerprint string ระบุความยาว
- ทดสอบ takeover/fencing, outage เกิน lease, สำเนา schema ที่ไม่รองรับ, disconnect/reward recovery, projected size และ request flood ตาม [I-08 results](../testing/I-08_RESULTS.md)
- ยังไม่ปิด I-08 ทั้งหมด: ต้องทดสอบ DataStore จริง/สองเซิร์ฟเวอร์และ migration rehearsal เมื่อมี migration; schema ปัจจุบันรองรับ version 1 เท่านั้น การ reject สำเนา version 99 ไม่ใช่ผล migration

## Realtime battle — คำสั่งล่าสุด 2026-10-02 (แทน auto แบบเทิร์นเดิม)
- ยกเลิก turn-based ทั้งหมด; server timer คุม basic ของแต่ละฝั่งแยกกันตาม Speed
- กดสกิลใช้ทันที cooldown 6 วินาที; โล่หมดหลัง 4 วินาทีหรือรับหนึ่ง hit
- ถอด client AutoBattle scheduler และคิวสกิล; UI รับ server push แล้วแสดง HP/เอฟเฟกต์แบบไม่บล็อกการกด
- rulesVersion mvp-1.1.0; บันทึก I-06 เดิมเป็นประวัติ ระบบปัจจุบันยึด [Realtime results](../testing/REALTIME_RESULTS.md)
- Battle/RPC 178 checks, feed 11 checks, regression I-01–I-07 ผ่าน; ยังรอ Studio walkthrough

## World arena — WORLD AUTO v2 (2026-10-02)
- ภาพต่อสู้ย้ายจาก ViewportFrame ในเมนูไป Workspace บนแท่น TrainingArena พร้อม HP เหนือตัวและดาเมจลอย
- ปุ่มสกิล/แถบคูลดาวน์อยู่ HUD ล่างจอ ใช้ 1–3 ได้แม้เมนูซ่อน; เริ่มสู้จัดกล้องเข้าสนาม จบคืนกล้อง/เมนู
- ใช้ไฟล์ `build/Digievo_WORLD_AUTO_v2.rbxlx` และป้าย WORLD AUTO v2 เพื่อแยกจาก place รุ่นเก่าที่มี F/รอบ
- Battle 178/feed 11 checks และ build ผ่าน; visual/input ใน Studio ยังรอทดสอบ

## Discovery status
T-00สำรวจเสร็จ; T-01ผู้ใช้/journeyเสร็จ; T-02scopeทดลองยืนยันโดยมีO-01; T-03มีcatalog/economy/worldbaselineครบแต่ยังไม่playtest; T-04มีarchitecture/schema/contractsฉบับรวมและNFRร่าง; T-05แตกงานเสร็จ. T-06 เริ่ม implementation ตามคำสั่งผู้ใช้แล้ว

## ลำดับพัฒนาและเกณฑ์จบ
| งาน | Dependency | ผลงานและเกณฑ์จบ | AC/NFR |
|---|---|---|---|
| I-00 เปิดงานimplementation | คำสั่งผู้ใช้ O-05 | ยืนยันscopeที่จะทำจากbaselinev1 แยกtest experience/data มีแผนงานที่ไม่ทำของจริงทับ | C-03 |
| I-01 กฎและcatalog | I-00 | modulesข้อมูล8ตัว/6skill/สูตร; ตรวจ144กรณีworldและstat/XPตัวอย่าง โดยไม่ต้องมีUIสวย | AC-06–11,15–18,24–25,31–36,43–46 |
| I-02 Profile/operation/recovery | I-00 | schema/lease/fencing/preparecommit/receipt; failure/replayไม่สร้างของซ้ำหรือresetprofile | AC-04,49–52; NFR-01/02/07 |
| I-03 RPC boundary | I-01,I-02 | envelopes/actiondispatch/identity/limits/idempotency/status; contractfixturesถูกต้องและerrorไม่หักทรัพยากร | APIครบ; NFR-06 |
| I-04 Starter/ไข่/คอลเลกชัน | I-01–03 | แจกครั้งเดียว สำรวจ3จุด ฟัก/ซื้อ/pending/lock/capacity ทำงานผ่านUIขั้นต่ำ | AC-05,37,39–41 |
| I-05 Mixและpreview | I-04 | rarity/world/สืบทอด/ราคาแสดงก่อนยืนยัน; stale/retry/หลุดได้ผลตามกฎ | AC-01–02,13–17,19–20,23–25,36,39,45–49 |
| I-06 Battleและprogression | I-01–04 | TRAINING1ต่อ1, Speed/cooldown/Shield, Growth/XP/ดาว/reward, disconnectและrewardpending | AC-08,12,21–22,26–30,33–35,38,42–43,53 |
| I-07 รวมjourneyและงานภาพ | I-05,I-06; O-01ก่อนงานภาพfinal | พื้นที่/โมเดลฐาน2แบบ/variants8/ข้อความไทย/keyboard-mouse/ผลpending; ทำวงจรครบ | C-05,AC-31,47–48 |
| I-08 Faultและdata safety | I-02–07 | matrixด้านล่างครบ100repeats/จุด, migrationสำเนา, reconnect2server/fence, requestflood | AC-49–53; NFR-01/02/06/07/08 |
| I-09 Performance | I-07,I-08; O-02 | บันทึกเครื่องจริงและ4clients, p95ต่างๆ/size/budget ผลไม่ถึงเป้าต้องมีแก้หรือปรับเป้าที่ผู้ใช้เห็น | NFR-03–05/07 |
| I-10 ทดลองกับลูกและตัดสินใจ | I-08,I-09; O-03 | ทดลองตามเกณฑ์ที่ตกลง บันทึกจุดสับสน/อยากผสมต่อ/ความรู้สึกเสียตัว เปลี่ยนbalanceแบบversioned | P-03/O-04 |

I-05/I-06ทำได้แยกหลังdependencyแต่ไม่มีการมอบหมายsubagentหรือเพิ่มผู้พัฒนาโดยอัตโนมัติ. งานกฎ/ข้อมูลเดินต่อได้ก่อนO-01ภาพ final; O-02ไม่ขวางสร้างprototypeแต่ขวางอ้างperformanceผ่าน

## Fault matrix ที่ต้องรันเมื่อมีระบบ
| จุดล้มเหลว | ผลที่ต้องเห็น |
|---|---|
| ก่อนprepare | ของเดิมทั้งหมด ไม่มีผลสุ่มเปิดเผย |
| หลังprepareก่อนcommit | ของเดิมถูกพักใช้รายการอื่น; reloadcommitแผนเดิม |
| หลังcommitก่อนresponse | refresh/receiptได้ผลเดิมไม่หักซ้ำ |
| callback/retryซ้ำ100ครั้ง | ผลสุ่มคงเดิม mutationครั้งเดียว |
| inputต่างแต่operationIdเดียว | conflictไม่มีmutationใหม่ |
| เซิร์ฟเวอร์เก่ากลับมาหลังtakeover | generationเดิมเขียนไม่ได้ |
| backendล่ม120s | pendingไม่มีdefaultprofile/ไม่เล่นต่อบนยอดเดา; resolveเมื่อพร้อม |
| หลุดกลางbattle | ยกเลิกแมตช์ไม่เสียของ; rewardpreparedถูกจ่ายครั้งเดียว |
| schemaใหม่ไม่รองรับ/oversize | หยุดและแจ้งตรวจ ไม่ทับหรือtruncateข้อมูล |

## เกณฑ์จบและข้อจำกัด
ก่อนให้ลูกเล่น: ไม่มีbugทำข้อมูลเสีย/ซ้ำ, corejourneyครบ, phase/cooldownตรง, เครื่องทดสอบบันทึก, ไม่มีงานpublishที่ทำโดยไม่มีคำสั่ง. หลังทดลองจึงเลือกปรับ/ทำต่อ/หยุด ไม่ขยายบอส/PvPเอง; basic auto ได้รับคำสั่งผู้ใช้แล้ว 2026-10-02

บันทึกออกแบบเดิมตรวจ 144 random cases, สูตร damage/XP และเอกสารเท่านั้น; สถานะ implementation/การทดสอบปัจจุบันให้ยึด I-01–I-07 และรายงานแต่ละขั้นด้านบน. Online durable fault, multi-client/load/FPS และ playtest เต็มวงจรยังค้าง
