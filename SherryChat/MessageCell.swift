import MessagingUI
import SwiftUI
import UIKit

/// 一行消息的画法。TiledView 每行调一次这个 cell。
/// 结构：一行日期（有才画）+ 气泡 + 状态（最后一条自己的才画）。
/// 左滑露时间戳：跟信息 App 一样，滑多少露多少，松手弹回去。
struct MessageCell: TiledCellContent {
    typealias StateValue = Void

    let item: MessageRow
    /// 点引用跳过去的目标行：闪一下（step 70）。
    var isHighlighted: Bool = false
    /// 雪莉改过的名字（step 80，记忆页“更换名称”）：引用块里
    /// 被回那人的名字，改过就显示新的；默认还是“雪莉”。
    var sherryName: String = "雪莉"
    var onVideoTap: (URL) -> Void = { _ in }
    var onFileTap: (URL) -> Void = { _ in }
    /// 点气泡里的引用块 → 跳回原文（step 70）。
    var onQuoteTap: (UUID) -> Void = { _ in }
    /// 右滑气泡 → 回复（step 72，Telegram 的 ChatSwipeToReplyRecognizer）：
    /// ChatView 接，设回复预览栏 + 弹起键盘。
    var onSwipeReply: (ChatMessage) -> Void = { _ in }
    /// 点失败回复下面的“重试”（step 77）：ChatView 接，
    /// 删掉失败那条及之后、用新 id 重新流式。
    var onRetry: (ChatMessage) -> Void = { _ in }
    /// 长按气泡 → Telegram 式菜单（ChatView 接）：只报“哪条被按住了”，
    /// 位置不在这里量——cell 在 TiledView 的 UIKit 宿主里，量的
    /// `.global` 坐标根本不是屏幕坐标，手指位置由 ChatView 根上
    /// 那份 simultaneous 手势量。pressing:true 报开始，false 报结束。
    var onPressStart: (ChatMessage) -> Void = { _ in }
    var onPressEnd: () -> Void = {}

    /// 长按时气泡轻缩的状态（见下面 onLongPressGesture）。
    @State private var isPressing = false
    /// 右滑回复时气泡跟手的距离（step 72）：0…60pt，
    /// 松手弹回 0；超过 60pt 就触发回复。
    @State private var swipeOffset: CGFloat = 0
    /// 状态行换字时的轻弹（1 → 1.18 → 1，0.3s 弹簧）。
    @State private var statusPop: CGFloat = 1

    private let maxRevealOffset: CGFloat = 60

