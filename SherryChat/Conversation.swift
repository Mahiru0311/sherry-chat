import Foundation
import Observation
import SwiftUI
import UIKit

/// 谁发的。第一阶段只有一个会话：我，和 Sherry。
enum Sender: Hashable, Equatable, Sendable {
    case me
    case sherry
}

/// 自己发出去那条的状态，画在最后一条自己消息下面。
/// 文案跟原来库版本里的一样（Delivered / Read）。
/// failed 是接 AI 后加的：对方那条回复没回上（断网、Key 错、
/// 超时……），标失败、可重试，别静默丢掉。
enum MessageKind: Hashable, Equatable, Sendable {
    case text
    case toolCall(toolID: String, name: String)
    case toolResult(toolID: String, name: String, isError: Bool)
}

enum DeliveryStatus: Hashable, Equatable, Sendable {
    case sending
    case delivered
    case read
    case failed

    var label: String {
        switch self {
        case .sending: return "Sending…"
        case .delivered: return "Delivered"
        case .read: return "Read"
        case .failed: return "Failed"
        }
    }
}

/// 一条消息带的附件。地址都是本地文件（选完拷到临时目录），
/// 分三种：照片、视频、文件。
enum MediaAttachment: Identifiable, Hashable, Equatable, Sendable {
    case image(url: URL, width: Int?, height: Int?)
    case video(url: URL, thumbnailURL: URL?, duration: TimeInterval?)
    case file(url: URL, name: String, size: Int64?)

    var id: String {
        switch self {
        case .image(let url, _, _): return url.absoluteString
        case .video(let url, _, _): return url.absoluteString
        case .file(let url, _, _): return url.absoluteString
        }
    }
}

/// 一条消息。id 一旦生成就不再变。
/// init 是手写的——让调用方能传 id 和 replyToID。
struct ChatMessage: Identifiable, Hashable, Equatable {
    let id: UUID
    var text: String
    var sender: Sender
    var sentAt: Date
    var kind: MessageKind
    var status: DeliveryStatus?
    var media: [MediaAttachment]
    /// 长按菜单里点的表情回应（Telegram 的做法：表情贴在气泡角上，
    /// 再点同一个就拿掉）。本地假对话，只存在内存里，不上网。
    var reactions: [String] = []
    /// 这条是回哪条的：只存被回那条的 id，不存全文快照——
    /// 气泡里的引用块每次都按这个 id 去 conversation 里现找原文，
    /// 原文找不到了引用块就不画。
    var replyToID: UUID? = nil
    /// 这条是失败的回复时，失败的原因（一句大白话，画在气泡下面）。
    /// 只有 status == .failed 时才有值。
    var failureReason: String? = nil

    init(
        id: UUID = UUID(),
        text: String,
        sender: Sender,
        sentAt: Date,
        kind: MessageKind = .text,
        status: DeliveryStatus? = nil,
        media: [MediaAttachment] = [],
        replyToID: UUID? = nil,
        failureReason: String? = nil
    ) {
        self.id = id
        self.text = text
        self.sender = sender
        self.sentAt = sentAt
        self.kind = kind
        self.status = status
        self.media = media
        self.replyToID = replyToID
        self.failureReason = failureReason
    }
}

/// 引用块和回复预览栏用的显示字段：名字是被回那人的名字色
/// （我们只有两个人：我蓝、雪莉绿）。
extension ChatMessage {
    var displayName: String {
        sender == .me ? "我" : "Sherry"
    }

    var nameColor: Color {
        sender == .me ? .blue : .green
    }

    /// 引用块/预览栏里那一行原文：有字就是字；没字（纯附件）
    /// 就按第一件附件说“照片/视频/文件名”。
    var snippet: String {
        if !text.isEmpty { return text }
        guard let first = media.first else { return "（空消息）" }
        switch first {
        case .image: return "照片"
        case .video: return "视频"
        case .file(_, let name, _): return name
        }
    }
}

/// 本地假对话：第一阶段的“对方”就是它，不接任何网络。
/// 行为照着原来库版本：发出 → sending → 600ms 后 delivered
/// → 900ms 后 read → 对方 typing 1800ms → append 一条假回复。
@MainActor @Observable
final class Conversation {
    var messages: [ChatMessage]
    var isTyping = false
    /// 真回复正在流式往里长字（step 79）：第一个 token 到了
    /// 置 true，流完/失败置 false。ChatView 看它决定流式时
    /// 要不要跟着往下滑——只在长字时跟，append 那一下不管。
    var isStreamingReply = false

