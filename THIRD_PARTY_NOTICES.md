# Sherry Chat — 第三方声明（THIRD_PARTY_NOTICES）

- 版本：v1 重启（2026-11-18）
- 依据：`research/project-review.md`（第一阶段审查）+ `research/integration-plan.md` §四
- 规则：能直接复用的成熟开源小件，在许可证允许范围内合理复用；只当设计参考的，提取思路后用原生 SwiftUI 重写；许可证不允许复用的代码一行不进；分发时随附本文件与下面列出的许可证文本。

## 复用与参考清单

| 东西 | 来源 | 许可证 | 我们怎么用 | 状态 |
|---|---|---|---|---|
| `swiftui-messaging-ui`（滚动/键盘引擎，`TiledView` 等） | FluidGroup，https://github.com/FluidGroup/swiftui-messaging-ui | Apache-2.0 | `fluidgroup/` 是上游仓库的 vendored 副本，**改过两处**（Apache-2.0 允许改，改动留痕）：① `Tiled/TiledView.swift` 的三点气泡退出滚动删掉 + `nextAppendScrollAnimated` 一次性开关（steps 67–68）；② `Tiled/TiledScrollPosition.swift` + `Tiled/TiledView.swift` 加了按条目滚动（`scrollToItem(index:)`，step 70，点引用跳转用）；其余未改动；App 只依赖它的 `MessagingUI` product | v1 已用，v2 有改动 |
| `RoundedCornerShape` + `RectCorner`（切线弧逐角圆角） | SwiftyChat，https://github.com/EnesKaraosman/SwiftyChat | Apache-2.0 | 改写进 `SherryChat/BubbleShape.swift`：气泡单条连续轮廓的四个角用切线弧画法；改动：只保留四个角的切线弧画法，尾巴的相切 quad 是我们自己按 SimpleX 思路写的 | v1 已用（第三阶段第 1 项） |
| 玻璃回退细节（按场景选 Material + 0.5pt 白描边模拟折射亮线 + Reduce Transparency / Increased Contrast / Reduce Motion 分支） | LiquidGlass（rguillen-dev），https://github.com/rguillen-dev/LiquidGlass | MIT | 只借做法，改我们自己的 `SherryChat/LiquidGlass.swift` 回退分支；不引整个包 | v1 已用（`GlassFallbackSurface`，第三阶段第 5 项） |
| `GlassColorContrast` 的思路（WCAG 对比度推导前景色） | LiquidGlass（rguillen-dev） | MIT | 只借思路，自己写；v1 暂未用上 | 参考 |
| 发送动画（输入栏上方 overlay 一份气泡 + `matchedGeometryEffect` + 0.2s `.smooth`） | ConversationUI，https://github.com/Mackarous/ConversationUI | MIT | 改写进 `SherryChat/ChatView.swift` 的发送流程；改动：overlay 气泡用我们自己的 `MessageCell` 样式，动画时长 0.2s 不变 | v1 已用（第三阶段第 4 项） |
| `Message.Status` 状态机（参考） | Exyte/Chat，https://github.com/exyte/Chat | MIT | 只参考；我们已有自己的 `DeliveryStatus` 状态模型 | 参考 |
| `KeyboardState`（键盘在不在 + 动画时长） | Exyte/Chat | MIT | 改写进 `SherryChat/InputBar.swift`：听系统键盘通知拿 `isVisible` 与动画时长，不自己算键盘高度；FluidGroup 的键盘跟随不变 | v1 已用（第三阶段第 3 项） |
| 流式契约的接口形状（`send()` 预建空回复 + `responseID`、`updateResponse(id:text:finished:)` 只接受当前 id、`retry()` 删掉该条及之后开新 id） | chatgpt-ios-ui `ChatState`，https://github.com/bryanrg22/chatgpt-ios-ui | MIT | 只在 App 第二阶段（接 AI）实现时照着写接口形状；v1 不写任何相关代码 | 第二阶段才用 |
| `ChatAction` 枚举的边界划分 | chatgpt-ios-ui | MIT | 同上，第二阶段才用 | 第二阶段才用 |
| 气泡数字与动效参数（圆角 16、尾巴往外 5pt / 往下 2pt、组内间距 2pt、弹簧 170/10 等） | SwiftUIMessagesUIClone，https://github.com/GetStream/SwiftUIMessagesUIClone | **无许可证（保留所有权利）** | 只记数字，不抄代码 | 数字参考 |
| 玻璃 morph 的思路（Container + union + `.buttonStyle(.glass)`） | Glass_Effect_SwiftUI、LiquidGlassSwiftUI | **无许可证** | 只学思路，自己写；v1 暂不用 morph | 思路参考 |
| 气泡单条连续轮廓 + 相切 quad 尾巴的思路（控制点 `d = tailHeight − w²/tailHeight`） | SimpleX Chat `ChatItemClipShape.swift`，https://github.com/simplex-chat/simplex-chat | **AGPL-3.0** | 只借思路，自己重写；一行代码不抄 | 思路参考 |
| 正在输入参数（bounce ±2.5pt、0.5s、透明度 1→0.5、气泡 1→1.04、两个小尾巴圆） | MessageKit，https://github.com/MessageKit/MessageKit | MIT | 只借数字与做法，自己写 | v1 已用（`TypingBubble`，第三阶段第 2 项） |
| 键盘 `keyboardDismissMode = .interactive` | MessageKit | MIT | 只借做法，自己写 | v1 已用（`KeyboardDismissProbe`，第三阶段第 3 项） |
| 分组断点 60 秒、组内/组间距 | Stream `stream-chat-swiftui` | **私有 SOURCE CODE LICENSE（非开源）** | 只记数字，不抄代码 | 数字参考 |
| SSE + Keychain + 失败分类 + 节流合并的思路 | EchoUI，https://github.com/Adarsky/EchoUI | **GPL-3.0（强 copyleft）** | 只学思路，第二阶段自己重写；**一行代码都不进** | 思路参考（第二阶段） |
| 行为清单（尾巴只落最后一条、状态机、假回复 600/900/1800ms 时序） | swift-chat，https://github.com/unionst/swift-chat | **专有 Swift Chat License v1.0（闭源）** | 只当验收对照；不复用代码、不反编译、不当依赖 | 行为参考 |