    private static var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }

    func body(context: CellContext<Void>) -> some View {
        let revealOffset = context.cellReveal?.rubberbandedOffset(max: maxRevealOffset) ?? 0
        let message = item.message
        let isFromMe = message.sender == .me

        VStack(spacing: 2) {
            if item.showDate {
                // 日期行（step 85，Telegram 的数）：34pt 高的药丸，
                // 深半透明底 + 白字。原来是居中的小灰字，壁纸一铺就
                // 看不清了（图 44 里“今天 23:49”糊在照片上）；
                // Telegram 的药丸在深浅色、壁纸上都看得清。
                Text(DateLabel.text(for: message.sentAt))
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .background(Color.black.opacity(0.3), in: Capsule())
            }

            HStack(spacing: 0) {
                if isFromMe {
                    Spacer(minLength: 60)
                }

                // 尾巴伸出气泡框外面 5pt，尾巴那侧留 6pt 空，
                // 不然这行的框会把尾巴切掉，气泡看着就像裂开了。
                MessageBubbleView(
                    message: item.message,
                    position: item.position,
                    replyTo: item.replyTo,
                    isHighlighted: isHighlighted,
                    sherryName: sherryName,
                    onVideoTap: onVideoTap,
                    onFileTap: onFileTap,
                    onQuoteTap: onQuoteTap,
                    onPressStart: onPressStart,
                    onPressEnd: onPressEnd
                )
                    .padding(.leading, isFromMe ? 0 : 6)
                    .padding(.trailing, isFromMe ? 6 : 0)
                    // 长按：气泡轻缩到 0.97。菜单不在这里开
                    // （perform 是空的），这里只负责轻缩和上报按住/松开。
                    // 震动不在这里——根上手势认出长按、菜单真要开的那一刻
                    // 才震一次（step 47）：这里震的话，视频/文件气泡
                    // （里面是 Button，吃掉祖先的长按手势）永远震不到，
                    // 还可能和根上那次叠成两下。
                    .scaleEffect(isPressing ? 0.97 : 1)
                    .onLongPressGesture(minimumDuration: 0.45, pressing: { pressing in
                        withAnimation(.easeInOut(duration: 0.15)) { isPressing = pressing }
                        if pressing {
                            onPressStart(message)
                        } else {
                            onPressEnd()
                        }
                    }, perform: {})
                    // 右滑 = 回复（step 72）：气泡跟手右移（最多 60pt），
                    // 左边露一个回复箭头；松手时滑过 60pt 就震一下、
                    // 设回复，没滑够就弹回去。simultaneousGesture：
                    // 别挡着滚动的 pan——列表照常上下滑，手指横着拖
                    // 才跟气泡。左滑不跟（那是库的露时间戳，别抢）。
                    .offset(x: swipeOffset)
                    .overlay(alignment: .leading) {
                        Image(systemName: "arrowshape.turn.up.left.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.secondary)
                            .opacity(min(max(swipeOffset / 60, 0), 1))
                            .offset(x: -28)
                    }
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 10, coordinateSpace: .local)
                            .onChanged { value in
                                if value.translation.width > 0 {
                                    swipeOffset = min(value.translation.width, 60)
                                }
                            }
                            .onEnded { value in
                                if value.translation.width > 60 {
                                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                    onSwipeReply(message)
                                }
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    swipeOffset = 0
                                }
                            }
                    )

                if !isFromMe {
                    Spacer(minLength: 60)
                }
            }
            // 左滑：整行往左让，时间戳从右边跟进来。
            // 不用 .clipped()——时间戳平时透明度是 0，不会露出来；
            // 用了 .clipped() 反而会把气泡的尾巴切掉。
            .offset(x: -revealOffset)
            .overlay(alignment: .trailing) {
                Text(Self.timeFormatter.string(from: message.sentAt))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: maxRevealOffset)
                    .offset(x: maxRevealOffset - revealOffset)
                    .opacity(revealOffset > 4 ? 1 : 0)
            }
            // 系统 contextMenu 撤了，长按走 onLongPress 回调开 Telegram 式菜单。

            // 失败的回复（step 77）：气泡下面一行红字 + 重试，
            // 点整行就重试。失败原因一句大白话，存在 message.failureReason 里。
            if message.status == .failed {
                Button {
                    onRetry(message)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.circle.fill")
                        Text("没回上：\(message.failureReason ?? "再试一次")")
                        Text("重试").fontWeight(.semibold)
                    }
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: isFromMe ? .trailing : .leading)
                    .padding(.trailing, 4)
                }
                .buttonStyle(.plain)
            }

            if item.showStatus, let status = message.status, !ChatTheme.showsInlineTimeAndStatus {
                Text(status.label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 4)
                    // Delivered → Read 用 crossfade + 轻弹，别直接换字；
                    // 两处都得有，不然 cell 一重建就只剩换字。
                    .contentTransition(.opacity)
                    .scaleEffect(statusPop)
                    .animation(.spring(response: 0.35, dampingFraction: 0.75), value: status)
                    .onChange(of: status) { _, _ in
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { statusPop = 1.18 }
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6).delay(0.14)) { statusPop = 1 }
                    }
            }
        }
        .padding(.horizontal, ChatTheme.rowHorizontalPadding)
        .padding(.bottom, bottomPadding)
    }

    /// 组和组之间 / 组里两条之间：主版本 8 / 2pt（信息 App），
    /// 对比版 2 / 0pt（Telegram）——都从 ChatTheme 取。
    /// 靠每行底下的 padding 拉开，不用另外算间距。
    private var bottomPadding: CGFloat {
        item.position == .last || item.position == .single ? ChatTheme.groupSpacing : ChatTheme.withinGroupSpacing
    }
}