    private var replies: [String]

    init(
        messages: [ChatMessage]? = nil,
        replies: [String]? = nil
    ) {
        self.messages = messages ?? Self.sampleMessages()
        self.replies = replies ?? Self.sampleReplies()
    }

    /// id 由调用方传进来（默认新生成）。
    /// replyToID 是这条回哪条的：ChatView.send() 从 replyingTo 里传进来。
    /// profile 是个人页那份 AgentProfile（ChatView 从 environment 里传）：
    /// 配齐了（地址 + 模型 + Key）就走真 AI 流式，没配齐就走假回复。
    func send(_ text: String?, _ media: [MediaAttachment], id: UUID = UUID(), replyToID: UUID? = nil, profile: AgentProfile? = nil) async {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty || !media.isEmpty else { return }

        let message = ChatMessage(id: id, text: trimmed, sender: .me, sentAt: .now, status: .sending, media: media, replyToID: replyToID)
        messages.append(message)
        // 发出去一个轻震动（Dolos 2026-11-18：对方发来消息时
        // 应该有震动感；自己发出去也轻震一下，跟信息 App 一样）。
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        // 换头像 / 换名字（记忆页那两个按钮立的 intent，step 80）：
        // 按钮只是立 flag，内容是这条消息——发图换头像、发字换名字。
        // 本地立刻生效；AI 那边只收到一句 system 备注来确认（不改
        // 这条消息本身、不往历史里加东西）；没配 API 时假回复直接
        // 说确认的话。没发对东西（换头像没发图、换名字没打字）
        // flag 就留着，等下一条。
        var systemNote: String? = nil
        var fakeConfirmation: String? = nil
        if profile?.pendingAvatarChange == true {
            let imageURL = media.compactMap({ item -> URL? in
                if case .image(let url, _, _) = item { return url }
                return nil
            }).first
            if let imageURL, profile?.setAvatar(from: imageURL) == true {
                profile?.pendingAvatarChange = false
                // step 83：备注得是直接指令，不能是“请自然地确认一下”——
                // 太软了，模型回的是反问（“你是不是给我换了新头像？
                // 我瞅瞅~”），Dolos 说它自己都不知道要干吗。
                systemNote = "用户刚刚把你的头像换成了一张新图片，头像已经换好了。你要做的是：用一句话自然地告诉对方头像已经换好了，可以简单说一句新头像的感觉。不要反问，不要问“是不是换了”，不要说“我瞅瞅”“让我看看”。"
                fakeConfirmation = "头像换好啦，新头像好看吗？"
            } else if imageURL != nil {
                // 发了图但拷不动：告诉用户，别悄悄留着 flag
                // 等下一条误触发。
                profile?.avatarChangeError = "头像没换上，再试一次"
                profile?.pendingAvatarChange = false
            }
            // 没发图（只发了字）：flag 留着，等下一条带图的（原有行为）。
        }
        if profile?.pendingNameChange == true, !trimmed.isEmpty {
            let newName = String(trimmed.prefix(20))
            profile?.setDisplayName(newName)
            profile?.pendingNameChange = false
            systemNote = "用户刚刚把你的名字改成了「\(newName)」，名字已经改好了。从现在起用新名字称呼自己，用一句话确认名字已经改好了。不要反问，不要问“是不是改了”。"
            fakeConfirmation = "好，我现在叫「\(newName)」啦，记住了。"
        }

        try? await Task.sleep(for: .milliseconds(600))
        setStatus(.delivered, for: message.id)

        // 真假两条路的时间线前面都一样：发出 → delivered → read。
        // 假回复那条还有个老规矩：假回复池空了就停在 delivered，
        // 不读、不打字、不回（原来就这样，别改）——但换头像/换名字
        // 的确认不在池子里，有确认话就照样回。
        if let profile, profile.isConfigured, let key = profile.apiKey() {
            try? await Task.sleep(for: .milliseconds(900))
            setStatus(.read, for: message.id)
            await realReply(profile: profile, apiKey: key, systemNote: systemNote)
        } else {
            if fakeConfirmation == nil {
                guard !replies.isEmpty else { return }
            }

            try? await Task.sleep(for: .milliseconds(900))
            setStatus(.read, for: message.id)
            await fakeReply(confirmation: fakeConfirmation)
        }
    }

