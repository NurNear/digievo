# Development Tasks — v1.0

ลำดับนี้เป็นแผนงานหลังคำสั่งimplementationเท่านั้น ไม่มีงานโค้ดเริ่มแล้ว. Scope/ข้อเปิด [PRD](01_PRD_REVIEW.md), ตัวเลข [Domain](06_DOMAIN_RULES.md), contracts [API](05_API_SPEC.md)

## Discovery status
T-00สำรวจเสร็จ; T-01ผู้ใช้/journeyเสร็จ; T-02scopeทดลองยืนยันโดยมีO-01; T-03มีcatalog/economy/worldbaselineครบแต่ยังไม่playtest; T-04มีarchitecture/schema/contractsฉบับรวมและNFRร่าง; T-05แตกงานด้านล่างเสร็จ. T-06 implementationยังไม่อนุญาต

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
