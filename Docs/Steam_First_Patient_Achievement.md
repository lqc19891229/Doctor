# Steam 成就接入：医者

Steam App ID: `5608660`

## 已配置的成就

| 成就 | API 名称 | 解锁条件 |
| --- | --- | --- |
| 初出茅庐 | `FIRST_PATIENT_CURED` | 至少成功治疗过一位患者 |
| 炉火纯青 | `TREAT_100_PATIENTS` | Steam 统计 `TOTAL_PATIENTS_CURED` 达到 100 |
| 博览群书 | `READ_ALL_BOOK_ENTRIES` | 总图鉴中所有 `BookEntryDB` 医书条目均已阅读 |

## Steamworks 配置

### 统计数据

| 字段 | 值 |
| --- | --- |
| API Name | `TOTAL_PATIENTS_CURED` |
| Type | `INT` |
| Set By | `Client` |
| Increment Only | 是 |
| Minimum | `0` |
| Maximum | `999999` |
| Default | `0` |

`TREAT_100_PATIENTS` 关联该统计，成就进度范围为 0–100。

### 成就

三个成就都设置为 Client。初出茅庐与博览群书不关联进度统计；炉火纯青关联 `TOTAL_PATIENTS_CURED`，目标值为 100。

所有成就与统计 API 名称必须与 GDScript 常量完全一致。保存后台配置后，在 Steamworks 的「发布」页面发布配置变更；不需要正式发布游戏。

## Godot 项目接入

项目使用 Godot 4.6。自动加载节点已在 `project.godot` 注册：

`SteamAchievements="*res://System/Steam/SteamAchievements.gd"`

需要安装与 Godot 4.6 匹配的 GodotSteam GDExtension 和当前目标平台对应的原生库。不要同时安装 GodotSteam 的 GDExtension 与 Module 版本。安装后重启 Godot 编辑器，并通过 Steam 客户端启动游戏进行验证。

官方资源：
- GodotSteam GDExtension：https://godotengine.org/asset-library/asset/2445
- GodotSteam 初始化教程：https://godotsteam.com/tutorials/initializing/
- GodotSteam 成就与统计 API：https://godotsteam.com/classes/userstats/

## 游戏侧实现

### 初出茅庐

`RecordsManager.record_treatment()` 在新增的治疗记录 `success == true` 时调用 `unlock_first_patient_cured()`。普通诊疗和剧情诊疗共用记录入口，因此失败记录不会解锁。

加载旧存档时，如果已有成功治疗记录，也会补发成就。

### 炉火纯青

每次新增成功治疗记录时，调用 `record_successful_patient()` 更新 Steam 统计 `TOTAL_PATIENTS_CURED`。

加载旧存档时，使用该存档中的成功治疗总数作为 Steam 统计的下限；不会把 Steam 账户已有统计降低。Steam 统计按账户累计，独立于当前游戏存档。

当统计达到 100 时，游戏会提交 `TREAT_100_PATIENTS`。Steamworks 中关联的进度统计也会显示 0–100 的进度。

### 博览群书

`UnlockManager._touch_readbook_state()` 会把当前存档的阅读进度合并到 `GlobalReadBookArchive`。总图鉴跨存档累积，只有当 `BookEntryDB.get_all_entries()` 返回的全部条目都存在于总图鉴已读集合中，才调用 `unlock_read_all_book_entries()`。

因此该成就检查的是游戏数据库中的全部医书条目，而不是仅检查当前打开的某一本书。

## 代码行为与兼容性

- 未安装 GodotSteam 或 Steam 客户端不可用时，游戏诊疗、读书和存档流程继续运行；Steam 功能停用。
- Steam 初始化设置 `SteamAppId` 和 `SteamGameId` 为 `5608660`。
- Steam 回调由自动加载节点持续处理。
- 成就状态和统计数据通过 `storeStats()` 提交。
- 尚未发布的成就 API 或统计 API 会保持待提交状态并定时重试。
- 成功治疗统计只在新治疗记录写入时增加；读档时仅将 Steam 统计补到当前存档成功治疗数以上，避免重复累计。
- 代码合并后仍需安装 GDExtension，并通过有测试权限的 Steam 账户进行真实运行验证。

## 测试建议

1. 使用 Steam 客户端登录拥有该 App ID 测试权限的账户。
2. 通过 Steam 启动游戏，检查 Godot 输出是否出现 Steam 初始化成功日志。
3. 完成一次成功治疗，确认 `FIRST_PATIENT_CURED` 解锁。
4. 完成治疗并检查 Steamworks 统计 `TOTAL_PATIENTS_CURED` 是否增加；测试时可在测试环境中调整统计值或使用专用测试账户验证 100 人阈值。
5. 逐步阅读医书条目；确认全部条目读完后解锁 `READ_ALL_BOOK_ENTRIES`。
6. 使用多个存档验证总图鉴跨存档累积，并确认失败治疗不会增加治疗统计。

不要在正式玩家账户上使用清除统计或重置成就的调试操作。
