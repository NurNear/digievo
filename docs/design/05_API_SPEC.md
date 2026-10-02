# API Contracts — v1.0

ContractออกแบบสำหรับRoblox client/server ไม่ใช่HTTP API และยังไม่มีโค้ด. กฎธุรกิจใช้ [Domain Rules](06_DOMAIN_RULES.md), typesใช้ [Data Model](04_DATA_MODEL.md)

## Transport และ identity
เลือก RemoteEvent สองช่อง: GameRequest(client→server), GameResponse(server→ผู้เล่นเจ้าของ) สำหรับasyncrequest/result; GamePushสำหรับprofile/world/battle changes. ส่งLuau tablesชนิดพื้นฐานเท่านั้น ไม่ส่งInstance/function/NaN/infinity. ตารางJSONด้านล่างเป็นตัวอย่างเอกสาร ไม่ใช่implementation

Robloxส่งPlayerให้server event handler ใช้UserIdจากตรงนั้นเท่านั้น ไม่มีpassword/token loginของเกมเพิ่ม และไม่เชื่อuserIdจากpayload. ไม่ใช้broadcastส่งprofile/ผลสุ่มprivate. การส่งRemoteEventไม่ใช่durablecommitหรือexactly-onceด้วยตัวเอง

## Envelope
Request: `{apiVersion:1, requestId:string, action:string, args:object}`. requestIdใช้correlation/replayในsession ไม่ใช่หลักฐานสิทธิ์ mutation. IDs1–128อักษร, unknownfieldsปฏิเสธเพื่อจับclientversionผิด

Response: `{apiVersion:1, requestId:string, status:"ok"|"pending"|"prepared"|"committed"|"rejected", data?:object, error?:Error, profileVersion?:integer}`.
- okใช้กับread/token/battleaction ไม่ได้สัญญาว่าเศรษฐกิจcommit
- pendingผลstorageยังไม่ทราบ, preparedรับงานถาวรแล้ว, committedมีreceipt, rejectedยืนยันไม่ได้executeหรือเป็นvalidationfailure
- Error: `{code:string,messageKey:string,retry:"none"|"same_operation"|"refresh"|"later",retryAfterMs?:integer}`; clientแปลข้อความ ไม่แสดงstack trace
- receipt/data.resultไม่ส่งจนcommitted; responseอาจซ้ำ/มาช้า clientไม่ลดprofileVersionหรือbattleRevisionย้อนกลับ

## Read และ preview
| action | args ที่จำเป็น | data เมื่อok |
|---|---|---|
| Profile.Get | `{}` | ProfileView |
| World.Get | `{}` | WorldView |
| Mix.Preview | `{parentIds:[string,string]}` สองinstanceต่างกัน | MixPreviewView |
| Operation.Get | `{operationId:string}` | status pending/prepared/committedพร้อมReceiptตามสิทธิ์ หรือSTALE_OPERATIONให้refresh |
| Battle.Get | `{}` | `{battle?:BattleView}` ไม่มีfieldbattleเมื่อไม่มีแมตช์ |

ProfileView: `{profileVersion,coinBalance,basicEggCount,pendingEggRewards,capacity:{creatures:30,eggs:20},creatures:CreatureView[],nodes:{nodeId,nextAvailableAt}[],recentReceipts:Receipt[],unresolvedOperationId?:string}` ไม่ส่งlease/resultPlan/internalflags

CreatureView: `{instanceId,definitionId,level,totalXP,potentialType,stars,isLocked,stats:{hp,atk,def,spd},slots:SlotView[3]}`. SlotView:`{role:"Species"|"Inherited"|"Growth",skillId?:string,unlocked:boolean}` ช่องว่างไม่มีskillId; GrowthแสดงskillIdแต่unlocked=falseก่อนLevel5

WorldView: `{cycleId,phaseId,timeOfDay:"Day"|"Night",weather:"Clear"|"Rain",nextChangeAt,serverTime,rulesVersion}`. phaseIdรวมcycleIdในการเทียบpreview