/// 一条消息的气泡本体：附件段在上、文字段在下，尾巴只长在最后一段上；
/// 下面挂表情回应角标。列表里的 cell 和长按菜单里抬起来的那份
/// 用同一份画法，别各画各的、免得长相漂移。
/// 回别人的消息时，气泡最上面多一段引用块（2pt 彩条 + 名字一行 +
/// 原文一行，和正文隔 7pt），引用块就是一段 segment，走同一套分段/圆角。
struct MessageBubbleView: View {
    let message: ChatMessage
    let position: BubblePosition
    /// 被回的那条原文（没有就是没回别人）。
    var replyTo: ChatMessage? = nil
    /// 跳转目标行的闪一下（step 70）。
    var isHighlighted: Bool = false
    /// 雪莉改过的名字（step 80）：引用块里被回那人的名字，
    /// 改过就显示新的；默认还是“雪莉”。
    var sherryName: String = "雪莉"
    var onVideoTap: (URL) -> Void = { _ in }
    var onFileTap: (URL) -> Void = { _ in }
    /// 点引用块 → 跳回原文（step 70）。
    var onQuoteTap: (UUID) -> Void = { _ in }
    /// 长按上报（step 47）：视频/文件那两段是 Button，Button 会吃掉
    /// 祖先的 onLongPressGesture，cell 那份手势按在它们身上永远不响，
    /// 所以这两段自己用 simultaneous 手势报上来——只上报，不震动
    /// （震动只有根上开菜单那一次）。文字/图片段走 cell 那份手势。
    var onPressStart: (ChatMessage) -> Void = { _ in }
    var onPressEnd: () -> Void = {}

    private var isFromMe: Bool { message.sender == .me }

