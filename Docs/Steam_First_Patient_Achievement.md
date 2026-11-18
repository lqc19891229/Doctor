# Steam 成就：初出茅庐

Steam App ID: `5608660`  
成就 API 名称：`FIRST_PATIENT_CURED`

## Steamworks 后台

进入 **编辑 Steamworks 设置 → 统计与成就 → 管理成就 → 基础游戏 → 创建成就**：

| 字段 | 值 |
| --- | --- |
| API Name | `FIRST_PATIENT_CURED` |
| 中文名 | 初出茅庐 |
| 中文描述 | 成功治疗一位患者 |
| 英文名 | First Steps |
| 英文描述 | Successfully treat your first patient. |
| Set By | Client |
| Visibility | Visible |
| Progress Stat | 空白 |
| Achieved icon | `FIRST_PATIENT_CURED_ACHIEVED.png` (256×256) |
| Unachieved icon | `FIRST_PATIENT_CURED_UNACHIEVED.png` (256×256) |

保存后在 Steamworks 的 **发布** 页面发布配置；不需要正式上线游戏才能测试。

## Godot 侧依赖

当前仓库尚未包含 Steam SDK / GodotSteam 二进制扩展。
Steam 成就桥接脚本位于 `System/Steam/SteamAchievements.gd`，在 `project.godot` 中注册为 autoload `SteamAchievements`。

1. 安装与 Godot 4.6、目标平台兼容的 GodotSteam GDExtension，以及所需的 Steam API 原生库。官方说明：https://godotsteam.com/
2. 使用 Steam 客户端登录具有该 App ID 的开发 / 测试权限的账户。
3. 通过 Steam 启动测试版本（或按照 GodotSteam 文档配置本地调试环境）。
4. 首次成功提交处方后，`Records.record_treatment()` 写入 `success = true`，触发 `SteamAchievements.unlock_first_patient_cured()`。
5. 成就脚本使用 `setAchievement()` 并调用 `storeStats()`，将解锁状态提交到 Steam。

### 兼容性

- 未安装 GodotSteam、或未启动 Steam 客户端时，桥接脚本自动停用，不影响普通游戏流程。
- 诊室治疗和剧情治疗统一由 `RecordsManager` 判定；失败记录不会解锁。
- 成就仅是 Steam 账户的进度，创建新存档不会清除已解锁的 Steam 成就。
- 加载曾成功治疗过病人的旧存档时，会补发未获得的 Steam 成就。
- Steam 配置未发布或 API 名称不一致时无法提交成功；请检查编辑器日志和发布状态。

## 调试

Steam 文档：https://partner.steamgames.com/doc/features/achievements/ach_guide

若要重复测试，可以用 Steam 客户端控制台清除单个成就：

```
achievement_clear 5608660 FIRST_PATIENT_CURED
```

请仅在自己的测试账户上执行。清除后再在游戏中完成一次成功治疗，或加载已治疗的旧存档。