MixPreviewView: `{previewId,expiresAt,profileVersion,world:WorldView,cost:20,parentIds:[2],baseRarity,rarityProbabilities:{rarity,probability}[],candidates:CandidateView[]}`
CandidateView:`{definitionId,probability,conditionalProbability,resetPotential:boolean,starsOutcomes:{stars,probability}[],inheritedOutcomes:{skillId?:string,probability}[]}` probabilitiesของstars/skillเป็นconditionalเมื่อได้candidateนี้; รายการไม่มีสกิลใช้objectไม่มีskillId. ชุด candidate probabilitiesรวม1. ไม่สุ่มactualresultตอนpreview

## ขอสิทธิ์และ execute mutation
1. `Operation.Create`: args`{kind,params}` → ok data`{operationId,expiresAt}`. servervalidate/schemaและออกintentในmemoryอายุ60s ยังไม่writeและยังไม่สุ่มลูก. ClientretryrequestIdเดิมต้องได้intentเดิม; หากหายหลังreconnectใช้Profile.Getหาprepared/receipt ไม่executeด้วยIDสุ่มเอง
2. `Operation.Execute`: args`{operationId}` → pending/prepared/committedหรือrejected. serverใช้paramsที่ผูกไว้ ไม่รับparamsใหม่ในExecute. หนึ่งmutationinflight/profile

การออก intent เดิมซ้ำคืน `expiresAt` เดิม ไม่ต่ออายุ. `Operation.Get` ตรวจ prepared/receipt ก่อน expiry และ recover สถานะที่ไม่แน่นอนจาก backend; หากเคย Execute แล้วแต่ PREPARE ยังไม่สำเร็จ จะ retry ด้วย params เดิมผ่าน validation เดิม. การอ่าน intent ที่ยังไม่เคย Execute ไม่เริ่ม mutation. Intent ที่หมดอายุและไม่มี prepared/receipt คืน `EXPIRED_INTENT`.

| kind | params | Receipt.result เมื่อcommitted |
|---|---|---|
| Egg.Collect | `{nodeId:"N01"|"N02"|"N03"}` | `{nodeId,nextAvailableAt,eggDelta:1}` |
| Egg.Buy | `{quantity:1}` | `{coinDelta:-40,eggDelta:1}` |
| Egg.Hatch | `{}` | `{eggDelta:-1,creature:CreatureView}` |
| Mix.Commit | `{previewId:string}` | `{coinDelta:-20,consumedIds:[2],creature:CreatureView}` |
| Creature.SetLocked | `{creatureId:string,locked:boolean}` | `{creatureId,locked}` |
| Reward.ClaimPendingEggs | `{}` | `{moved:integer>=1,pendingRemaining}` ย้ายmin(ช่องว่าง,pending) |

ถ้าSetLockedค่าเดิมให้committed no-op receiptโดยไม่เปลี่ยนทรัพยากร; Claimไม่มีpendingให้NOTHING_TO_CLAIM; ช่องไข่เต็มให้CAPACITY_FULLไม่สร้างnegative changes. Collect/startbattleตรวจระยะ12studsฝั่งserverตามDomain refinements

StarterGrantและBattleRewardเป็นinternal operationsเท่านั้น ไม่มีclientrouteให้เลือกจำนวน/ชนะ. หลังbattlewinใช้battleIdผูกoperationIdก่อนprepare; จ่ายCoin/XP/ดาว/ไข่ในprofilekeyเดียว แล้วpush receipt. หากไข่เต็มบันทึกpendingแทนโดยยังcommitted

### Idempotency/recovery
ผลpreparedในprofileมีสิทธิ์เหนือexpiry/phaseใหม่: Executeซ้ำต้องcommitแผนเดิม ไม่กลับไปvalidatepreviewหมดอายุแล้วปฏิเสธงานยอมรับแล้ว. หลังcommitให้receiptเดิม; operationIdที่ไม่รู้จัก/นอกsession/receiptถูกล้างห้ามเริ่มงานใหม่ ให้STALE_OPERATIONและProfile.Get

