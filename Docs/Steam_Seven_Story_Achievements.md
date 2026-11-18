# 《医者》剩余七个 Steam 成就配置与本地化

Steam App ID：`5608660`

共 7 个剧情类成就，全部设置为 **Client**，进度统计留空，集合选择 **基础游戏**；建议对可能剧透剧情的成就勾选“剧透”。上传图标须为 256×256 PNG，按 `{API}_ACHIEVED.png`、`{API}_UNACHIEVED.png` 命名。

| 简体中文名称 | 简体中文描述 | Steam API | 剧情 ID |
|---|---|---|---|
| 一个违背祖宗的决定 | 完成辞别老师剧情 | `FAREWELL_TEACHER` | `004_04` |
| 一战成名 | 成功治愈世子 | `CURE_PRINCE_HEIR` | `005_02` |
| 过年啦 | 完成上元灯节剧情 | `LANTERN_FESTIVAL` | `027` |
| 一个小生命 | 完成吴芷兰妊娠相关治疗成功剧情 | `WUZHILAN_PREGNANCY` | `026_02` |
| 风波平息 | 完成结案剧情 | `CASE_RESOLVED` | `021` |
| 为往圣继绝学 | 完成《本草纲目》完书剧情 | `FINISH_BENCAO_GANGMU` | `000_01` |
| 为万世开太平 | 通关游戏 | `COMPLETE_GAME` | `000_05` |

## 本地化字段（Steamworks 每种语言分别填写名称/描述）

### 一个违背祖宗的决定 — `FAREWELL_TEACHER`

| 语言 | 名称 | 描述 |
|---|---|---|
| 简体中文 | 一个违背祖宗的决定 | 完成辞别老师剧情 |
| 繁体中文 | 一個違背祖宗的決定 | 完成辭別老師劇情 |
| 英语 | A Decision Against Tradition | Complete the farewell to your teacher storyline. |
| 日语 | 師との別れ | 師との別れの物語を完了する |
| 韩语 | 조상의 뜻을 거스르는 결단 | 스승과 작별하는 이야기를 완료하세요. |

### 一战成名 — `CURE_PRINCE_HEIR`

| 语言 | 名称 | 描述 |
|---|---|---|
| 简体中文 | 一战成名 | 成功治愈世子 |
| 繁体中文 | 一戰成名 | 成功治癒世子 |
| 英语 | Rise to Fame | Successfully cure the prince's heir. |
| 日语 | 一躍名医 | 世子の治療に成功する |
| 韩语 | 일약 명의 | 세자의 치료에 성공하세요. |

### 过年啦 — `LANTERN_FESTIVAL`

| 语言 | 名称 | 描述 |
|---|---|---|
| 简体中文 | 过年啦 | 完成上元灯节剧情 |
| 繁体中文 | 過年啦 | 完成上元燈節劇情 |
| 英语 | Happy New Year! | Complete the Lantern Festival storyline. |
| 日语 | 新年を祝おう | 元宵節の物語を完了する |
| 韩语 | 새해가 왔어요! | 원소절 등불 축제 이야기를 완료하세요. |

### 一个小生命 — `WUZHILAN_PREGNANCY`

| 语言 | 名称 | 描述 |
|---|---|---|
| 简体中文 | 一个小生命 | 完成吴芷兰妊娠相关治疗成功剧情 |
| 繁体中文 | 一個小生命 | 完成吳芷蘭妊娠相關治療成功劇情 |
| 英语 | A New Life | Successfully complete Wu Zhilan's pregnancy treatment storyline. |
| 日语 | 新たな命 | 呉芷蘭の妊娠に関わる治療を成功させる |
| 韩语 | 작은 생명 | 오지란의 임신 관련 치료 이야기를 성공적으로 완료하세요. |

### 风波平息 — `CASE_RESOLVED`

| 语言 | 名称 | 描述 |
|---|---|---|
| 简体中文 | 风波平息 | 完成结案剧情 |
| 繁体中文 | 風波平息 | 完成結案劇情 |
| 英语 | Peace Restored | Complete the case resolution storyline. |
| 日语 | 騒動の終息 | 事件解決の物語を完了する |
| 韩语 | 풍파가 잦아들다 | 사건 종결 이야기를 완료하세요. |

### 为往圣继绝学 — `FINISH_BENCAO_GANGMU`

| 语言 | 名称 | 描述 |
|---|---|---|
| 简体中文 | 为往圣继绝学 | 完成《本草纲目》完书剧情 |
| 繁体中文 | 為往聖繼絕學 | 完成《本草綱目》完書劇情 |
| 英语 | Passing On the Legacy | Complete the Compendium of Materia Medica storyline. |
| 日语 | 先人の学を継ぐ | 『本草綱目』完成の物語を完了する |
| 韩语 | 옛 성현의 학문을 잇다 | 《본초강목》 완성 이야기를 완료하세요. |

### 为万世开太平 — `COMPLETE_GAME`

| 语言 | 名称 | 描述 |
|---|---|---|
| 简体中文 | 为万世开太平 | 通关游戏 |
| 繁体中文 | 為萬世開太平 | 通關遊戲 |
| 英语 | Peace for All Ages | Complete the game. |
| 日语 | 万世の平和へ | ゲームをクリアする |
| 韩语 | 태평성대를 위하여 | 게임을 클리어하세요. |

## 游戏内触发逻辑

当前实现使用 `StoryManager._mark_story_played()`，只有剧情**正式结束、完成跳过或成功治疗分支的后续剧情结束**时，才向 `SteamAchievements.unlock_for_completed_story(story_id)` 发送剧情 ID。不会在剧情开始时解锁。

- `005_02`：剧情资源带 `condition_treatment_result = "cured"`，主剧情来源为 `005_01`，只有治疗成功后才进入对应剧情。
- `026_02`：剧情资源带 `condition_treatment_result = "cured"`，主剧情来源为 `026_01`，同样只在治疗成功时出现。
- `027`：仓库内真实 ID 为 `027`，不是 `027_上元灯节`。
- `000_05`：结局剧情 `after_play = "endgame"`，仅此标记视为正常通关；`000_06`、`000_07`、`000_08` 为 gameover，不应解锁。
- 读取已有的 `played_story_ids` 旧存档时，可补发已完成但尚未获得的剧情成就；Steam 账户已获得的成就不会重复解锁。

## 注意

1. **必须先在 Steamworks 创建全部 7 个 API 名称**（大小写一致），然后保存、发布配置，游戏才能按名称调用。
2. 本次 PR 仅修改代码与说明文档；图标 PNG 作为单独下载包提供，没有提交到 GitHub 仓库。
3. 本次更改没有在 Godot 4.6 编辑器和 Steam 客户端中运行验证，需用开发账户逐项测试剧情解锁。