    /// 假回复（没配 API 时的老路，一字不动）：
    /// 对方 typing 1800ms → 关三点气泡、append 假回复必须同一笔改动
    /// （step 67）：库在同一次 updateUIView 里先把三点气泡那行藏起来
    /// （alpha 0）、再插真消息，列表只按净高度差滑一次。
    /// 以前中间等 650ms，是等库把三点气泡滑出去（0.55s 滚动）：
    /// 那次滚动让列表下滑 42pt，随后 append 又让列表上滑 44pt，
    /// 净走 2pt 却动了两趟——这就是 Dolos 说的“两层”。
    /// 库那边的退出滚动已删掉（TiledView.updateTypingIndicatorVisibility），
    /// 这里再等 650ms 只会多一段三点气泡干等着的时间。
    /// confirmation 是换头像/换名字时的确认话（step 80）：
    /// 有它就不从假回复池子里拿，直接说确认的话。
    private func fakeReply(confirmation: String? = nil) async {
        isTyping = true

        try? await Task.sleep(for: .milliseconds(1800))
        isTyping = false
        if let confirmation {
            messages.append(ChatMessage(text: confirmation, sender: .sherry, sentAt: .now))
        } else {
            messages.append(ChatMessage(text: replies.removeFirst(), sender: .sherry, sentAt: .now))
        }
        // 对方回过来一个通知式震动（success），跟自己发出去的
        // 轻震动不是同一种手感——两边到手的消息各有各的震动。
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// 真回复（配齐了 API 才走）：三点气泡亮着发请求，
    /// 第一个 token 到之前 typing 一直亮；token 一到就 append
    /// 一条空的 sherry 消息（新 id），之后每个 chunk 都改同一条
    /// 的文本，id 不变、气泡在原地长高。
    /// 关三点气泡、append 空回复必须同一笔改动（跟假回复那条
    /// 同一个道理，step 67/68）：不然列表先滑一下再插一行，
    /// 又是两层。
    /// systemNote 是换头像/换名字时的一句备注（step 80）：
    /// 只拼进这一次请求的 system prompt，让 AI 确认一下，
    /// 不进历史、不改消息。
    /// 打字机（step 81）：服务商经常一大段一大段地发，
    /// 直接拼上去就是卡一下、整段蹦出来。收到的字先攒在
    /// typewriterReceived 里，另一路每 80ms 往气泡里吐
    /// 几个字（typewriterTask，step 83 从 30ms 改成 50ms，
    /// step 84 再改成 80ms），看着像一个字一个字打出来的。
    private var typewriterReceived = ""
    private var typewriterShown = 0
    private var typewriterDone = false
    private var typewriterTask: Task<Void, Never>?

    /// 打字机那一路：每 80ms 吐 pending/8 个字，至少 1、
    /// 最多 80——短回复像打字一样一个一个出来，长的一大段
    /// 也在一秒上下吐完，不会爬半天。原来 50ms 一吐，
    /// 气泡每 50ms 重排一次（库里 performBatchUpdates +
    /// reconfigureItems + 重新布局），跟滑又 120ms 跳一次，
    /// 两路各走各的、动画看着卡（step 84，Dolos：气泡动画很卡）；
    /// 80ms 一吐速度一样（每秒最多还是约 1000 字），
    /// UI 更新少了四成，剩下的跟滑交给弹簧每帧自己追。
    /// 流完了（typewriterDone）且吐干净了就停；中途失败或重试直接取消，留着已显示的字。
    private func typewriterStart(replyID: UUID) {
        typewriterTask?.cancel()
        typewriterReceived = ""
        typewriterShown = 0
        typewriterDone = false
        typewriterTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(80))
                guard !Task.isCancelled else { return }
                let pending = typewriterReceived.count - typewriterShown
                if pending <= 0 {
                    if typewriterDone { return }
                    continue
                }
                let step = min(max(pending / 8, 1), 80)
                typewriterShown += step
                if let index = messages.firstIndex(where: { $0.id == replyID }) {
                    messages[index].text = String(typewriterReceived.prefix(typewriterShown))
                }
            }
        }
    }

    private func typewriterStop(drain: Bool) async {
        if drain {
            typewriterDone = true
            await typewriterTask?.value
        } else {
            typewriterTask?.cancel()
            await typewriterTask?.value
        }
        typewriterTask = nil
    }
    private func realReply(profile: AgentProfile, apiKey: String, systemNote: String? = nil) async {
        isTyping = true
        let history = Self.apiMessages(
            from: messages,
            systemPrompt: profile.systemPrompt,
            memoryContext: profile.memoryContext,
            extraSystemNote: systemNote
        )
        let stream = await OpenAIClient().streamChat(
            baseURL: profile.normalizedBaseURL,
            model: profile.modelName,
            apiKey: apiKey,
            messages: history
        )
        var replyID: UUID?
        do {
            for try await chunk in stream {
                if replyID == nil {
                    let id = UUID()
                    replyID = id
                    isStreamingReply = true
                    isTyping = false
                    messages.append(ChatMessage(id: id, text: "", sender: .sherry, sentAt: .now))
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    typewriterStart(replyID: id)
                }
                // 字先攒进打字机，不直接拼上气泡——
                // 服务商一整段发过来时，直接拼就是整段蹦出来。
                typewriterReceived += chunk
            }
            // 流完了：等打字机把剩下的字吐完（还是一个一个出来，
            // 不是一跳到底），再关 isStreamingReply。
            await typewriterStop(drain: true)
            isStreamingReply = false
        } catch is CancellationError {
            await typewriterStop(drain: false)
            isStreamingReply = false
            // 重试把那条消息删了、流被停掉：不是失败，别标。
            return
        } catch {
            await typewriterStop(drain: false)
            isStreamingReply = false
            // 失败原因一句大白话，画在气泡下面，可重试。
            let reason = (error as? AIError)?.reason ?? "没回上，检查网络或设置再试"
            isTyping = false
            if let id = replyID,
               let index = messages.firstIndex(where: { $0.id == id }) {
                // 已经流了一半：留着已到的字，标失败、可重试。
                messages[index].status = .failed
                messages[index].failureReason = reason
            } else {
                // 第一个字之前就失败了：插一条空的失败消息，
                // 失败原因和重试入口画在气泡下面。
                messages.append(ChatMessage(
                    text: "",
                    sender: .sherry,
                    sentAt: .now,
                    status: .failed,
                    failureReason: reason
                ))
            }
        }
    }

    /// 重试一条失败的回复（chatgpt-ios-ui 的做法）：删掉失败那条
    /// 及之后的消息，用新 id 重新流式。失败只能发生在配好的情况下，
    /// 所以这里配齐了才重试，没配好什么都不做。
    func retryFailedReply(id: UUID, profile: AgentProfile?) async {
        guard let index = messages.firstIndex(where: { $0.id == id }),
              messages[index].status == .failed,
              let profile, profile.isConfigured, let key = profile.apiKey()
        else { return }
        messages.removeSubrange(index...)
        await realReply(profile: profile, apiKey: key)
    }

    /// 发给 API 的历史：SOUL 当 system prompt，记忆拼在后面；
    /// 然后按顺序 user/assistant。第一版只发文字：空消息
    /// （失败那条、纯附件）不发，附件本身不发——PLAN 第一阶段
    /// 就没要求附件进 AI，别为了附件拖住第一版。
    /// extraSystemNote 是换头像/换名字时的一句备注（step 80）：
    /// 只拼进这一次请求的 system prompt，让 AI 确认一下。
    private static func apiMessages(
        from messages: [ChatMessage],
        systemPrompt: String,
        memoryContext: String,
        extraSystemNote: String? = nil
    ) -> [ChatAPIMessage] {
        var result: [ChatAPIMessage] = []
        var system = systemPrompt
        if !memoryContext.isEmpty {
            system += "\n\n以下是你记得的关于对方的事：\n" + memoryContext
        }
        if let note = extraSystemNote, !note.isEmpty {
            system += "\n\n" + note
        }
        if !system.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            result.append(ChatAPIMessage(role: "system", content: system))
        }
        for message in messages {
            guard !message.text.isEmpty else { continue }
            result.append(ChatAPIMessage(
                role: message.sender == .me ? "user" : "assistant",
                content: message.text
            ))
        }
        return result
    }

    private func setStatus(_ status: DeliveryStatus, for id: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        // 状态变化要包在 withAnimation 里，不然 Delivered → Read
        // 只是换字，没有淡入淡出。0.35s easeInOut，
        // 跟 cell 里那行字的 contentTransition 是一对。
        withAnimation(.easeInOut(duration: 0.35)) {
            messages[index].status = status
        }
    }

    /// 表情回应开关（长按菜单里点一下贴上，再点一下拿掉）。
    /// 同一个表情只贴一次，顺序按点的先后。
    func toggleReaction(_ reaction: String, for id: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            if let i = messages[index].reactions.firstIndex(of: reaction) {
                messages[index].reactions.remove(at: i)
            } else {
                messages[index].reactions.append(reaction)
            }
        }
    }

    /// 删除一条消息（step 46，微信长按菜单“删除”）。
    /// 被删那条是别人引用的原文时，引用块按 id 现找、找不到就不画，
    /// 不会留空引用。
    func deleteMessage(id: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        withAnimation(.easeInOut(duration: 0.25)) {
            messages.remove(at: index)
        }
    }

    // MARK: - 示例数据（跟原来库版本里的一模一样）

    static func sampleMessages() -> [ChatMessage] {
        let now = Date()
        return [
            ChatMessage(
                text: "嗨，毛毛，我是雪莉。",
                sender: .sherry,
                sentAt: now.addingTimeInterval(-360),
                status: nil
            ),
            ChatMessage(
                text: "这是咱们第一个 App 的第一个聊天页面，先用假回复顶着，真 AI 还在路上。",
                sender: .sherry,
                sentAt: now.addingTimeInterval(-300),
                status: nil
            ),
            ChatMessage(
                text: "收到，页面看起来像信息 App 吗？",
                sender: .me,
                sentAt: now.addingTimeInterval(-120),
                status: .read
            ),
        ]
    }

    static func sampleReplies() -> [String] {
        [
            "收到啦，假回复也是回复，先跑通这一圈再说。",
            "气泡、键盘、滚动都对上号了，咱们再往下走。",
            "嘿嘿，名侦探上线，先记下这条：页面稳了，才接 AI。",
        ]
    }
}

