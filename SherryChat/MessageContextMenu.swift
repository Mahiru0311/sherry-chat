import SwiftUI
import UIKit

/// 长按气泡的微信式菜单（step 46，照 Dolos 发的微信截图改）：
/// 上面一排快捷表情（👍 ❤️ 😂 😮 😢 + ⊕ 更多），中间是那条消息
/// 从列表里“抬”出来（后面全屏变暗，点暗处收起），下面是动作列表
/// （回复 / 复制 / 删除，Dolos 2026-11-18：转发和星标都不要，只留这三行）。
/// - 表情行：点一下贴到气泡角上，再点拿掉；⊕ 展开第二排更多表情。
/// - 删除：真删（Conversation.deleteMessage），被删那条是别人
///   引用的原文时，引用块按 id 现找、找不到就不画。
/// - 复制：有文字才显示。
///
/// step 84（Dolos：弹窗能不能都用官方系统的）：这块刻意留在手写，
/// 没换成系统 contextMenu——系统菜单装不下快捷表情行、也抬不起
/// 气泡，而表情行和抬起来的气泡正是 Dolos 当初照微信截图要的样子；
/// 换成系统菜单等于把她要的功能删了。手写归手写，系统的交互行为
/// 要补齐：点暗处收起（本来就有）、划一下收起（step 84 加的，
/// 像系统菜单那样划走就收）、打开时震一下（根手势 step 47）、
/// 出现是弹簧。头像铅笔菜单和加号菜单都换成系统 Menu 了（那里
/// 只有纯动作行，系统装得下）。
///
/// 位置：抬起来的气泡不按 cell 里量的尺寸摆——cell 在 TiledView 的
/// UIKit 宿主里，量的尺寸和位置都不可信。它是一行和 cell 里
/// 一模一样的布局（同样的 Spacer + 尾巴留空 + 行 padding +
/// maxWidth 280），放在满宽的 HStack 里，只按纵向摆——横向它自己
/// 就落在原气泡的位置上，不用算。它的 frame 在 overlay 里自己量
/// （主层级、`.named("chat")` 坐标系，这里的量是真的），表情行和
/// 菜单再按这个量出来的中心横向对齐。纵向以手指为中心，整组贴边时
/// 一起移，不出屏幕。
struct MessageContextMenuOverlay: View {
    let message: ChatMessage
    let position: BubblePosition
    /// 长按时手指在 "chat" 坐标系里的位置（ChatView 根上那份
    /// simultaneous 手势量的，和这个 overlay 同一个坐标系）。
    let anchor: CGPoint
    /// 被回的那条原文（step 39）：抬起来的气泡和列表里那条
    /// 是同一份画法，引用块也要一样有。
    var replyTo: ChatMessage? = nil
    var onToggleReaction: (String) -> Void
    var onReply: () -> Void
    var onCopy: () -> Void
    var onDelete: () -> Void
    var onDismiss: () -> Void

    @State private var appeared = false
    /// ⊕ 点开更多表情。
    @State private var showMoreEmoji = false
    /// 抬起来的气泡在 overlay 里自己量的 frame（主层级，真的）：
    /// 表情行和菜单按它的中心横向对齐。第一帧还没量出来时是 .zero，
    /// 先按发信方向估一个中心。
    @State private var bubbleFrame: CGRect = .zero

    /// 微信那排快捷表情：五个 + ⊕（step 61：Dolos 说点 ⊕ 还是裁切，
    /// 让删掉不必要的表情、把面板收窄——原来七个 + ⊕ 是 354pt 宽，
    /// 390pt 的屏上只剩 12pt 边，看着就像贴着边、像被裁了）。
    private let quickReactions = ["👍", "❤️", "😂", "😮", "😢"]
    /// ⊕ 展开的第二排：六个，正好一排。
    private let moreReactions = ["🎉", "🤔", "😍", "😭", "🤝", "👏"]

