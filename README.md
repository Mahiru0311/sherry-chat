# iOS 原生 AI 聊天应用

Dolos 和 Sherry 的第一个项目：从零做一个 iOS 原生的 AI 聊天应用。

目标：先做出一个真的像苹果信息 App 的聊天页面（蓝色灰色气泡、圆角、间距、字体、自然的键盘、深浅色、iOS 26 Liquid Glass），再接 AI。一步一步来，先把页面做得像，再接对话。

- 技术：SwiftUI 原生，优先 iOS 26+，能交给系统组件的地方交给系统。
- 第一阶段：只做一个聊天页面，别的先不碰。
- 第二阶段：接 OpenAI 兼容 API（地址、Key、模型名可配，流式输出，多轮对话）。
- 第三阶段：聊天记录本地存。

## v1 重启（2026-11-18，Dolos 定）

全部重新来，需要 swift-chat 依赖的都不做。自研 spike 升上来当 v1 底座，
名字 Sherry Chat、Bundle ID `com.sherry.chat` 不变，里面不再有 swift-chat。
库版主 App 停用、留档不删（git 历史里还在），spike 仓库留作实验场。

- 滚动/键盘引擎：FluidGroup `swiftui-messaging-ui`（Apache-2.0），
  vendored 在 `fluidgroup/`，不改远程 SPM。
- 气泡、顶栏、输入栏：全部手写 SwiftUI。
- 玻璃：自己的三个 helper（`SherryChat/LiquidGlass.swift`），iOS 26 真
  `.glassEffect()`，iOS 18–25 回退毛玻璃。
- 构建要小、要轻：v1 基准 343K，不加新 SPM 依赖。
- 第三方声明：`THIRD_PARTY_NOTICES.md`（来源、许可证、怎么用、改了什么）。

## 文件夹

- `SherryChat/` — v1 源码（iMessage 风格聊天页、微信式联系人详情、MCP/Skills 工具入口、气泡、输入栏、玻璃、附件、听写）
- `SherryChat.xcodeproj/` — 手写工程（源文件用同步组，加文件不用登记）
- `fluidgroup/` — vendored 的 FluidGroup swiftui-messaging-ui
- `.github/workflows/ios.yml` — CI：archive-only，unsigned IPA（macos-15-intel + Xcode 26）
- `planning/PLAN.md` — 分步规划、验证方法、坑
- `research/` — 研究笔记（审查、整合方案、自研参考、swift-chat 笔记）
- `downloads/` — 下载的东西
- `cache/` — 缓存、临时文件，好清理
- `logs/` — 过程日志
- `state.json` — 当前状态小记录，动手前先看它

状态：2026-11-18，v1 重启交接中。App 名 Sherry Chat，Bundle ID `com.sherry.chat`，目标 iOS 26+、最低 iOS 18。仓库：`Dolos311/sherry-chat`。