## v2（self-dev-v2，2026-11-18，Dolos 10:32 批准自研）

- swift-chat（UnionChat 二进制）从 v2 起**彻底不再是依赖**：`SherryChat.xcodeproj` 里的远程包引用、`import SwiftChat`、`Chat` / `Message` / `MessageMedia` 类型全部移除。只当验收对照（就是 Dolos 的三张截图），不复用代码、不反编译。库版代码留在 `main` 分支的 git 历史里，不删。
- FluidGroup `swiftui-messaging-ui` 仍是唯一的滚动引擎依赖（Apache-2.0）。v2 分支里 `fluidgroup/` 是上游仓库的 vendored 副本，但只推了包本身需要的文件（`Package.swift`、`Package.resolved`、`LICENSE`、`Sources/`、`Tests/`）；上游的 `Dev/` 演示 App 没推，不需要。**改动过上游源码两处**（见上表 FluidGroup 那行：三点气泡退出滚动 + `nextAppendScrollAnimated`，按条目滚动 `scrollToItem`），其余未改动。
- 玻璃回退新增一条思路参考：SwiftGlassUI（bc1pjerry，MIT）的三级回退（原生玻璃 → ultraThinMaterial → Reduce Transparency 下实色），抄进我们自己的 `SherryChat/LiquidGlass.swift`；不引整包。

## 许可证文本

下面是本 App 实际分发时需要随附的许可证文本（MIT 与 Apache-2.0 的
全文直接取自各仓库根目录的 LICENSE 文件原文，未改动）。
GPL-3.0 与专有许可证的项目我们没有分发其代码，故此处不附全文，
只在上表注明。

### MIT License（适用于上表所有 MIT 项目）

版权行（各项目不同，许可证正文相同）：

- Copyright (c) 2026 Ricardo Guillen（LiquidGlass）
- Copyright (c) 2024 Andrew Mackarous（ConversationUI）
- Copyright (c) 2026 Bryan Ramirez-Gonzalez and contributors（chatgpt-ios-ui）
- Copyright (c) 2019 exyte（Exyte/Chat）
- Copyright (c) 2017 MessageKit（MessageKit）

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.


