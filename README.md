# EchoPOC

一个 iOS 上的 Telegram 语音对讲 PoC。

当前实现：

- Telegram 接入：`TDLibKit`
- 语音转文字（STT）：Cloudflare Workers AI Whisper
- 播报（TTS）：Microsoft Edge Neural TTS
- UI：SwiftUI

## 环境要求

- macOS
- Xcode 15+
- iOS Simulator 或真机

## Clone 后必须配置的内容

这个项目有两类配置：

1. 编译前必须有的 Telegram 配置
2. 运行时在 App 内填写的 Cloudflare 配置

### 1. Telegram API 配置

用途：
- 用来初始化 TDLib
- 没有这两个值时，项目现在可以编译，但 Telegram 登录页会显示 `Telegram Not Configured`

需要的字段：

- `TELEGRAM_API_ID`
- `TELEGRAM_API_HASH`

获取方式：

- 打开 `my.telegram.org`
- 登录你的 Telegram 账号
- 在 API development tools 里创建应用
- 拿到 `api_id` 和 `api_hash`

配置位置：

- 文件：[EchoPOC/Info.plist](/Users/strrl/playground/GitHub/EchoPOC/EchoPOC/Info.plist)

默认占位值：

```xml
<key>TELEGRAM_API_HASH</key>
<string></string>
<key>TELEGRAM_API_ID</key>
<string>0</string>
```

你需要把它改成自己的值，例如：

```xml
<key>TELEGRAM_API_HASH</key>
<string>your_api_hash</string>
<key>TELEGRAM_API_ID</key>
<string>12345678</string>
```

相关代码：

- [EchoPOC/TelegramConfig.swift](/Users/strrl/playground/GitHub/EchoPOC/EchoPOC/TelegramConfig.swift)
- [EchoPOC/TelegramService.swift](/Users/strrl/playground/GitHub/EchoPOC/EchoPOC/TelegramService.swift)

### 2. Cloudflare Workers AI 配置

用途：

- 按住说话后，把录音发给 Cloudflare Whisper 做 STT

需要的字段：

- `Account ID`
- `API Token`

获取方式：

- 打开 `dash.cloudflare.com`
- 进入 `AI` / `Workers AI`
- 拿到 `Account ID`
- 创建一个可调用 Workers AI 的 `API Token`

配置方式：

- 运行 App
- 进入 `Settings`
- 在 `Cloudflare Workers AI (STT)` 区域填写：
  - `Account ID`
  - `API Token`

保存位置：

- 本地 `UserDefaults`
- 不在仓库里
- 不需要改代码

相关代码：

- [EchoPOC/VoiceSettingsView.swift](/Users/strrl/playground/GitHub/EchoPOC/EchoPOC/VoiceSettingsView.swift)
- [EchoPOC/CloudflareAIService.swift](/Users/strrl/playground/GitHub/EchoPOC/EchoPOC/CloudflareAIService.swift)

## 运行步骤

1. clone 仓库
2. 用 Xcode 打开 [EchoPOC.xcodeproj](/Users/strrl/playground/GitHub/EchoPOC/EchoPOC.xcodeproj)
3. 在 [EchoPOC/Info.plist](/Users/strrl/playground/GitHub/EchoPOC/EchoPOC/Info.plist) 里填入 `TELEGRAM_API_ID` 和 `TELEGRAM_API_HASH`
4. 选择模拟器或真机运行
5. 首次启动时允许麦克风权限
6. 进入 `Settings`，填入 Cloudflare `Account ID` 和 `API Token`
7. 返回 Telegram 登录页，输入手机号、验证码、二次验证密码

## 当前行为说明

- 没填 Telegram 配置：
  - 可以编译
  - Telegram 不会初始化
  - 登录页会显示缺少配置提示

- 没填 Cloudflare 配置：
  - App 可以进入主界面
  - 但对讲语音转文字不可用
  - `Talk` 页面会显示 `API Not Configured`

## 敏感信息边界

不应该提交到 Git 的内容：

- 你自己的 `TELEGRAM_API_ID`
- 你自己的 `TELEGRAM_API_HASH`
- 你自己的 Cloudflare `API Token`

可以提交的内容：

- `TelegramConfig.swift` 代码本身
- `Info.plist` 里的空占位键
- `CloudflareConfig` 的 `UserDefaults` key 名

## 常见问题

### 为什么以前会出现 `Build input file cannot be found`

因为以前项目把 `EchoPOC/TelegramConfig.swift` 当作本地私有文件处理，同时它又被 Xcode target 引用了。别人 clone 后如果没有这个文件，Xcode 会直接报构建输入文件不存在。

现在这个问题已经改掉了：

- `TelegramConfig.swift` 可以提交
- 敏感值不再写死在 Swift 文件里
- 缺配置时只会禁用 Telegram 初始化，不会因为缺文件导致 build fail
