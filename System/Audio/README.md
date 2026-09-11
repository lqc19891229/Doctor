# 音效系统

`SfxManager` 是全局 Autoload，音效统一输出到 `SFX` Audio Bus，因此会自动受设置菜单中的“音效音量”控制。

## 按钮音效

所有进入场景树的 `BaseButton` 会自动获得点击音，不需要在各场景重复连接信号。若某个按钮需要静音，在该按钮上添加布尔元数据：

```text
sfx_disabled = true
```

按钮音使用运行时生成的短音色，不增加额外二进制素材。管理器使用 4 个播放器组成小型音源池，连续点击时不会频繁截断前一个声音。

## 把脉心跳

心跳复用 `res://Assets/hear_tbeat.mp3`：

- 按住 `Q+A+Z` 并显示右手脉象时开始循环；
- 按住 `W+S+X` 并显示左手脉象时开始循环；
- 松开任意键、混按两组键、关闭把脉窗口或退出诊疗时立即停止；
- 普通诊室和剧情诊疗共用同一套行为。

需要在其他玩法控制心跳时，调用：

```gdscript
SfxManager.set_heartbeat_active(true)
SfxManager.set_heartbeat_active(false)
```
