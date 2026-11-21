import AVKit
import MessagingUI
import PhotosUI
import QuickLook
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// 自研聊天页：悬空顶栏（头像 + 玻璃名字牌）+ FluidGroup TiledView
/// 滚动引擎 + 自己画的输入栏。顶栏玻璃只属于名字牌，顶栏上面是
/// iOS 26 原生 Scroll Edge Effect（渐变模糊）。
struct ChatView: View {
    var onNewChat: () -> Void = {}
    var onUserSent: (String) -> Void = { _ in }
    @State private var conversation = Conversation()
    /// 个人页那份 AgentProfile（App 入口注入）：send() 传给
    /// Conversation，配齐了才走真 AI；没配齐走假回复。
    @Environment(AgentProfile.self) private var profile
    /// 状态栏高度（step 85）：顶栏材质的高 = 顶栏内容高 +
    /// 这份高度，不然材质在 90pt 就断了、头像和名字牌落在外面（图 45）。
    /// SwiftUI 没有 `\.safeAreaInsets` 这个环境值（CI 红过一次），
    /// 用根上那份 GeometryReader 量出来。兜底 59pt：灵动岛手机
    /// 的状态栏就是这个数，量到之前先按它，Dolos 那台正好是这个数。
    @State private var topSafeAreaInset: CGFloat = 59
    /// 滚动交给 FluidGroup 自己的开关，不再手写 scrollToBottom：
    /// 首次加载后滑到底；新消息只在离底 < 100pt 时才跟到底
    /// （见下面 onTiledScrollGeometryChange），翻上去看历史时不抢滚动。
    @State private var scrollPosition = TiledScrollPosition(
        autoScrollsToBottomOnAppend: true,
        scrollsToBottomOnReplace: true
    )
    @State private var inputText = ""
    @State private var staged: [MediaAttachment] = []
    @FocusState private var inputFocused: Bool

    @State private var showPhotos = false
    @State private var showFiles = false
    @State private var showCamera = false
    @State private var photoItems: [PhotosPickerItem] = []

    @State private var previewURL: URL?
    @State private var playingVideo: IdentifiableURL?
    @Environment(ToolsStore.self) private var toolsStore
    /// 附件出问题时给用户的一句明确提示（选不上 / 拷不动 / 保存失败），
    /// 不许悄悄丢附件。
    @State private var attachmentError: String?

    @StateObject private var dictation = DictationManager()
    @State private var dictationBaseText = ""
    @State private var keyboardVisible = false

    /// 长按气泡开出来的 Telegram 式菜单（step 30）：只存 id + 位置 +
    /// 手指点，消息本体每次从 conversation 里现取，
    /// 这样菜单里点了表情，选中态立刻就是新的，不会拿着旧快照。
    @State private var contextMenu: ContextMenuTarget?

    /// 正在被长按的那条（step 33）：cell 的长按手势在按住那一刻
    /// （pressing:true）就报上来，菜单由根上那份 simultaneous 手势
    /// 在 0.45s 到时开——两边是同一个手指、同一个 0.45s，
    /// 按住时就记下，0.45s 到时一定已经在了，不用抢时序。
    /// 松开 / 菜单开出来就清掉；超过 2 秒没开出来也作废，
    /// 免得一次没开成的按住留到下一次。
    @State private var pendingLongPress: PendingLongPress?

    /// 点引用跳过去的那条（step 70）：目标行闪一下，1 秒后清掉。
    @State private var highlightedMessageID: UUID?

    /// 离底部超过 100pt 时回到底部按钮出现（step 71）；
    /// 在上面翻历史时新来的对方消息记未读数，回到 底部清零。
    @State private var isAwayFromBottom = false
    @State private var unreadCount = 0

    /// 流式跟滑上一次滚动的时间（step 79）：chunk 约 33ms 来一个，
    /// 每个都滑会打架，120ms 滑一次、每次都是小距离，
    /// 连起来就是顺滑地往下走。
    @State private var lastFollowScroll = Date.distantPast

    /// 滚动几何里最近一次量到的离底距离（step 83）：跟滑只在
    /// 新内容真的被挡住时才滑，已经在底部就别动——每一滑都把
    /// 弹簧动画重启一遍，拖着的手指会被打断。
    @State private var lastPointsFromBottom: CGFloat = 0

    /// 消息内容顶上留的空：第一条消息在顶栏底边下面 16pt。
    /// 固定数，不是从几何里算出来的——没有反馈环，不会再漂。
    private let topContentOffset: CGFloat = 16

    /// 进场动画已删干净（step 48）：新消息不自己动，
    /// 只有库那道滑到底的滚动（见 MessageCell 的说明）。

    /// 正在回哪条：只存 id，原文每次按 id 现找（见 replyTarget）。
    /// 发出去和点 × 都清掉它。
    @State private var replyingTo: UUID?

    /// 正在回的那条原文（按 replyingTo 现找）。
    private var replyTarget: ChatMessage? {
        replyingTo.flatMap { id in conversation.messages.first(where: { $0.id == id }) }
    }

    /// 回复预览栏 52pt；底栏总高 = 输入框 70 + 有回复时再加 52。
    /// 换头像/换名字的提示栏也是 52pt（step 80）：显示着它时
    /// 底栏一样长高，不然提示栏会盖住最后一条消息——
    /// 跟回复预览栏同一个道理。
    private let replyPreviewHeight: CGFloat = 52

    private var bottomAreaHeight: CGFloat {
        inputBarHeight
            + (replyTarget == nil ? 0 : replyPreviewHeight)
            + (pendingHint == nil ? 0 : replyPreviewHeight)
    }