    var body: some View {
        VStack(alignment: isFromMe ? .trailing : .leading, spacing: 2) {
            segmentsView
            // 表情回应角标：有表情就画，没有就不画。
            if !message.reactions.isEmpty {
                Text(message.reactions.joined(separator: " "))
                    .font(.body)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color(.systemBackground), in: Capsule())
                    .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
            }
        }
        .frame(maxWidth: ChatTheme.bubbleMaxWidth, alignment: isFromMe ? .trailing : .leading)
        // 跳转目标行闪一下（step 70，Telegram 的 flashIndicators）：
        // 气泡外面一圈淡蓝底，1 秒后 ChatView 把 isHighlighted 清掉、
        // 这里跟着淡出。不是常驻的描边，别当选中态。
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.accentColor.opacity(isHighlighted ? 0.15 : 0))
                .padding(-4)
        )
        .animation(.easeInOut(duration: 0.3), value: isHighlighted)
    }

    /// 一条消息可能有好几段：附件在上，文字在下。
    /// 尾巴只长在最后一段上，段和段之间贴着的角是小半径。
    @ViewBuilder
    private var segmentsView: some View {
        let segments = segments(of: message)
        let positions = segmentPositions(count: segments.count)
        VStack(alignment: isFromMe ? .trailing : .leading, spacing: 2) {
            ForEach(segments.indices, id: \.self) { i in
                segmentView(segments[i], position: positions[i])
            }
        }
    }

    private enum Segment {
        case text(String)
        case media(MediaAttachment)
        /// 引用块（step 39）：被回的那条原文。永远是第一段，
        /// 上面不再有别的段。
        case quote(ChatMessage)
    }

    private func segments(of message: ChatMessage) -> [Segment] {
        var result: [Segment] = []
        if let replyTo {
            result.append(.quote(replyTo))
        }
        result += message.media.map { .media($0) }
        if !message.text.isEmpty {
            result.append(.text(message.text))
        }
        return result
    }

    private func segmentPositions(count: Int) -> [BubblePosition] {
        guard count > 1 else { return [position] }
        switch position {
        case .single:
            return [.first] + Array(repeating: .middle, count: count - 2) + [.last]
        case .first:
            return [.first] + Array(repeating: .middle, count: count - 1)
        case .middle:
            return Array(repeating: .middle, count: count)
        case .last:
            return Array(repeating: .middle, count: count - 1) + [.last]
        }
    }

    /// 文字段的内容：主版本就是正文；对比版（Telegram）在正文后面
    /// 拼上时间，自己发的再拼勾——发出去单勾、对方收到双勾、
    /// 已读双勾变蓝。正在发/失败时不拼勾（失败那行红字在气泡下面）。
    private func textContent(_ text: String) -> Text {
        guard ChatTheme.showsInlineTimeAndStatus else { return Text(text) }
        let time = Self.shortTime.string(from: message.sentAt)
        var result = Text(text)
            + Text("  \(time)").font(.caption2).foregroundStyle(.secondary)
        if isFromMe {
            switch message.status {
            case .delivered:
                result = result + Text(" ✓✓").font(.caption2).foregroundStyle(.secondary)
            case .read:
                result = result + Text(" ✓✓").font(.caption2).foregroundStyle(Color.accentColor)
            default:
                break
            }
        }
        return result
    }

    private static let shortTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    /// 气泡底：单条连续轮廓一次填完（BubbleShape），身子 + 尾巴
    /// 不再分开填两次——交界处没有缝。
    @ViewBuilder
    private func bubbleBackground(isFromMe: Bool, position: BubblePosition) -> some View {
        BubbleShape(isFromMe: isFromMe, position: position)
            .fill(BubbleColors.background(isFromMe: isFromMe))
    }

    @ViewBuilder
    private func segmentView(_ segment: Segment, position: BubblePosition) -> some View {
        switch segment {
        case .text(let text):
            // 对比版（Telegram）：时间 + 状态坐在最后一行行尾，
            // 不在气泡下面另起一行。Text 拼接会当成一段排版，
            // 时间和勾自然落在最后一行末尾。
            textContent(text)
                .font(.body)
                .foregroundStyle(BubbleColors.foreground(isFromMe: isFromMe))
                // 内边距：主版本尾巴侧 18 / 另一侧 14 / 上下 7
                // （MessageKit）；对比版左右 11 / 上下 6（Telegram）。
                .padding(.leading, isFromMe ? ChatTheme.textInsetOtherSide : ChatTheme.textInsetTailSide)
                .padding(.trailing, isFromMe ? ChatTheme.textInsetTailSide : ChatTheme.textInsetOtherSide)
                .padding(.vertical, ChatTheme.textInsetVertical)
                .background(
                    bubbleBackground(isFromMe: isFromMe, position: position)
                )
        case .quote(let quoted):
            // 引用块（Telegram 的数）：左边 2pt 彩条 + 名字一行 +
            // 原文一行，内容左边缩进 11pt，和下面正文隔 7pt。
            // 点引用块跳回原文（step 70）：按 quoted.id 找下标，
            // 库居中滚过去 + 目标行闪一下；原文删了就跳不了，
            // 但这种情况引用块本来就不画（replyTo 现找是 nil）。
            HStack(spacing: 8) {
                Rectangle()
                    .fill(quoted.nameColor)
                    .frame(width: 2)
                VStack(alignment: .leading, spacing: 1) {
                    // 被回的是雪莉时显示改过的名字（step 80）：
                    // quoted.displayName 写死是“雪莉”，改了名字
                    // 还显示旧的就错了。
                    Text(quoted.sender == .sherry ? sherryName : quoted.displayName)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(quoted.nameColor)
                        .lineLimit(1)
                    Text(quoted.snippet)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.leading, 11)
            .padding(.trailing, isFromMe ? ChatTheme.textInsetTailSide : ChatTheme.textInsetOtherSide)
            .padding(.vertical, 6)
            .background(
                bubbleBackground(isFromMe: isFromMe, position: position)
            )
            .padding(.bottom, 5)
            .onTapGesture { onQuoteTap(quoted.id) }
        case .media(let media):
            mediaView(media, position: position)
        }
    }

    @ViewBuilder
    private func mediaView(_ media: MediaAttachment, position: BubblePosition) -> some View {
        switch media {
        case .image(let url, let width, let height):
            LocalImage(url: url, pixelWidth: width, pixelHeight: height)
                .clipShape(BubbleShape(isFromMe: isFromMe, position: position))
        case .video(let url, let thumbnailURL, let duration):
            Button { onVideoTap(url) } label: {
                ZStack {
                    if let thumbnailURL {
                        LocalImage(url: thumbnailURL, pixelWidth: nil, pixelHeight: nil)
                    } else {
                        Color.secondary.opacity(0.2)
                    }
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.white)
                        .shadow(radius: 4)
                    if let duration {
                        Text(formattedDuration(duration))
                            .font(.caption2)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.black.opacity(0.6), in: Capsule())
                            .padding(8)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    }
                }
                .frame(width: 240, height: 180)
            }
            .buttonStyle(.plain)
            .clipShape(BubbleShape(isFromMe: isFromMe, position: position))
            // Button 吃祖先长按：这段自己报按住/松开，只上报不震动。
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.45).onChanged { pressing in
                    if pressing {
                        onPressStart(message)
                    } else {
                        onPressEnd()
                    }
                }
            )
        case .file(let url, let name, let size):
            Button { onFileTap(url) } label: {
                HStack(spacing: 10) {
                    Image(systemName: "doc.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name)
                            .font(.subheadline)
                            .lineLimit(2)
                        if let size {
                            Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 8)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: 260, alignment: .leading)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
            .background(
                bubbleBackground(isFromMe: isFromMe, position: position)
            )
            // Button 吃祖先长按：这段自己报按住/松开，只上报不震动。
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.45).onChanged { pressing in
                    if pressing {
                        onPressStart(message)
                    } else {
                        onPressEnd()
                    }
                }
            )
        }
    }

    private func formattedDuration(_ duration: TimeInterval) -> String {
        let total = Int(duration)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

// MARK: - 正在输入的三个点

/// 对方正在输入：灰气泡里三个点轮着跳（点 8pt、间距 5pt，
/// bounce ±2.5pt、0.5s；气泡本身 1s 轻缩放 1 → 1.04）。
/// 尾巴就是 BubbleShape 那只钩形尾巴——左下角那两个小尾巴圆
/// （原来 7pt 和 11pt）删了：图 37 量过，它们在深色下是两颗
/// 挂在气泡下面的点，只贴着气泡一条细边，看着就是第二层；
/// Dolos 从 11:44 起说的“两层”就是它们（step 69）。
/// 它们是信息 App 真有的细节（图 07 里也有），但深色下读着
/// 是散点不是尾巴，留着就是第二层，不如不要。
struct TypingBubble: View {
    @State private var animate = false
    @State private var breathe = false

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3) { i in
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 8, height: 8)
                    .offset(y: animate ? -2.5 : 2.5)
                    .opacity(animate ? 1 : 0.5)
                    .animation(
                        .easeInOut(duration: 0.5)
                            .repeatForever(autoreverses: true)
                            .delay(Double(i) * 0.15),
                        value: animate
                    )
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            BubbleShape(isFromMe: false, position: .single)
                .fill(Color(.systemGray5))
        )
        .scaleEffect(breathe ? 1.04 : 1)
        .animation(
            .easeInOut(duration: 1).repeatForever(autoreverses: true),
            value: breathe
        )
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        // 进场/出场都交给库（typingIndicator 的 0.55s 滑出 + 滚动带入），
        // 这里不挂自己的 transition——两份动会叠在一起。
        // 三个点的轮跳和气泡的呼吸是里面的常驻动效，不是进场动画。
        .onAppear {
            animate = true
            breathe = true
        }
    }
}

