import SwiftUI
import UIKit

/// 底下那一栏：圆圈加号 + 输入框（麦克风/发送在框内右侧）+ 附件条。
/// - 加号是 44pt 玻璃圆（按/长按原生弹一下，不参加任何合并）。
/// - 发送钮是框内右侧的蓝药丸，不是框外圆钮；空框时框内右侧是
///   麦克风（听写），有字或挂了附件就换成发送钮。
/// - 加号菜单：系统 Menu（step 84 换的），三行 Camera / Photos / Files；
///   原来是手搭的玻璃卡，点别处都收不掉，也没有系统菜单的弹簧和震动。
///   对比版（Telegram）：发送/麦克风不在框里，是框外右边一个蓝圆钮。
/// - 整栏悬浮：玻璃只属于输入框本身，底边离屏幕底边留 8pt 空，
///   左右 8pt（键盘起来 20pt）。
struct InputBar: View {
    @Binding var text: String
    @Binding var staged: [MediaAttachment]
    var focused: FocusState<Bool>.Binding
    var isDictating: Bool
    var dictationUnavailable: Bool
    var isKeyboardUp: Bool = false

    var onSend: () -> Void
    var onMicTap: () -> Void
    var onPickPhotos: () -> Void
    var onPickFiles: () -> Void
    var onTakePhoto: () -> Void
    var onTools: () -> Void = {}

    /// 量输入框高度用的两个数（见下面 textField）：
    /// 框宽（量文字区有多宽），和藏起来的量尺量出来的文字真高。
    @State private var fieldWidth: CGFloat = 0
    @State private var measuredTextHeight: CGFloat = 0

    /// 录音中麦克风的轻呼吸（step 36）：录着的时候一眼看出来。
    @State private var recordingPulse = false