    /// 顶栏的高度（不含状态栏）。列表顶边 inset 只算这一项，
    /// 状态栏那一份 FluidGroup 内部自己加，不重复算。
    /// 对比版（Telegram 顶栏：小头像 + 名字 + 状态）是 56。
    private var headerHeight: CGFloat { ChatTheme.headerHeight }

    /// 底栏的高度：主版本 70（输入框 46 + 上下 padding 16 + 底边 8）；
    /// 对比版 57（Telegram：面板最小高 49 = 14 + 框 35，再加基高 8）。
    /// 列表 frame 用负 bottom padding 伸下去这么多、底边 inset
    /// 也顶上来这么多，最后一条消息静止时正好贴着底栏上面。
    private var inputBarHeight: CGFloat { ChatTheme.inputBarHeight }

    /// 把“有没有一句提示”变成 alert 用的 Bool Binding。
    /// 写成 helper，别把 Binding(get:set:) 直接嵌进 body 的修饰器链里——
    /// 链太长编译器会报“unable to type-check in reasonable time”。
    private func alertBinding(_ message: Binding<String?>) -> Binding<Bool> {
        Binding(
            get: { message.wrappedValue != nil },
            set: { if !$0 { message.wrappedValue = nil } }
        )
    }

    private var rows: [MessageRow] {
        MessageGrouping.rows(for: conversation.messages)
    }

    /// 流式时最后一条回复的字数（step 79）：只在流式时长，
    /// 字一多 onChange 就响，ChatView 跟着滑；不流式时是 0，
    /// 不会误触。
    private var streamingTextLength: Int {
        conversation.isStreamingReply ? (conversation.messages.last?.text.count ?? 0) : 0
    }

    /// 换头像 / 换名字进行中时输入框上面那句提示（step 80）：
    /// 记忆页点了按钮回来才有。不是发出去的消息，只是一句提示，
    /// 发完（Conversation.send 消费了 flag）就消失。
    private var pendingHint: String? {
        if profile.pendingAvatarChange {
            return "更换头像：发一张图给我"
        }
        if profile.pendingNameChange {
            return "更换名称：告诉我新名字"
        }
        return nil
    }

    var body: some View {
        pickersView
            .onChange(of: dictation.liveText) { _, text in
                inputText = dictationBaseText + text
            }
            .alert("附件提示", isPresented: alertBinding($attachmentError)) {
                Button("好") {}
            } message: {
                Text(attachmentError ?? "")
            }
            .alert("头像", isPresented: alertBinding(Binding(
                get: { profile.avatarChangeError },
                set: { profile.avatarChangeError = $0 }
            ))) {
                Button("好") {}
            } message: {
                Text(profile.avatarChangeError ?? "")
            }
            .alert("听写", isPresented: alertBinding($dictation.errorMessage)) {
                Button("好") {}
            } message: {
                Text(dictation.errorMessage ?? "")
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                keyboardVisible = true
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                keyboardVisible = false
            }
    }

    /// body 拆成几块：整个 body 写成一条修饰器链，编译器会报
    /// “unable to type-check in reasonable time”——每块单独算，链短了就编得过。
    private var pickersView: some View {
        chatStack
            .photosPicker(
                isPresented: $showPhotos,
                selection: $photoItems,
                maxSelectionCount: 10,
                matching: .any(of: [.images, .videos])
            )
            .onChange(of: photoItems) { _, items in
                handlePhotoItems(items)
            }
            .fileImporter(
                isPresented: $showFiles,
                allowedContentTypes: [.item],
                allowsMultipleSelection: true
            ) { result in
                handlePickedFiles(result)
            }
            .sheet(isPresented: $showCamera) {
                CameraPicker(
                    onPick: { image in
                        showCamera = false
                        if let media = mediaFromCameraImage(image) {
                            staged.append(media)
                        }
                    },
                    onCancel: { showCamera = false }
                )
            }
            .quickLookPreview($previewURL)
            .fullScreenCover(item: $playingVideo) { video in
                videoPlayerView(for: video.url)
            }

    }

