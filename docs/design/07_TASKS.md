# Development Tasks — v1.0

ผู้ใช้สั่งเริ่ม I-00 และให้เดินต่อวันที่ 2026-09-12 แล้ว ปัจจุบันมีโมดูลกฎ I-01 และระบบข้อมูล I-02 แบบทดสอบในเครื่อง ยังไม่มีเกมที่เล่นครบวงจรหรือการบันทึกออนไลน์. Scope/ข้อเปิด [PRD](01_PRD_REVIEW.md), ตัวเลข [Domain](06_DOMAIN_RULES.md), contracts [API](05_API_SPEC.md)

## I-00: เริ่มแล้ว 2026-09-12
- คำสั่งผู้ใช้เริ่ม I-00 ปิด O-05 และแทนสถานะ T-06 ที่ยังไม่อนุญาตในบันทึก Discovery เดิมด้านล่าง
- ยึด MVP baseline v1.0: พื้นที่เล็ก, catalog 8 ตัว, ไข่/ฟัก/คอลเลกชัน, ผสมพร้อม preview/inheritance, Level/Growth, PvE manual 1 ต่อ 1, World Condition และ profile/recovery
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
- ยังไม่ปิดครบแบบ Studio Play/RemoteEvent UI: ยังไม่มีหน้าจอ client, ยังไม่ผูก GameRequest/GameResponse/GamePush จริง และยังไม่ใช่ action rules เต็มของ I-04-I-06
- รายละเอียดผลและข้อจำกัดดู [รายงาน I-03](../testing/I-03_RESULTS.md)

## I-04: ไข่และคอลเลกชัน (local implementation, 2026-09-14)
- เพิ่ม EggActions สำหรับ Collect/Buy/Hatch/SetLocked/ClaimPendingEggs พร้อมตรวจ params, ราคา, ช่องเต็ม, cooldown และระยะฝั่ง server
- เชื่อม GameRequest/GameResponse/GamePush กับ Player identity และเพิ่ม UI ภาษาไทย จุดสำรวจ 3 จุด ตัวนับ cooldown และคอลเลกชัน
- Create ตรวจแผนโดยไม่สุ่ม; Execute สุ่มครั้งเดียวก่อน prepare นอก callback และ recovery ใช้ผลเดิม
- ฟักแสดงผลหลัง committed และ presentation 3 วินาที; client ใช้ requestId เดิมเมื่อคำตอบหายและไม่ลด profileVersion ย้อนหลัง
- ผล CLI/build และข้อจำกัดดู [รายงาน I-04](../testing/I-04_RESULTS.md); Studio log ยืนยัน I-01–I-04 PASS แล้ว และผู้ใช้ยืนยันทดสอบฟัก/เดินเก็บไข่/ล็อก–ปลดล็อกครบโดยไม่ได้รายงานปัญหา; ยังไม่ทดสอบเครือข่ายหลาย client
- ใช้ memory backend เท่านั้น; ระบบผสมและต่อสู้ยังเป็น I-05/I-06 ที่ต้องทำต่อ

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
ก่อนให้ลูกเล่น: ไม่มีbugทำข้อมูลเสีย/ซ้ำ, corejourneyครบ, phase/cooldownตรง, เครื่องทดสอบบันทึก, ไม่มีงานpublishที่ทำโดยไม่มีคำสั่ง. หลังทดลองจึงเลือกปรับ/ทำต่อ/หยุด ไม่ขยายบอส/PvP/autoเอง

สิ่งที่ทำแล้วตอนออกแบบ: คำนวณ144randomcases, สูตรdamage/XP, ตรวจเอกสารIDs/links/JSON. สิ่งที่ยังไม่ทำ: Robloxcode, durablefaulttest, network/load/FPS/playtest; ไม่รายงานว่าtestsเหล่านี้ผ่านจากการตรวจเอกสาร