/// 一行要画的东西：消息本身 + 它在组里的位置 + 要不要画日期 + 要不要画状态。
/// ChatView 一次算好，交给 TiledView；位置变了（新消息进来）就重新算。
/// replyTo 是这条回的那条原文（step 39）：按 message.replyToID
/// 在同一个 messages 里现找，不存快照（Telegram 的做法：
/// 引用块每次重读原文）。原文找不到了就是 nil，引用块不画。
struct MessageRow: Identifiable, Equatable {
    let message: ChatMessage
    let position: BubblePosition
    let showDate: Bool
    let showStatus: Bool
    let replyTo: ChatMessage?

    var id: ChatMessage.ID { message.id }
}

/// 按发送者和时间把连续消息排成组，算出每条在组里的位置。
/// 同一个人连续发的算一组；超过 60 分钟没说话，下一条就是新一组，
/// 上面画一行日期。状态只画在最后一条自己消息的下面。
enum MessageGrouping {
    static func rows(for messages: [ChatMessage]) -> [MessageRow] {
        var rows: [MessageRow] = []
        for (index, message) in messages.enumerated() {
            let previous = index > 0 ? messages[index - 1] : nil
            let next = index + 1 < messages.count ? messages[index + 1] : nil

            // 分组断点是 600 秒（step 74，Telegram 的 chatMessageMerge：
            // 同人同向、不到 10 分钟合并一组）：隔了十分钟没说话，
            // 下一条就是新一组，尾巴和圆角都得重新算。
            // 日期行是换天才画，那是另一回事。
            let startsGroup = previous.map {
                $0.sender != message.sender || message.sentAt.timeIntervalSince($0.sentAt) > 600
            } ?? true
            let endsGroup = next.map {
                $0.sender != message.sender || $0.sentAt.timeIntervalSince(message.sentAt) > 600
            } ?? true

            let position: BubblePosition
            switch (startsGroup, endsGroup) {
            case (true, true): position = .single
            case (true, false): position = .first
            case (false, true): position = .last
            case (false, false): position = .middle
            }

            // 日期只画在第一条、和上一条不是同一天的那条上面（step 73，
            // Telegram §2.2：按换天画）。光换人说话不画日期——
            // 信息 App 也是这样的。
            let showDate = previous.map {
                !Calendar.current.isDate($0.sentAt, inSameDayAs: message.sentAt)
            } ?? true

            // 状态只画在最后一条自己的消息下面，而且那条得是真发出去的。
            let showStatus = message.sender == .me && endsGroup && message.status != nil

            rows.append(MessageRow(
                message: message,
                position: position,
                showDate: showDate,
                showStatus: showStatus,
                replyTo: message.replyToID.flatMap { id in messages.first(where: { $0.id == id }) }
            ))
        }
        return rows
    }
}