sameIDต่างinputจากOperation.Create retryให้IDEMPOTENCY_CONFLICT. ระหว่างstorageunknownหยุดคิว ไม่สร้างIDใหม่เพื่อretry. Resolveอ่านbackendstateที่ไม่cachedก่อนตัดสินว่าไม่มีprepared; ต้องตรวจgenerationด้วย ไม่ให้เซิร์ฟเวอร์เก่าส่งplanใหม่หลังถูกfence

## Battle contracts
| action | args | result |
|---|---|---|
| Battle.Start | `{creatureId,encounterId:"TRAINING"}` | ok `{battle:BattleView}` เลือกC01/C02ศัตรู50/50, D-18 |
| Battle.Action | `{battleId,expectedRevision,command:"SKILL",skillId:string}` | ok `{battle:BattleView,events:CombatEvent[]}` หรือpendingเมื่อรางวัลกำลังบันทึก |
| Battle.Forfeit | `{battleId,expectedRevision}` | ok `{outcome:"forfeit"}` ไม่มีpenalty/reward |

Realtime (2026-10-02): server tick schedules both fighters' BASIC attacks independently.
Battle.Action is SKILL only, applies immediately, and validates ownership, active
battle and server `readyAt` seconds. `expectedRevision` must be a positive integer
no newer than the current revision; older observations are accepted because auto
hits may race the request. A different battle ID is still rejected. Replay with
the same requestId returns the cached result; new requests cannot bypass cooldown.
Battle.Get `{}` returns `{battle?:BattleView}` and can recover a pending reward.

BattleView: `{battleId,revision,status,startedAt,serverTime,player,enemy,events,rewardOperationId?,outcome?}`.
BattleFighter: `{definitionId,stats:{hp,atk,def,spd},currentHP,shield,shieldExpiresAt,attackInterval,nextAttackAt,skills:{skillId,readyAt,cooldownSeconds}[]}`.
CombatEvent: `{seq,at,actor,command,skillId?,rawDamage,shieldAbsorbed,hpDamage,targetHP,shieldGranted}`.
Full snapshots retain the last 24 events. GamePush publishes changed battle views;
clients deduplicate event seq and reject non-increasing snapshot revisions.
No roundIndex, activeSide or owner-turn cooldown fields remain.

หนึ่งactivebattleต่อผู้เล่น; ระหว่างbattleปฏิเสธmutationเศรษฐกิจทั้งหมด ไม่เริ่มbattleเมื่อมีpendingmutation. Loss/forfeitปล่อยstateทันที ไม่มีwriteรางวัล; winเปลี่ยนresolving จนinternaloperationcommitก่อนเริ่มต่อ. Disconnectยกเลิกแมตช์ memory แต่preparedrewardยังrecover

## Push และการคืนสภาพUI
GamePush: `{apiVersion:1,event:"ProfileChanged"|"WorldChanged"|"BattleChanged"|"OperationChanged",data:typedView}` เฉพาะWorldChangedส่งผู้เล่นทุกคนได้. ProfileChangedส่งfullProfileViewเพื่อความง่ายที่capacity30 ไม่ส่งทุกframe; lease refreshไม่push. เมื่อrequestเกิน5sให้แสดงกำลังตรวจสถานะและpollOperation.Getไม่เกิน1/sด้วยIDเดิม; การส่งeventหายให้Getคืนsnapshot ไม่ถือว่าเป็นการcancel