### Apache License 2.0（适用于 FluidGroup swiftui-messaging-ui 与 SwiftyChat）

Apache License
                           Version 2.0, January 2004
                        http://www.apache.org/licenses/

   TERMS AND CONDITIONS FOR USE, REPRODUCTION, AND DISTRIBUTION

   1. Definitions.

      "License" shall mean the terms and conditions for use, reproduction,
      and distribution as defined by Sections 1 through 9 of this document.

      "Licensor" shall mean the copyright owner or entity authorized by
      the copyright owner that is granting the License.

      "Legal Entity" shall mean the union of the acting entity and all
      other entities that control, are controlled by, or are under common
      control with that entity. For the purposes of this definition,
      "control" means (i) the power, direct or indirect, to cause the
      direction or management of such entity, whether by contract or
      otherwise, or (ii) ownership of fifty percent (50%) or more of the
      outstanding shares, or (iii) beneficial ownership of such entity.

      "You" (or "Your") shall mean an individual or Legal Entity
      exercising permissions granted by this License.

      "Source" form shall mean the preferred form for making modifications,
      including but not limited to software source code, documentation
      source, and configuration files.

      "Object" form shall mean any form resulting from mechanical
      transformation or translation of a Source form, including but
      not limited to compiled object code, generated documentation,
      and conversions to other media types.

      "Work" shall mean the work of authorship, whether in Source or
      Object form, made available under the License, as indicated by a
      copyright notice that is included in or attached to the work
      (an example is provided in the Appendix below).

      "Derivative Works" shall mean any work, whether in Source or Object
      form, that is based on (or derived from) the Work and for which the
      editorial revisions, annotations, elaborations, or other modifications
      represent, as a whole, an original work of authorship. For the purposes
      of this License, Derivative Works shall not include works that remain
      separable from, or merely link (or bind by name) to the interfaces of,
      the Work and Derivative Works thereof.

      "Contribution" shall mean any work of authorship, including
      the original version of the Work and any modifications or additions
      to that Work or Derivative Works thereof, that is intentionally
      submitted to Licensor for inclusion in the Work by the copyright owner
      or by an individual or Legal Entity authorized to submit on behalf of
      the copyright owner. For the purposes of this definition, "submitted"
      means any form of electronic, verbal, or written communication sent
      to the Licensor or its representatives, including but not limited to
      communication on electronic mailing lists, source code control systems,
      and issue tracking systems that are managed by, or on behalf of, the
      Licensor for the purpose of discussing and improving the Work, but
      excluding communication that is conspicuously marked or otherwise
      designated in writing by the copyright owner as "Not a Contribution."

      "Contributor" shall mean Licensor and any individual or Legal Entity
      on behalf of whom a Contribution has been received by Licensor and
      subsequently incorporated within the Work.

   2. Grant of Copyright License. Subject to the terms and conditions of
      this License, each Contributor hereby grants to You a perpetual,
      worldwide, non-exclusive, no-charge, royalty-free, irrevocable
      copyright license to reproduce, prepare Derivative Works of,
      publicly display, publicly perform, sublicense, and distribute the
      Work and such Derivative Works in Source or Object form.

   3. Grant of Patent License. Subject to the terms and conditions of
      this License, each Contributor hereby grants to You a perpetual,
      worldwide, non-exclusive, no-charge, royalty-free, irrevocable
      (except as stated in this section) patent license to make, have made,
      use, offer to sell, sell, import, and otherwise transfer the Work,
      where such license applies only to those patent claims licensable
      by such Contributor that are necessarily infringed by their
      Contribution(s) alone or by combination of their Contribution(s)
      with the Work to which such Contribution(s) was submitted. If You
      institute patent litigation against any entity (including a
      cross-claim or counterclaim in a lawsuit) alleging that the Work
      or a Contribution incorporated within the Work constitutes direct
      or contributory patent infringement, then any patent licenses
      granted to You under this License for that Work shall terminate
      as of the date such litigation is filed.

   4. Redistribution. You may reproduce and distribute copies of the
      Work or Derivative Works thereof in any medium, with or without
      modifications, and in Source or Object form, provided that You
      meet the following conditions:

      (a) You must give any other recipients of the Work or
          Derivative Works a copy of this License; and

      (b) You must cause any modified files to carry prominent notices
          stating that You changed the files; and

      (c) You must retain, in the Source form of any Derivative Works
          that You distribute, all copyright, patent, trademark, and
          attribution notices from the Source form of the Work,
          excluding those notices that do not pertain to any part of
          the Derivative Works; and

      (d) If the Work includes a "NOTICE" text file as part of its
          distribution, then any Derivative Works that You distribute must
          include a readable copy of the attribution notices contained
          within such NOTICE file, excluding those notices that do not
          pertain to any part of the Derivative Works, in at least one
          of the following places: within a NOTICE text file distributed
          as part of the Derivative Works; within the Source form or
          documentation, if provided along with the Derivative Works; or,
          within a display generated by the Derivative Works, if and
          wherever such third-party notices normally appear. The contents
          of the NOTICE file are for informational purposes only and
          do not modify the License. You may add Your own attribution
          notices within Derivative Works that You distribute, alongside
          or as an addendum to the NOTICE text from the Work, provided
          that such additional attribution notices cannot be construed
          as modifying the License.

      You may add Your own copyright statement to Your modifications and
      may provide additional or different license terms and conditions
      for use, reproduction, or distribution of Your modifications, or
      for any such Derivative Works as a whole, provided Your use,
      reproduction, and distribution of the Work otherwise complies with
      the conditions stated in this License.

   5. Submission of Contributions. Unless You explicitly state otherwise,
      any Contribution intentionally submitted for inclusion in the Work
      by You to the Licensor shall be under the terms and conditions of
      this License, without any additional terms or conditions.
      Notwithstanding the above, nothing herein shall supersede or modify
      the terms of any separate license agreement you may have executed
      with Licensor regarding such Contributions.

   6. Trademarks. This License does not grant permission to use the trade
      names, trademarks, service marks, or product names of the Licensor,
      except as required for reasonable and customary use in describing the
      origin of the Work and reproducing the content of the NOTICE file.

   7. Disclaimer of Warranty. Unless required by applicable law or
      agreed to in writing, Licensor provides the Work (and each
      Contributor provides its Contributions) on an "AS IS" BASIS,
      WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
      implied, including, without limitation, any warranties or conditions
      of TITLE, NON-INFRINGEMENT, MERCHANTABILITY, or FITNESS FOR A
      PARTICULAR PURPOSE. You are solely responsible for determining the
      appropriateness of using or redistributing the Work and assume any
      risks associated with Your exercise of permissions under this License.

   8. Limitation of Liability. In no event and under no legal theory,
      whether in tort (including negligence), contract, or otherwise,
      unless required by applicable law (such as deliberate and grossly
      negligent acts) or agreed to in writing, shall any Contributor be
      liable to You for damages, including any direct, indirect, special,
      incidental, or consequential damages of any character arising as a
      result of this License or out of the use or inability to use the
      Work (including but not limited to damages for loss of goodwill,
      work stoppage, computer failure or malfunction, or any and all
      other commercial damages or losses), even if such Contributor
      has been advised of the possibility of such damages.

   9. Accepting Warranty or Additional Liability. While redistributing
      the Work or Derivative Works thereof, You may choose to offer,
      and charge a fee for, acceptance of support, warranty, indemnity,
      or other liability obligations and/or rights consistent with this
      License. However, in accepting such obligations, You may act only
      on Your own behalf and on Your sole responsibility, not on behalf
      of any other Contributor, and only if You agree to indemnify,
      defend, and hold each Contributor harmless for any liability
      incurred by, or claims asserted against, such Contributor by reason
      of your accepting any such warranty or additional liability.

   END OF TERMS AND CONDITIONS

   APPENDIX: How to apply the Apache License to your work.

      To apply the Apache License to your work, attach the following
      boilerplate notice, with the fields enclosed by brackets "[]"
      replaced with your own identifying information. (Don't include
      the brackets!)  The text should be enclosed in the appropriate
      comment syntax for the file format. We also recommend that a
      file or class name and description of purpose be included on the
      same "printed page" as the copyright notice for easier
      identification within third-party archives.

   Copyright [yyyy] [name of copyright owner]

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.