    /// 有没有东西可发：字非空，或者挂了附件。
    private var hasContent: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !staged.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            if !staged.isEmpty {
                stagingStrip
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            inputRow
        }
        // 对比版（Telegram）：输入面板是满宽实色条，底色一直铺到屏幕底边，
        // 不是悬浮的玻璃条。主版本照旧：整栏悬空，底边离屏幕底边留 8pt。
        .background(
            Group {
                if ChatTheme.isTelegramStyle {
                    ChatTheme.inputPanelBackgroundColor
                        .ignoresSafeArea(edges: .bottom)
                }
            }
        )
        // 整栏悬空：底边离屏幕底边留 8pt，左右 12pt（键盘起来 28pt），
        // 不再贴着底边和两边。
        .padding(.bottom, 8)
        // 附件条、麦克风/发送切换、键盘收窄都用弹簧进出，
        // 之前是直接蹦出来的，看着生硬。
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: staged.count)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: hasContent)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: isKeyboardUp)
    }

    // MARK: - 输入框 + 加号那一行

    /// 没有 GlassEffectContainer、没有 glassEffectUnion——
    /// 每块玻璃只管自己弹一下（`.interactive()`），不合并。
    private var inputRow: some View {
        HStack(spacing: ChatTheme.inputRowSpacing) {
            plusButton
            Button(action: onTools) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.tint)
                    .frame(width: 32, height: 40)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("工具与 Skills")
            textField
            // 对比版（Telegram）：发送/麦克风是框外右边一个蓝圆钮，
            // 不是框内贴着的按钮。
            if ChatTheme.isTelegramStyle {
                telegramSendButton
            }
        }
        // 对比版左右 8pt、上下 7pt（Telegram 面板最小高 49 = 14 + 框 35）；
        // 主版本照旧（键盘起来 20pt 边距）。
        .padding(.horizontal, ChatTheme.isTelegramStyle ? 8 : (isKeyboardUp ? 20 : 8))
        .padding(.vertical, ChatTheme.isTelegramStyle ? 7 : 8)
    }

    /// 对比版（Telegram）的发送圆钮：框外右边，40pt 蓝圆、白箭头；
    /// 听写中是红圆麦克风（再点就是停），空框是蓝圆麦克风。
    /// Telegram 的发送按钮组就是 40pt。
    private var telegramSendButton: some View {
        Group {
            if isDictating {
                Button(action: onMicTap) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.white)
                        .frame(width: ChatTheme.sendButtonSize, height: ChatTheme.sendButtonSize)
                        .background(.red, in: Circle())
                }
            } else if hasContent {
                Button(action: onSend) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: ChatTheme.sendButtonSize, height: ChatTheme.sendButtonSize)
                        .background(.blue, in: Circle())
                }
            } else {
                Button(action: onMicTap) {
                    Image(systemName: "mic")
                        .font(.system(size: 22))
                        .foregroundStyle(.white)
                        .frame(width: ChatTheme.sendButtonSize, height: ChatTheme.sendButtonSize)
                        .background(.blue, in: Circle())
                }
                .opacity(dictationUnavailable ? 0.4 : 1)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - 加号和菜单

    /// 加号：主版本是 44pt 玻璃圆（`.interactive()`，按/长按原生弹一下），
    /// 不参加任何合并。点按：系统 Menu（相机 / 照片 / 文件）；
    /// 长按（0.5s）：直接打开系统相册，不经过菜单。
    /// Menu 是 step 84 换的：原来是手搭的玻璃卡，点别处都收不掉，
    /// 也没有系统菜单的弹簧和震动；系统 Menu 这些都是现成的。
    /// 长按还挂在 Menu 上（simultaneousGesture）：0.5s 到了就
    // 直接开相册，Menu 不会跟着弹出来。
    /// 对比版（Telegram）：加号就是一个素色加号图标，没有玻璃圆——
    /// Telegram 的附加按钮本来就没有底。
    private var plusButton: some View {
        Menu {
            Button { onTakePhoto() } label: {
                Label("Camera", systemImage: "camera.fill")
            }
            Button { onPickPhotos() } label: {
                Label("Photos", systemImage: "photo")
            }
            Button { onPickFiles() } label: {
                Label("Files", systemImage: "doc.fill")
            }
        } label: {
            if ChatTheme.isTelegramStyle {
                Image(systemName: "plus")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 40, height: 40)
            } else {
                Image(systemName: "plus")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .glassCircleFill()
                    .offset(x: -1)
            }
        }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5)
                .onEnded { _ in
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    onPickPhotos()
                }
        )
    }

    // MARK: - 挂着的附件

    /// 选好的照片/文件先挂在这儿：一排小图，每个右上角有个 ×，
    /// 点 × 就拿掉；点了发送才真的发出去。
    private var stagingStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(staged.indices, id: \.self) { i in
                    ZStack(alignment: .topTrailing) {
                        stagedThumb(staged[i])
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        Button { staged.remove(at: i) } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(.white, .black.opacity(0.6))
                        }
                        .padding(2)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }

    @ViewBuilder
    private func stagedThumb(_ media: MediaAttachment) -> some View {
        switch media {
        case .image(let url, _, _):
            LocalImage(url: url, pixelWidth: nil, pixelHeight: nil, fixedSize: CGSize(width: 64, height: 64))
        case .video(_, let thumbnailURL, _):
            if let thumbnailURL {
                LocalImage(url: thumbnailURL, pixelWidth: nil, pixelHeight: nil, fixedSize: CGSize(width: 64, height: 64))
            } else {
                Image(systemName: "play.rectangle")
                    .font(.title2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.secondary.opacity(0.2))
            }
        case .file(_, let name, _):
            VStack(spacing: 4) {
                Image(systemName: "doc.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.secondary)
                Text(name)
                    .font(.caption2)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.secondary.opacity(0.15))
        }
    }

    // MARK: - 输入框和发送

    /// 输入框：固定圆角 23pt 的液态玻璃（iOS 26 真 `.glassEffect()`，低版本回退
    /// 实色 systemGray6，不是毛玻璃），框内右侧贴着麦克风/发送钮（4pt 间隙）。
    /// 空框一行、最多五行、超了框内滚动，不再长高——Telegram 的做法。
    /// 圆角也是 Telegram 的做法：圆角 = 一行高的一半（23pt），写死、
    /// 不跟框高走，框长高只长高、不变圆——胶囊打字一多就越变越圆（截图 31）。
    /// 高度是量出来的死数，不是 maxHeight：maxHeight 在这条布局链里
    /// 会被父层撑满——空框也长到 134pt 的帽（截图 28）；lineLimit
    /// 也没卡住——打字一多长到 185pt（截图 24）。
    /// 量法：一个藏起来的 Text，跟框里同一字体、同一宽度，量出文字真高，
    /// 再夹到 1~5 行之间；框宽还没量出来（第一帧）时按一行算，
    /// 不会一上来就闪成大框。框宽不随框高变，没有反馈环。
    /// 层级：玻璃是 TextField 自己的修饰器（只包有真实内容的视图，
    /// 绝不包空 Capsule——空形状默认黑填充，玻璃一盖就是实灰），
    /// 麦克风/发送钮是 TextField 的 overlay（在文字上面）。
    /// 没有描边、没有灰底、底下不再垫任何层。
    private var textField: some View {
        TextField("iMessage", text: $text, axis: .vertical)
            .lineLimit(1...5)
            .focused(focused)
            .padding(.leading, 12)
            // 对比版发送钮在框外，框里不用给按钮留 48pt，12 就够了。
            .padding(.trailing, ChatTheme.isTelegramStyle ? 12 : 48)
            .padding(.vertical, ChatTheme.fieldVerticalPadding)
            .frame(height: fieldHeight)
            .glassFieldFill()
            // 麦克风/发送钮贴着框内右下角（只在主版本；对比版的钮在框外）：
            // 原来是垂直居中，框一长高钮就悬在半空、压着上面的气泡
            // （截图 24 里那个大蓝圈就是它）。贴底之后单行时照样居中
            // （钮 36pt + 底边 5pt = 框高 46pt 的正中），多行时钮钉在
            // 右下角，像信息 App 和 Telegram 一样。
            .overlay(alignment: .bottomTrailing) {
                if !ChatTheme.isTelegramStyle {
                    micOrSendButton
                        .padding(.trailing, 4)
                        .padding(.bottom, 5)
                }
            }
            // 量框宽：文字区的宽 = 框宽 − 左 12 − 右 48。
            // 背景色块跟框一样大，直接量它，不用 GeometryReader。
            .background(
                Color.clear
                    .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { width in fieldWidth = width }
            )
            // 藏起来的量尺：跟框里同一字体、同一宽度，量文字真高。
            // 空字时量一个空格，免得 Text("") 量出 0。
            // 宽度扣掉左右边距：主版本左 12 + 右 48（框内按钮），
            // 对比版左 12 + 右 12（按钮在框外）。
            .background(
                Text(text.isEmpty ? " " : text)
                    .font(.body)
                    .frame(width: max(fieldWidth - (ChatTheme.isTelegramStyle ? 24 : 60), 0), alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .hidden()
                    .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { height in measuredTextHeight = height }
            )
    }

    /// 一行 body 字体的行高（从系统取，不手写）。
    private var lineHeight: CGFloat {
        UIFont.preferredFont(forTextStyle: .body).lineHeight
    }

    /// 框高 = 文字真高 + 上下 padding，夹在 1 行和 5 行之间。
    /// 文字超了 5 行时框不再长，TextField 自己在框内滚。
    /// 主版本上下各 12pt（框 46）；对比版各 6pt（Telegram 框最小高 35）。
    private var fieldHeight: CGFloat {
        let textHeight = fieldWidth > 100 ? measuredTextHeight : lineHeight
        let vPad = ChatTheme.fieldVerticalPadding * 2
        return min(max(textHeight, lineHeight) + vPad, lineHeight * 5 + vPad)
    }

    /// 框内右侧：听写中永远是红色麦克风（再点就是停），不管框里有没有字
    /// （一出字就被发送钮换掉，听写就关不掉了——这就是以前的毛病）；
    /// 没听写时，有字/挂了附件是蓝药丸发送钮，空框是麦克风。
    /// 切换用弹簧 + 淡入，别直接蹦。听写不可用时麦克风照样能点，
    /// 点了 DictationManager 会报原因，不许点了没反应。
    @ViewBuilder
    private var micOrSendButton: some View {
        if isDictating {
            Button(action: onMicTap) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.red)
                    .frame(width: 36, height: 36)
                    .scaleEffect(recordingPulse ? 1.15 : 1)
                    .animation(
                        .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                        value: recordingPulse
                    )
                    .onAppear { recordingPulse = true }
                    .onDisappear { recordingPulse = false }
            }
            .buttonStyle(.plain)
            .transition(.scale(scale: 0.8).combined(with: .opacity))
        } else if hasContent {
            Button(action: onSend) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 32)
                    .background(.blue, in: RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
            .transition(.scale(scale: 0.8).combined(with: .opacity))
        } else {
            Button(action: onMicTap) {
                Image(systemName: "mic")
                    .font(.system(size: 22))
                    .foregroundStyle(.secondary)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .opacity(dictationUnavailable ? 0.4 : 1)
            .transition(.scale(scale: 0.8).combined(with: .opacity))
        }
    }
}