## Error matrix
| code | เกิดเมื่อ | clientทำต่อ |
|---|---|---|
| INVALID_INPUT / UNSUPPORTED_VERSION | schema/type/enum/size/APIversionผิด | หยุด/อัปเดตclient |
| PROFILE_NOT_READY / SESSION_BUSY | โหลดหรือleaseยังไม่พร้อม | later ไม่มีdefaultprofile |
| NOT_OWNER / CREATURE_NOT_FOUND | instanceไม่มีสิทธิ์/ถูกใช้แล้ว | refresh |
| CREATURE_LOCKED / IN_BATTLE / OPERATION_BUSY | stateไม่อนุญาต | รอ/ปลดล็อกผ่านUI |
| INSUFFICIENT_FUNDS / NO_EGG / CAPACITY_FULL | เงื่อนไขทรัพยากรไม่ผ่าน | แสดงเหตุผล ไม่หักของ |
| NODE_UNAVAILABLE / OUT_OF_RANGE | cooldown/ระยะไม่ผ่าน | รอหรือเดินใกล้ |
| STALE_PREVIEW / STALE_PROFILE | ก่อนprepareข้อมูลเปลี่ยน/หมด60s | previewใหม่และผู้เล่นยืนยันใหม่ |
| STALE_OPERATION / IDEMPOTENCY_CONFLICT | IDไม่รู้จัก/ข้อมูลไม่ตรง | refresh ห้ามexecuteเดา |
| INVALID_RULE_CONFIG / PROFILE_INVALID | กฎหรือschemaข้อมูลไม่รองรับ | หยุดและlogเพื่อตรวจ |
| STALE_BATTLE / NOT_YOUR_TURN / SKILL_LOCKED / SKILL_COOLDOWN / BATTLE_ENDED | คำสั่งต่อสู้ไม่ถูกต้อง | Battle.Get |
| NOTHING_TO_CLAIM | ไม่มีไข่ค้าง | refresh |
| RATE_LIMITED | เกินtokenbucket | laterตามretryAfterMs |
| STORAGE_UNAVAILABLE | backendล้มเหลว | same_operationถ้าผลยังunknown; ห้ามอ้างว่าไม่หักแน่นอน |

Rejectedหมายถึงไม่มีdomainmutationจากrequestที่ถูกrejectนั้น; หากoperationเดียวกันเคยprepared/committedต้องlookupแล้วคืนสถานะนั้นก่อนreject. ข้อผิดพลาดtransportไม่ใช่หลักฐานrejected

## Limits และตัวอย่าง
Ingress ต่อผู้เล่น burst 40, เติม 20 requests/วินาที ก่อนตรวจ envelope, fingerprint และ replay; malformed/unknown/cached requests นับด้วย. Fingerprint จำกัดรวม 256 table entries, depth 12 และ budget 8KiB; strings ระบุความยาวเพื่อกัน delimiter collision. Unknown routes ไม่สร้าง action bucket. Disconnect ล้าง ingress ของผู้เล่น.

request<=8KiB, ID<=128ตัวอักษร, mutation1inflight/1s burst2; Operation.Createใช้bucketเดียวกัน; preview2/s burst4; battle2/s burst2; reads/status1/s burst2. invalid/rate-limitไม่เรียกDataStorewrite. serverresponseไม่ใช้8KiBrequestlimit แต่ต้องส่งเฉพาะpublicfields; profileprojectionต้องไม่เกิน256KiB

```json
{"apiVersion":1,"requestId":"req-18","action":"Operation.Execute","args":{"operationId":"op-server-7"}}
```
```json
{"apiVersion":1,"requestId":"req-18","status":"committed","profileVersion":9,"data":{"operationId":"op-server-7","seq":9,"kind":"Egg.Buy","committedAt":1789084800,"result":{"coinDelta":-40,"eggDelta":1}}}
```
seqและprofileVersionในตัวอย่างเท่ากันโดยบังเอิญ ไม่ใช้แทนกัน. ตัวอย่างrejectedก่อนรับงาน:
```json
{"apiVersion":1,"requestId":"req-19","status":"rejected","error":{"code":"STALE_PREVIEW","messageKey":"mix.preview_changed","retry":"refresh"}}
```

## เอกสารแพลตฟอร์ม
ตรวจ2026-09-11: [Roblox Remote events and callbacks](https://create.roblox.com/docs/scripting/events/remote) รองรับการสื่อสารasync; ชื่อroutes/envelopes/IDsข้างต้นเป็นcontractของโครงการ ไม่ใช่APIสำเร็จรูปของRoblox. ServervalidationและDataStoreอ้างอิงในArchitecture