    var body: some View {
        GeometryReader { proxy in
            let screen = proxy.size
            let menuWidth = min(300, screen.width - 32)
            let menuHeight: CGFloat = menuRowCount * 52 + 12
            // 表情行高：单排 52；⊕ 展开后多一排 48 + 间隔 8。
            let reactionHeight: CGFloat = showMoreEmoji ? 108 : 52
            // 气泡高：overlay 里量出来的真数；还没量出来先估 64，
            // 量出来立刻纠正（同一布局 pass，不会闪一下再跳）。
            let bubbleHeight = bubbleFrame.height > 0 ? bubbleFrame.height : 64
            // 气泡纵向以手指为中心；表情行在上、菜单在下，
            // 贴边时整组一起移，不出屏幕。
            // 菜单开着时整屏是暗的，顶栏/输入栏区也可以借——
            // 只要不出屏幕边就行，不用再躲顶栏和底栏。
            // 注意：这里全是 let——ViewBuilder 里不能写 var 再改，
            // 赋值语句会被当成视图、编不过。移位先算出来，再一次加进三个值里。
            let bubbleCenterY0 = min(max(anchor.y, bubbleHeight / 2 + 8), screen.height - bubbleHeight / 2 - 8)
            let reactionY0 = bubbleCenterY0 - bubbleHeight / 2 - 8 - reactionHeight / 2
            let menuY0 = bubbleCenterY0 + bubbleHeight / 2 + 8 + menuHeight / 2
            let shiftDown = max(0, 8 - (reactionY0 - reactionHeight / 2))
            let shiftUp = max(0, (menuY0 + menuHeight / 2) - (screen.height - 8))
            let shift = shiftDown - shiftUp
            let bubbleCenterY = bubbleCenterY0 + shift
            let reactionY = reactionY0 + shift
            let menuY = menuY0 + shift
            // 表情行和菜单横向以气泡中心为准，贴边时夹在屏幕里。
            // 气泡中心是 overlay 里量出来的；没量出来时按发信方向估：
            // 对方发的气泡中心约在 18 + 280/2，自己发的约在屏宽 - 18 - 140。
            let bubbleCenterX = bubbleFrame.width > 0
                ? bubbleFrame.midX
                : (message.sender == .me ? screen.width - 158 : 158)
            // 夹的时候按最宽的那块算。表情面板永远是 270pt 宽——
            // 快捷行 6 个 40pt 钮（5 个表情 + ⊕）+ 间距 + 两边 padding；
            // ⊕ 展开的 6 个表情正好一排、同样 270pt，不改变板宽。
            // 390pt 的屏居中时两边各留 60pt，不再靠限位硬夹。
            // ——step 61 的“270pt”在真机上没成立，截图 35 量出来
            // 面板约 352pt 宽、左沿贴着屏幕边（0pt）。根因不是算错
            // 数，是展开那排用的 LazyVGrid：lazy 容器会贪心地吃掉
            // 父层给的全部宽度（这里是整个 overlay 的 393pt 宽），
            // 所以面板宽度根本不是内容决定的，是容器撑满的；
            // 限位按 300pt 夹、中心约 165pt，352pt 宽的板子左沿
            // 就落在 -11pt、被屏幕裁了。修法：第二排改回普通 HStack
            // （6 个固定项不需要 lazy 网格），整块板再加
            // .fixedSize(horizontal: true) 兜底——宽度永远由内容定，
            // 再宽的容器也撑不满它。之前 354pt 宽时限位按 354 算、
            // 只剩 12pt 边（step 60），截图 34 里看着还是贴着左沿、
            // 像被裁了，也是同一个毛病。
            let reactionWidth: CGFloat = 270
            let panelWidth = max(menuWidth, reactionWidth)
            let centerX = min(max(bubbleCenterX, panelWidth / 2 + 12), screen.width - panelWidth / 2 - 12)

            ZStack {
                // 全屏变暗，点暗处收起（微信的 dim 背景）。
                // 划一下也收起（step 84）：系统菜单划走就收，
                // 这里也一样——划的距离够了就收，点按不受影响。
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .onTapGesture { onDismiss() }
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 20)
                            .onEnded { _ in onDismiss() }
                    )

                // 抬起来的气泡：和 cell 里同一行布局，放在满宽 HStack 里，
                // 横向自己落在原气泡的位置上，只摆纵向（手指的 y）。
                // 抬起来 = 放大 1.02 + 阴影；原来那个在暗处下面，
                // 被抬起来的这份不透明地盖住，不会看着像两份。
                HStack(spacing: 0) {
                    if message.sender == .me {
                        Spacer(minLength: 60)
                    }
                    MessageBubbleView(message: message, position: position, replyTo: replyTo)
                        .padding(.leading, message.sender == .me ? 0 : 6)
                        .padding(.trailing, message.sender == .me ? 6 : 0)
                        .scaleEffect(appeared ? 1.02 : 0.97)
                        .shadow(color: .black.opacity(0.25), radius: 16, y: 8)
                        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .named("chat")) }) { frame in
                            bubbleFrame = frame
                        }
                    if message.sender != .me {
                        Spacer(minLength: 60)
                    }
                }
                .padding(.horizontal, 12)
                .position(x: screen.width / 2, y: bubbleCenterY)

                // 快捷表情行：微信是白色圆角矩形面板，不是拉满的胶囊——
                // 胶囊一拉长就显硬、显丑（Dolos 2026-11-18）。圆角 18pt，
                // 展开的网格也在这同一块面板里长，不再变回椭圆。
                // 底是 iOS 26 原生液态玻璃（`.glassEffect()`，一层），
                // 不是实色白底——截图 30 里两块板子都是死白，Dolos 问
                // “图一的液态玻璃效果呢”。代码里已经没有 Capsule 了
                // （grep 过），椭圆的印象就是这块死白大板子。
                // 玻璃只属于这两块面板，抬起来的气泡还是实色。
                VStack(spacing: 8) {
                    HStack(spacing: 2) {
                        ForEach(quickReactions, id: \.self) { emoji in
                            reactionButton(emoji)
                        }
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showMoreEmoji.toggle()
                            }
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 40, height: 40)
                                .background(Color(.systemGray5), in: Circle())
                        }
                        .buttonStyle(.plain)
                    }
                    if showMoreEmoji {
                        // 第二排是普通 HStack，不是 LazyVGrid——
                        // LazyVGrid 会贪心地吃掉父层给的全部宽度
                        // （截图 35：展开后整块板约 352pt 宽、左沿贴边），
                        // 6 个固定项不需要 lazy 网格。
                        HStack(spacing: 2) {
                            ForEach(moreReactions, id: \.self) { emoji in
                                reactionButton(emoji)
                            }
                        }
                    }
                }
                // 宽度永远由内容定：.fixedSize 兜底，免得将来哪个
                // 孩子又贪心地把板子撑满屏幕。
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .glassPanelFill(cornerRadius: 18)
                .shadow(color: .black.opacity(0.2), radius: 8, y: 2)
                .position(x: centerX, y: reactionY)

                // 动作菜单：只留三行——回复 / 复制 / 删除。
                VStack(spacing: 0) {
                    contextMenuRow(title: "回复", systemImage: "arrowshape.turn.up.left") {
                        onDismiss()
                        onReply()
                    }
                    if !message.text.isEmpty {
                        Divider()
                            .padding(.leading, 52)
                        contextMenuRow(title: "复制", systemImage: "doc.on.doc") {
                            onDismiss()
                            onCopy()
                        }
                    }
                    Divider()
                        .padding(.leading, 52)
                    contextMenuRow(title: "删除", systemImage: "trash", destructive: true) {
                        onDismiss()
                        onDelete()
                    }
                }
                .padding(.vertical, 6)
                .frame(width: menuWidth)
                .glassPanelFill(cornerRadius: 20)
                .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
                .position(x: centerX, y: menuY)
            }
            .opacity(appeared ? 1 : 0)
            .onAppear {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { appeared = true }
            }
        }
    }

    /// 菜单行数：回复、删除两行是一直有的，有文字再加复制一行。
    private var menuRowCount: CGFloat {
        message.text.isEmpty ? 2 : 3
    }

    private func reactionButton(_ emoji: String) -> some View {
        let selected = message.reactions.contains(emoji)
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                onToggleReaction(emoji)
            }
        } label: {
            Text(emoji)
                .font(.system(size: 28))
                .frame(width: 40, height: 40)
                .background(
                    selected ? Color.blue.opacity(0.18) : Color.clear,
                    in: Circle()
                )
                .scaleEffect(selected ? 1.12 : 1)
        }
        .buttonStyle(.plain)
    }

    private func contextMenuRow(
        title: String,
        systemImage: String,
        destructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: systemImage)
                    .font(.system(size: 18))
                    .foregroundStyle(destructive ? .red : .secondary)
                    .frame(width: 28)
                Text(title)
                    .font(.body)
                    .foregroundStyle(destructive ? .red : .primary)
                Spacer()
            }
            .frame(height: 52)
            .contentShape(Rectangle())
            .padding(.horizontal, 16)
        }
        .buttonStyle(.plain)
    }
}