// MARK: - 本地图片

/// 本地临时文件的图。AsyncImage 不吃 file:// 地址，这里自己读。
struct LocalImage: View {
    let url: URL
    let pixelWidth: Int?
    let pixelHeight: Int?
    var fixedSize: CGSize? = nil

    @State private var image: UIImage? = nil

    private var displaySize: CGSize {
        if let fixedSize { return fixedSize }
        let maxWidth: CGFloat = 240
        let maxHeight: CGFloat = 320
        guard let w = pixelWidth, let h = pixelHeight, w > 0, h > 0 else {
            return CGSize(width: maxWidth, height: 180)
        }
        let scale = min(maxWidth / CGFloat(w), maxHeight / CGFloat(h), 1)
        return CGSize(width: CGFloat(w) * scale, height: CGFloat(h) * scale)
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.secondary.opacity(0.2)
            }
        }
        .frame(width: displaySize.width, height: displaySize.height)
        // 地址变了就重新读（step 83）：.task 不带 id 只在第一次出现时跑，
        // 头像换第二张时地址还是同一份不会重读——现在每次换头像文件名
        // 都带 uuid（AgentProfile.setAvatar），地址变了这里跟着重读。
        .task(id: url) {
            image = nil
            image = await Task.detached { UIImage(contentsOfFile: url.path) }.value
        }
    }
}