    private var chatStack: some View {
        ZStack(alignment: .top) {
            // 壁纸（step 80）：设了就铺在列表后面。列表的
            // collectionView 本来就是透明的（TiledView:661），
            // 气泡是不透明的，字不会糊在图上。
            // 对比版没设壁纸时不是素底：Telegram 默认就是带淡淡图案的
            // 壁纸（浅色 #E7EBF0、深色 #0E1621），素底看着就不是 Telegram。
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            if let wallpaperURL = profile.wallpaperURL {
                WallpaperView(
                    url: wallpaperURL,
                    scale: profile.wallpaperScale,
                    offset: profile.wallpaperOffset,
                    blur: profile.wallpaperBlur,
                    motion: profile.wallpaperMotion,
                    brightness: profile.wallpaperBrightness
                )
            }

            VStack(spacing: 0) {
                TiledView(items: rows, scrollPosition: $scrollPosition) { row in
                    MessageCell(
                        item: row,
                        isHighlighted: highlightedMessageID == row.message.id,
                        sherryName: profile.displayName,
                        onVideoTap: { playingVideo = IdentifiableURL(url: $0) },
                        onFileTap: { previewURL = $0 },
                        onQuoteTap: { jumpToMessage(id: $0) },
                        onSwipeReply: { message in
                            // 右滑回复（step 72）：和长按菜单里的回复一样，
                            // 只记下回哪条、弹起键盘，预览栏出现在输入框上面。
                            replyingTo = message.id
                            inputFocused = true
                        },
                        onRetry: { message in
                            // 点失败那条下面的“重试”：删掉失败那条及之后，
                            // 用新 id 重新流式（Conversation.retryFailedReply）。
                            Task {
                                await conversation.retryFailedReply(id: message.id, profile: profile)
                            }
                        },
                        onPressStart: { message in
                            pendingLongPress = PendingLongPress(
                                id: message.id,
                                position: row.position,
                                since: Date()
                            )
                        },
                        onPressEnd: {
                            pendingLongPress = nil
                        }
                    )
                }
                // iMessage 风格的输入状态：对方正在输入时显示原生三点气泡。
                .typingIndicator(.indicator(isVisible: conversation.isTyping) {
                    TypingBubble()
                })
                .revealConfiguration(.default)
                // 顶边 inset 只算两项：顶栏高度 90 + 顶上留的空 16，
                // 都是固定数。状态栏那一份 FluidGroup 内部自己加，
                // 不在我们这里重复算。底边 inset 是底栏的高度：
                // 列表 frame 用负 bottom padding 伸到底栏后面去，
                // 底边 inset 顶上来同样多，最后一条消息静止时
                // 正好贴着底栏上面。键盘高度由 FluidGroup 自己拿。
                .additionalContentInset(EdgeInsets(top: headerHeight + topContentOffset, leading: 0, bottom: bottomAreaHeight, trailing: 0))
                .onTapBackground {
                    inputFocused = false
                }
                // 跟底开关：离底 < 100pt 才跟，翻上去看历史时不抢滚动；
                // 值没变就不写，免得每次滚动几何变化都触发一次 @State 赋值。
                .onTiledScrollGeometryChange { geometry in
                    let nearBottom = geometry.pointsFromBottom < 100
                    lastPointsFromBottom = geometry.pointsFromBottom
                    if scrollPosition.autoScrollsToBottomOnAppend != nearBottom {
                        scrollPosition.autoScrollsToBottomOnAppend = nearBottom
                    }
                    if isAwayFromBottom == nearBottom {
                        isAwayFromBottom = !nearBottom
                    }
                    if nearBottom, unreadCount != 0 {
                        unreadCount = 0
                    }
                }
                // 拖进底边安全区（键盘区）就收键盘。
                .onDragIntoBottomSafeArea {
                    inputFocused = false
                }
                // 长按菜单的手指位置：这份手势活在主层级里，`.named("chat")`
                // 坐标系和下面那个 overlay 是同一个空间，量出来的点
                // 直接就是菜单要摆的点。cell 那边按住时就记下了哪条
                // （pendingLongPress），这里只管开菜单。
                // 必须是 `.simultaneousGesture`，不是 `.gesture`：
                // `.gesture` 优先于视图自己的手势，里面那个
                // minimumDistance: 0 的 DragGesture 一上手就把触摸
                // 认领了，底下 UICollectionView 的 pan 收不到手指，
                // 整页冻住；simultaneous 两个手势同时认，手指一滑
                // 长按认不上、pan 照常走，手指定住 0.45s 菜单照常开。
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.45)
                        .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named("chat")))
                        .onChanged { value in
                            if case .second(true, let drag?) = value,
                               contextMenu == nil,
                               let pending = pendingLongPress,
                               Date().timeIntervalSince(pending.since) < 2 {
                                // 震动只在这里震一次（step 47）：长按认出来了、
                                // 菜单真要开。哪个气泡都走这一条，所以哪个
                                // 气泡都震；cell 那边不再震，免得叠成两下。
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                contextMenu = ContextMenuTarget(
                                    id: pending.id,
                                    position: pending.position,
                                    anchor: drag.location
                                )
                                pendingLongPress = nil
                            }
                        }
                )
                // 注意顺序：scrollDismissesKeyboard 是系统修饰器，
                // 返回 some View，会把 TiledView 的类型丢掉——
                // FluidGroup 自己的修饰器必须放在它前面。
                .scrollDismissesKeyboard(.interactively)
                // iOS 26 原生 Scroll Edge Effect（soft 渐变模糊），顶 + 底。
                // 真正起作用的是 ScrollEdgeEffectConfigurator（直接设
                // collectionView 的 topEdgeEffect / bottomEdgeEffect），
                // 这个 SwiftUI 修饰器只是顺手也挂上。
                .nativeScrollEdgeEffectSoft()
                .background(ScrollEdgeEffectConfigurator())
                // 输入栏留在布局流内，由系统 TabView/键盘安全区共同管理。
                // 不再负 padding 伸到标签栏后面，避免与原生 Liquid Glass Tab Bar 重叠。
                // 新消息进来、人在上面翻历史时才记未读；
                // 自己发的、或已经在底部的都不记。
                // 挂在这里不挂上面：FluidGroup 自己的修饰器
                // （onDragIntoBottomSafeArea 那些）是 TiledView
                // 自己的 consuming 方法，.onChange 会把类型
                // 变成普通 some View、后面的 FluidGroup 修饰器
                // 就找不到了——必须等链走完、类型已经丢了再挂。
                .onChange(of: conversation.messages.count) { _, _ in
                    if isAwayFromBottom,
                       let last = conversation.messages.last,
                       last.sender != .me {
                        unreadCount += 1
                    }
                }
                // 流式跟滑（step 79，step 83 改过，step 84 再改）：
                // 回复一边长字、一边滑到底，最新一行始终贴在输入框上面，
                // 不会被玻璃输入框挡住。根因：库只在 append 时滑
                // （autoScrollsToBottomOnAppend），同一条消息原地长字
                // 不触发 append，所以之前长多高都不动。
                // step 83 的做法是每 120ms 直接把偏移量放到位（animated: false）：
                // 8 次/秒的小跳，连起来看着就是一抖一抖的；而且每次调用
                // 都先停掉滚动的惯性——Dolos 23:46 报的“气泡动画很卡”
                // 就是这个：长字（50ms 一刷）+ 跳滑（120ms 一跳）各走各的。
                // step 84：跟滑只在离底超过 16pt 时触发一次，用的就是
                // 库里那台 SpringScrollAnimator（animated: true）——
                // 它每帧都重新算目标（dynamic target），气泡长多高、
                // 目标就往下走多远，一台弹簧从头跟到尾、不用重启，
                // 手指一拖它自己就停（库里的 pan 取消）。
                // 触发节流 300ms：气泡匀速长的时候弹簧自己追，不用反复喊；
                // 只有长字停了一阵、弹簧追到了又停下，下一段长出来、
                // 离底又超过 16pt 时，才再喊一台新的。
                // 第一 token 那一下还是 append 那道滚动管（step 68
                // 的一帧到位不动）；她中途滑上去看历史时 isAwayFromBottom
                // 为真，跟滑停住、不抢滚动。
                .onChange(of: streamingTextLength) { _, _ in
                    guard conversation.isStreamingReply, !isAwayFromBottom else { return }
                    guard lastPointsFromBottom > 16 else { return }
                    let now = Date()
                    guard now.timeIntervalSince(lastFollowScroll) > 0.3 else { return }
                    lastFollowScroll = now
                    scrollPosition.scrollTo(edge: .bottom, animated: true)
                }

                // 换头像 / 换名字进行中（step 80）：记忆页点了按钮
                // 回来，输入框上面显示要换什么。× 点一下取消，
                // 两个 flag 都清掉——不是只清一个，免得下次发消息
                // 误触发。发出去那条消息就是内容（ChatView.send 不动，
                // Conversation.send 里按 flag 消费）。
                if let hint = pendingHint {
                    pendingHintBar(hint)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .animation(.easeInOut(duration: 0.25), value: pendingHint)
                }

                // 回复预览栏：正在回哪条时才出现，贴在输入框上面、52pt 高。
                // 左边 2pt 彩条 + 名字一行 + 原文一行，被回的是照片就带
                // 一张 35×35 小图，右边一个 44×44 的 ×，点了就取消回复。
                // 点文字区跳回被引的那条（step 75），点 × 只取消回复。
                if let quoted = replyTarget {
                    replyPreviewBar(for: quoted)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .animation(.easeInOut(duration: 0.25), value: replyingTo)
                }

                InputBar(
                    text: $inputText,
                    staged: $staged,
                    focused: $inputFocused,
                    isDictating: dictation.isRecording,
                    dictationUnavailable: dictation.unavailable,
                    isKeyboardUp: keyboardVisible,
                    onSend: send,
                    onMicTap: toggleDictation,
                    onPickPhotos: { showPhotos = true },
                    onPickFiles: { showFiles = true },
                    onTakePhoto: { showCamera = true }
                )
            }

            // 顶栏：钉死在顶上的兄弟节点，不在滚动内容里、也不进
            // FluidGroup 的 .headerContent()——所以滚多远它都不动。
            // 状态栏高度不手量：这个 overlay 本来就从安全区顶边
            // （灵动岛下面）开始画，头像自然坐在岛下面。
            // 顶栏底（step 89，图 49）：step 88 的 mask 是顶上 62%
            // 全强度、下面才淡——量出来图 49 顶上 0–118pt 都是一大块
            // 均匀的奶白，只有上面一点点在渐变。Dolos 要的恰恰反过来：
            // 只有状态栏那一小块该糊、还不能这么糊，然后往下
            // 慢慢地没了。所以峰值压到 0.35（原来是满的 1.0），
            // 状态栏那段（约 0–0.28）只轻轻糊一层，剩下的大半块
            // 都是缓坡——到头像那儿只剩一点点，到名字牌那儿
            // 几乎没了。做法还是原生：模糊本身就是系统
            // `.ultraThinMaterial`（iOS 底层液态玻璃，一点没变），
            // mask 只调它的强度，不画颜色、没有实色块、没有细线。
            // 原生 API 没有“有色渐变”这个东西
            // （research/liquid-glass-ios26.md §7.5），列表那边
            // 的原生 Scroll Edge Effect（.soft）也留着，内容滑到
            // 顶栏下面时它负责淡出——两边各管各的。
            // 几何不动：材质高 = 顶栏高 + 状态栏高。
            ZStack(alignment: .top) {
                Group {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .mask(
                            LinearGradient(
                                stops: [
                                    .init(color: .black.opacity(0.24), location: 0),
                                    .init(color: .black.opacity(0.16), location: 0.42),
                                    .init(color: .clear, location: 1),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
                    .frame(height: headerHeight + topSafeAreaInset)
                    .frame(maxWidth: .infinity, alignment: .top)
                    .ignoresSafeArea(edges: .top)

                headerView
            }

            // 回到底部按钮（step 71，step 83 改了摆法）：
            // 离底 >100pt 才出现，右下角、悬在底栏上面 12pt，
            // 带未读数角标（99 封顶）。点一下滑到底部，未读数清零；
            // 滑回去后几何回调也会清零。
            // 摆法千万别把 .frame(maxWidth: .infinity, maxHeight: .infinity)
            // 直接挂在按钮身上（step 71–82 就是这么挂的）：按钮会被撑满
            // 全屏，手指点哪都先落在它身上，列表的 pan 收不到手指，
            // 页面就冻住了；而且 isAwayFromBottom 一旦为真就再也没有
            // 滚动事件把它清掉，冻住就一直冻着——Dolos 22:51 报的
            // “根本不让上下滑动”就是这个。现在按钮只在右下角 44pt 里，
            // 上下左右的空位是 Spacer（不吃触摸），手指都交给列表。
            if isAwayFromBottom {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        backToBottomButton
                    }
                }
                .padding(.trailing, 16)
                .padding(.bottom, bottomAreaHeight + 12)
                .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isAwayFromBottom)
        // 根底色：顶栏区后面是系统底色，深色浅色都走系统。
        .background(Color(.systemBackground))
        // "chat" 坐标系：长按菜单的手指位置和 overlay 都用它——
        // 根上那份手势量的点，和 overlay 里的 `.position` 是同一个空间。
        .coordinateSpace(name: "chat")
        // 长按气泡的 Telegram 式菜单：表情行 + 抬起来的气泡 + 回复/复制。
        // 消息本体从 conversation 里现取，菜单里点了表情，选中态立刻更新。
        .overlay {
            if let target = contextMenu,
               let message = conversation.messages.first(where: { $0.id == target.id }) {
                MessageContextMenuOverlay(
                    message: message,
                    position: target.position,
                    anchor: target.anchor,
                    replyTo: conversation.messages.first(where: { $0.id == message.replyToID }),
                    onToggleReaction: { emoji in
                        conversation.toggleReaction(emoji, for: target.id)
                    },
                    onReply: {
                        // 只记下回哪条、弹起键盘；预览栏出现在输入框上面，
                        // 发出去时这条 id 跟着消息走（send 里传 replyToID）。
                        replyingTo = target.id
                        inputFocused = true
                    },
                    onCopy: {
                        UIPasteboard.general.string = message.text
                    },
                    onDelete: {
                        // 删的那条正被回复预览指着时，预览一起清掉。
                        if replyingTo == target.id {
                            replyingTo = nil
                        }
                        conversation.deleteMessage(id: target.id)
                    },
                    onDismiss: {
                        contextMenu = nil
                    }
                )
            }
        }
        // 震动不在这里：Conversation.send 里发出去/收进来时各调一次，
        // 免得这里再叠一次、震两下。
        // 根上量状态栏高（step 85）：顶栏材质的高要加上它。
        // GeometryReader 挂在 background 里，不占地方、不挡触摸；
        // 量到就记下来，变了（比如转屏）再更新。
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { topSafeAreaInset = proxy.safeAreaInsets.top }
                    .onChange(of: proxy.safeAreaInsets.top) { _, newValue in
                        topSafeAreaInset = newValue
                    }
            }
        )
    }

    /// 点引用跳回原文（step 70，Telegram 的 navigateToMessage）：
    /// 按 id 找下标，库把它居中滚到屏幕中间，目标行闪一下；
    /// 原文删了、找不到了就不跳。全部消息都在内存里，
    /// 不存在“先加载再跳”。1 秒后把高亮清掉，闪一下就够了。
    private func jumpToMessage(id: UUID) {
        guard let index = conversation.messages.firstIndex(where: { $0.id == id }) else { return }
        scrollPosition.scrollToItem(index: index)
        highlightedMessageID = id
        Task {
            try? await Task.sleep(for: .milliseconds(1000))
            if highlightedMessageID == id { highlightedMessageID = nil }
        }
    }

    private func videoPlayerView(for url: URL) -> some View {
        VideoPlayer(player: AVPlayer(url: url))
            .ignoresSafeArea()
            .overlay(alignment: .topLeading) {
                Button { playingVideo = nil } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.white, .black.opacity(0.6))
                }
                .padding()
            }
    }

    private func handlePhotoItems(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        photoItems = []
        Task {
            let (newMedia, failedCount) = await mediaFromPhotoItems(items)
            if failedCount > 0 {
                attachmentError = "有 \(failedCount) 张照片/视频没能加进来，请再试一次。"
            }
            staged.append(contentsOf: newMedia)
        }
    }

    private func handlePickedFiles(_ result: Result<[URL], Error>) {
        if case .success(let urls) = result {
            let (newMedia, failedNames) = mediaFromFileURLs(urls)
            if !failedNames.isEmpty {
                attachmentError = "以下文件没能加进来：\(failedNames.joined(separator: "、"))。可能是 iCloud 还没下载完，或来源 App 不让读，再试一次。"
            }
            staged.append(contentsOf: newMedia)
        }
    }

    /// 回到底部按钮本体（step 71）：44pt 玻璃圆 + 向下箭头，
    /// 有未读时右上角挂红色数字角标（99 封顶）。
    private var backToBottomButton: some View {
        Button {
            scrollPosition.scrollTo(edge: .bottom)
            unreadCount = 0
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "arrow.down")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .glassCircleFill()
                if unreadCount > 0 {
                    Text("\(min(unreadCount, 99))")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(.red, in: Capsule())
                        .offset(x: 6, y: -6)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - 顶栏

    /// 悬空的顶栏：头像在上、名字在下，没有整条玻璃底、没有分隔线。
    /// 玻璃只属于名字牌，头像是实色蓝圆；头像 56pt，往下挪 8pt，
    /// 底边轻压进名字牌顶部约 8pt。VStack 里后画的会盖住先画的，
    /// 名字牌在头像下面、会盖住头像底边，所以头像挂 `.zIndex(1)`，
    /// 让它画在名字牌上面。名字右边的小 chevron 是按信息 App 的做法放的。
    /// 点顶栏（头像在里面）进全屏个人页（ProfileView：SOUL、记忆、API 接入），
    /// 原来那个占位的联系人卡片 sheet 废了。
    /// 头像和名字是 profile 里那份（step 80，记忆页换头像/换名字改的）：
    /// 换过头像就用换的图，改过名字就显示新名字；没动过就是
    /// 原来的 sparkles 蓝圆 + Sherry。
    /// 位置（step 49）：整块往上挪了约 8pt，头像顶边离灵动岛约 5pt，
    /// 就是“到状态栏下面就好”——原来顶上 padding 4pt + 居中空 1pt
    /// + 头像自己的 offset 8pt，头像顶边在岛下面约 13pt，太空了。
    /// 挪法：顶上那 4pt padding 拿掉，整块再往上 offset 4pt；
    /// 头像压名字牌那 8pt overlap 没动。
    private var headerView: some View {
        ZStack {
            VStack(spacing: 4) {
                avatarView(size: 72)
                    .offset(y: 10)
                    .zIndex(1)
                Text(profile.displayName)
                    .font(.headline.weight(.semibold))
                    .lineLimit(1)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 5)
                    .glassCapsuleFill()
                Text(conversation.isTyping ? "正在输入…" : "在线")
                    .font(.caption2)
                    .foregroundStyle(conversation.isTyping ? Color.secondary : Color.green)
            }

            HStack {
                Spacer()
                Button(action: onNewChat) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 17, weight: .bold))
                        .frame(width: 42, height: 42)
                        .glassCircleFill()
                        .offset(y: -18)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("新增聊天")
            }
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity)
        .frame(height: headerHeight)
    }

    @ViewBuilder
    private func avatarView(size: CGFloat) -> some View {
        if let avatarURL = profile.avatarURL {
            LocalImage(url: avatarURL, pixelWidth: nil, pixelHeight: nil, fixedSize: CGSize(width: size, height: size))
                .clipShape(Circle())
        } else {
            Image(systemName: "sparkles")
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(Color.accentColor, in: Circle())
        }
    }

    /// 对比版（Telegram 式）顶栏：小头像 + 名字 + 状态行，左对齐。
    /// Telegram 的对话顶栏就是这样：头像 40pt 左右、名字在上、
    /// 状态（在线 / 正在输入…）在下。正在输入时状态行写“正在输入…”——
    /// Telegram 的输入状态只在顶栏显示，不占气泡（我们主版本的
    /// 三点气泡是给 AI 回复做的模拟，Dolos 定过，留着不动）。
    /// 点顶栏进个人页，和主版本一样。
    private var telegramHeaderView: some View {
        HStack(spacing: 10) {
            Group {
                if let avatarURL = profile.avatarURL {
                    LocalImage(url: avatarURL, pixelWidth: nil, pixelHeight: nil, fixedSize: CGSize(width: 40, height: 40))
                        .clipShape(Circle())
                } else {
                    Image(systemName: "sparkles")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(Color.accentColor, in: Circle())
                }
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(profile.displayName)
                    .font(.headline)
                    .lineLimit(1)
                Text(conversation.isTyping ? "正在输入…" : "在线")
                    .font(.caption2)
                    .foregroundStyle(conversation.isTyping ? .secondary : Color.accentColor)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .frame(height: headerHeight)
    }

    /// 换头像 / 换名字进行中的提示栏（step 80）：52pt 高，
    /// 和回复预览栏一个尺寸、一块玻璃，贴在输入框上面。
    /// 左边是个小图标 + 提示字，右边 × 取消（两个 flag 都清掉）。
    private func pendingHintBar(_ hint: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: profile.pendingAvatarChange ? "person.crop.circle.badge.plus" : "pencil")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(hint)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            Button {
                profile.pendingAvatarChange = false
                profile.pendingNameChange = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .frame(height: replyPreviewHeight)
        .glassPanelFill(cornerRadius: 18)
        .padding(.horizontal, keyboardVisible ? 20 : 8)
    }

    /// 回复预览栏本体：52pt 高，左边 2pt 彩条 + 名字一行 + 原文一行，
    /// 被回的是照片就带一张 35×35 小图，右边一个 44×44 的 ×。
    /// 底是一块和输入框同宽的玻璃，和下面那行输入框贴在一起，
    /// 视觉上就是一块长高的玻璃输入区。横向边距跟输入框那行对齐
    /// （键盘没起来 8pt、起来了 20pt）。
    private func replyPreviewBar(for quoted: ChatMessage) -> some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(quoted.nameColor)
                .frame(width: 2, height: 36)
                .clipShape(Capsule())
            if case .image(let url, _, _) = quoted.media.first {
                LocalImage(url: url, pixelWidth: nil, pixelHeight: nil, fixedSize: CGSize(width: 35, height: 35))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            VStack(alignment: .leading, spacing: 1) {
                // 被回的是雪莉时显示改过的名字（step 80）：
                // 引用块里“雪莉”两个字是 quoted.displayName 写死的，
                // 改了名字还显示旧的就错了。
                Text(quoted.sender == .sherry ? profile.displayName : quoted.displayName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(quoted.nameColor)
                    .lineLimit(1)
                Text(quoted.snippet)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            // 点文字区跳回被引的那条（step 75，Telegram 的简化版：
            // 点就跳，不做选项菜单）。手势只挂在文字区上，不挂
            // 整个栏——右边的 × 是 Button，点它只取消回复，不跳。
            .contentShape(Rectangle())
            .onTapGesture { jumpToMessage(id: quoted.id) }
            Spacer()
            Button {
                replyingTo = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .frame(height: replyPreviewHeight)
        .glassPanelFill(cornerRadius: 18)
        .padding(.horizontal, keyboardVisible ? 20 : 8)
    }

    // MARK: - 发送和听写

    private func send() {
        let text = inputText
        let media = staged
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !media.isEmpty else { return }
        // 先把附件拷到持久目录再发；拷不动的那一项原样保留在消息里，
        // 但要告诉用户——重启后它可能打不开，绝不悄悄丢。
        let (persisted, failed) = persistSentMedia(media)
        if !failed.isEmpty {
            attachmentError = "以下附件没能存下来，已按原位置发出，重启手机后可能打不开：\(failed.joined(separator: "、"))。"
        }
        onUserSent(trimmed)
        profile.reviewUserMessageForMemory(trimmed)
        let messageID = UUID()
        // 回复态跟着这条消息走：发出去就清掉，预览栏立刻收起。
        let replyID = replyingTo
        replyingTo = nil
        inputText = ""
        staged = []
        Task {
            await conversation.send(text, persisted, id: messageID, replyToID: replyID, profile: profile)
        }
    }

    private func toggleDictation() {
        if dictation.isRecording {
            dictation.stop()
        } else if dictation.isStarting {
            // 授权还没回来：这一下是取消，不是再开一回。
            dictation.cancelStart()
        } else {
            dictationBaseText = inputText
            dictation.liveText = ""
            dictation.start()
        }
    }
}

/// fullScreenCover(item:) 要 Identifiable，URL 自己不是。
private struct IdentifiableURL: Identifiable {
    let url: URL
    var id: URL { url }
}

/// 壁纸铺法（step 89）：聊天页和编辑器共用同一套数，框出来的样子
/// 就是贴上去的样子。
/// - 铺满（cover）：宽高两个方向取大的那个缩放，只裁不拉。
/// - 位移夹住：图永远盖住整个框，不留白边——图 49 底下那条白带
///   （1040–1080px 纯白）就是图没盖住底边，编辑器里也一样夹。
enum WallpaperLayout {
    /// 铺满倍数：宽高两个方向取大的那个。
    static func coverScale(imageSize: CGSize, frame: CGSize) -> CGFloat {
        guard imageSize.width > 0, imageSize.height > 0,
              frame.width > 0, frame.height > 0 else { return 1 }
        return max(frame.width / imageSize.width, frame.height / imageSize.height)
    }

    /// 铺满后再乘用户缩放，图的实际尺寸。extraScale 是动态开着时
    /// 多放大的那一点（step 92：1.08），视差移动才有余量、不露白。
    static func displayedSize(imageSize: CGSize, frame: CGSize, userScale: CGFloat, extraScale: CGFloat = 1) -> CGSize {
        let s = coverScale(imageSize: imageSize, frame: frame) * max(1, userScale) * extraScale
        return CGSize(width: imageSize.width * s, height: imageSize.height * s)
    }

    /// 位移夹到盖住框的范围里：图比框大的那部分才能移，
    /// 移到头图边正好贴着框边，再移就露白了。
    static func clampedOffset(_ offset: CGSize, imageSize: CGSize, frame: CGSize, userScale: CGFloat, extraScale: CGFloat = 1) -> CGSize {
        let d = displayedSize(imageSize: imageSize, frame: frame, userScale: userScale, extraScale: extraScale)
        let maxX = max(0, (d.width - frame.width) / 2)
        let maxY = max(0, (d.height - frame.height) / 2)
        return CGSize(
            width: min(max(offset.width, -maxX), maxX),
            height: min(max(offset.height, -maxY), maxY)
        )
    }

    /// 视差能移的余量（step 92）：图比框多出来的那一半，
    /// 减掉用户已经移掉的部分——移到头图边正好贴着框边。
    static func parallaxMargin(displayed: CGSize, frame: CGSize, offset: CGSize) -> CGSize {
        CGSize(
            width: max(0, (displayed.width - frame.width) / 2 - abs(offset.width)),
            height: max(0, (displayed.height - frame.height) / 2 - abs(offset.height))
        )
    }
}

/// 聊天壁纸（step 80，step 88 重写渲染，step 89 再改两处，step 92 加了
/// 模糊/动态/亮度，step 93 改两处）：
/// 本地文件的一张图，铺满整个聊天页、盖在系统底色
/// 上面、消息列表下面。列表的 collectionView 本来就是透明的
/// （TiledView:661），图直接透出来；气泡是不透明的，字不会糊在图上。
/// AsyncImage 不吃 file://，这里自己读文件，和 LocalImage 一个做法。
/// - 一定保住原比例（step 88，图 47/48：换壁纸后照片左右拉着）：
///   按图片真实尺寸（`image.size`）自己算缩放，宽高两个方向取大的那个，
///   只裁不拉；图居中摆，左右裁多少、上下裁多少都由比例定。
/// - 满铺的框一定不能是死数（step 94，图 53/55）：step 89 把这层
///   改成 `.frame(width: screen.width, height: screen.height)`（整屏
///   死框 852pt）之后，顶栏头像跑到状态栏里去了（图 53/55 里头像顶
///   在 21.3pt，图 47/49 里是 67pt；输入框也往下挪了约 44pt）。根因
///   是根 ZStack 只被提议了安全区 759pt（852 − 59 状态栏 − 34 Home
///   条），死框把它硬撑成 852pt，多出来的 93pt 默认居中、上下各溢
///   46.5pt——头像 67 − 46.5 = 20.5 ≈ 实测 21.3（残差约 3pt 是顶栏
///   内部 90pt 框里内容居中多出来的 3pt）。step 93 只加了
///   ignoresSafeArea、没动死框，所以图 55 和图 53 一模一样。
///   修法：回到 step 87/88 的做法——框用
///   `.frame(maxWidth: .infinity, maxHeight: .infinity)`（只拿提议的
///   尺寸、不硬撑父容器），满铺靠 `.ignoresSafeArea()` 画出去；
///   图本身的尺寸（displayedSize/clampedOffset）还是按整屏算，
///   那是图不是框，别混了。顶栏代码和 ChatTheme 一字没动。
/// - 编辑器调好的缩放位移（step 89）：铺满后再乘 scale、再加 offset，
///   渲染时再夹一次，旧值也不会露白。
/// - 模糊/动态/亮度（step 92，Telegram 的三个开关；step 93 模糊改轻）：
///   编辑器里调成什么样、这里就画成什么样；动态是 CoreMotion 的视差
///   （WallpaperMotionProvider），图多放大 8% 才有余量移，视差也夹在
///   余量里，不露白。模糊半径 step 92 是 14——整屏糊成一片，照片
///   一点认不出来（图 53），改成 8，糊归糊、照片还认得出来。
private struct WallpaperView: View {
    let url: URL
    let scale: CGFloat
    let offset: CGSize
    let blur: Bool
    let motion: Bool
    let brightness: Double
    @State private var image: UIImage?
    @StateObject private var motionProvider = WallpaperMotionProvider()

    var body: some View {
        let screen = UIScreen.main.bounds.size
        Group {
            if let image, image.size.width > 0, image.size.height > 0 {
                let motionScale: CGFloat = motion ? 1.08 : 1
                let d = WallpaperLayout.displayedSize(imageSize: image.size, frame: screen, userScale: scale, extraScale: motionScale)
                let o = WallpaperLayout.clampedOffset(offset, imageSize: image.size, frame: screen, userScale: scale, extraScale: motionScale)
                let margin = WallpaperLayout.parallaxMargin(displayed: d, frame: screen, offset: o)
                let px = min(max(motionProvider.offset.width, -margin.width), margin.width)
                let py = min(max(motionProvider.offset.height, -margin.height), margin.height)
                Image(uiImage: image)
                    .resizable()
                    .frame(width: d.width, height: d.height)
                    .position(x: screen.width / 2 + o.width + px, y: screen.height / 2 + o.height + py)
                    .blur(radius: blur ? 8 : 0)
                    .brightness((brightness - 100) / 250)
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        // 满铺走 ignoresSafeArea（step 87/88 的做法，step 94 恢复）：
        // 框只拿提议的尺寸、不硬撑父容器；状态栏和 Home 条那块也是
        // 壁纸，靠 ignoresSafeArea 画出去。死框（step 89–93）会把
        // 根 ZStack 硬撑成 852pt、顶栏头像顶进状态栏里，见上面。
        .ignoresSafeArea()
        // 地址变了就重新读（step 83）：.task 不带 id 只在第一次出现时跑，
        // 壁纸换第二张时地址还是同一份不会重读——现在每次换壁纸文件名
        // 都带 uuid（AgentProfile.setWallpaper），地址变了这里跟着重读。
        .task(id: url) {
            image = nil
            image = await Task.detached { UIImage(contentsOfFile: url.path) }.value
        }
        .onAppear { if motion { motionProvider.start() } }
        .onDisappear { motionProvider.stop() }
        .onChange(of: motion) { _, on in
            if on { motionProvider.start() } else { motionProvider.stop() }
        }
    }
}

/// 对比版默认壁纸（step 87）：Telegram 默认壁纸就是带淡淡图案的底色，
/// 不是素底。底色浅色 #E7EBF0、深色 #0E1621；图案是 120pt 一格的
/// 淡淡几何纹（小菱形 + 小点，透明度约 0.06）——Telegram 原版是
/// 小涂鸦，形状没法一模一样，底色 + 淡纹是能对上的部分。
/// 有自定义壁纸时这层不上（上面那支 `if let wallpaperURL` 优先）。
private struct TelegramWallpaperView: View {
    var body: some View {
        ZStack {
            ChatTheme.chatBackgroundColor
            Canvas { context, size in
                let tile: CGFloat = 120
                let motif = Path { p in
                    // 小菱形
                    p.move(to: CGPoint(x: 60, y: 44))
                    p.addLine(to: CGPoint(x: 72, y: 56))
                    p.addLine(to: CGPoint(x: 60, y: 68))
                    p.addLine(to: CGPoint(x: 48, y: 56))
                    p.closeSubpath()
                    // 小点
                    p.addEllipse(in: CGRect(x: 14, y: 14, width: 5, height: 5))
                    p.addEllipse(in: CGRect(x: 96, y: 92, width: 5, height: 5))
                }
                var x: CGFloat = -tile
                while x < size.width + tile {
                    var y: CGFloat = -tile
                    while y < size.height + tile {
                        context.translateBy(x: x, y: y)
                        context.stroke(motif, with: .color(.primary.opacity(0.06)), lineWidth: 1)
                        context.translateBy(x: -x, y: -y)
                        y += tile
                    }
                    x += tile
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    }
}

/// 长按菜单的目标：只存 id + 组内位置 + 手指位置，
/// 消息本体每次从 conversation 里现取，这样菜单里点了表情，
/// 选中态立刻就是新的。anchor 是手指在 "chat" 坐标系里的点。
/// 气泡尺寸不在这里存——抬起来的气泡在 overlay 里自己量。
struct ContextMenuTarget {
    let id: UUID
    let position: BubblePosition
    let anchor: CGPoint
}

/// 正在被长按的那条：cell 在按住那一刻报上来，根上的手势
/// 在 0.45s 到时按它开菜单。since 用来作废：超过 2 秒没开出来，
/// 这条记录就不算数了。
struct PendingLongPress {
    let id: UUID
    let position: BubblePosition
    let since: Date
}
