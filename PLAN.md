# EchoPOC — 项目计划

## 愿景

做一个像对讲机一样的 Telegram 客户端。

收到消息自动播报，说话自动识别发送，端侧处理，低延迟，不过云。

---

## 分阶段计划

### Phase 1: Echo（已完成）

**目标：** 验证流式语音对话的基础体验。

- 按住按钮 → `SFSpeechRecognizer` 实时 STT（on-device）
- 松开按钮 → 立刻 `AVSpeechSynthesizer` 流式 TTS 播报识别结果
- 验证延迟是否可接受（首字播报延迟 < 200ms）

**结论：** 系统 API 够快，体验可以做。

---

### Phase 2: Telegram 集成（当前目标）

**目标：** 把 Echo 的能力嵌进一个真实的 Telegram 客户端。

#### 技术选型

**Telegram 接入层：TDLib**
- 官方 C++ 库，完整实现 MTProto
- iOS 使用 `TDLibKit`（Swift wrapper）
- 不自己实现 MTProto，避免重复造轮子

**语音层：沿用 Phase 1**
- STT: `SFSpeechRecognizer`，`requiresOnDeviceRecognition = true`
- TTS: `AVSpeechSynthesizer`，逐句流式播报

#### 核心功能

**接收端（"自动播报"）：**
- 监听指定会话的新消息
- 文本消息 → 立刻 TTS 播报（"收到：XXX 说，balabala"）
- 语音消息 → 下载 OGG → ffmpeg 转码 → STT → 显示文字 + TTS 播报
- 可以按会话配置开关

**发送端（"对讲机按钮"）：**
- 长按麦克风 → STT 实时识别
- 松开 → 发送文字消息（或语音消息，可选）
- 识别中途可以看到实时文字预览

#### UI 结构（最简版）

```
TabView
├── 会话列表（对讲机模式开关 per chat）
└── 单聊页面
    ├── 消息列表（只读，不需要完整功能）
    ├── 播报状态栏（"正在播报：XXX"）
    └── 底部：长按麦克风按钮
```

---

### Phase 3: 体验打磨（未来）

- 多语言支持（中英自动切换 STT）
- 播报队列管理（多消息同时来，排队/打断逻辑）
- 唤醒词（不用按按钮，说"发送"自动提交）
- 自定义 TTS 声音
- Apple Watch 联动（表盘震动提示，表冠按压发送）

---

## 关键约束

- **全部端侧**：STT/TTS 不走任何云端 API
- **低延迟优先**：TTS 首字延迟目标 < 200ms，STT 实时显示
- **最小 UI**：不做完整 Telegram 替代品，只做对讲机模式这一件事
- **iOS 优先**：利用 Apple 系统 API，Android 后续再考虑

---

## 技术依赖

| 模块 | 方案 | 备注 |
|------|------|------|
| Telegram 协议 | TDLib + TDLibKit | Swift binding |
| STT | SFSpeechRecognizer | on-device，支持中文 |
| TTS | AVSpeechSynthesizer | 流式，系统声音 |
| 音频转码 | ffmpeg（可选） | 处理语音消息 OGG |
| UI | SwiftUI | 最小化 |

---

## 当前进度

- [x] Phase 1: Echo PoC（STT + TTS 流式对话）
- [ ] Phase 2: TDLib 接入，收消息自动播报
- [ ] Phase 2: 发送端，长按录音发消息
- [ ] Phase 2: 会话列表 + 对讲机模式开关
- [ ] Phase 3: 打磨

---

## 下一步

1. 集成 TDLibKit（Swift Package）
2. 实现 TelegramService：登录、监听消息
3. 把 SpeechManager 里的 TTS 接上消息事件
4. 最简 UI：会话列表 + 单聊页面 + 麦克风按钮
