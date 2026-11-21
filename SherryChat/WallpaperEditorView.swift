import SwiftUI
import UIKit

/// 壁纸编辑器（step 89 起，Telegram 的逻辑）：选完照片先调再贴——
/// 捏合缩放、拖动移动，调好点“完成”才贴上；点“取消”就丢掉。
/// 框就是整屏（和聊天页壁纸同一块尺寸：UIScreen 整屏），
/// 所以框出来的样子就是贴上去的样子。
/// 缩放最小 1（刚好铺满），位移夹住，图永远盖住整个框，
/// 不留白边（图 49 底下那条白带就是没盖住）。
/// 手势是系统原生的 MagnifyGesture + DragGesture——
/// Dolos 表扬过的那条规矩：能交给 iOS 底层的就交给底层，
/// 不自己画、不自己算手势。
///
/// 顶栏的位置（step 92）：SwiftUI 的安全区在这页上两次都量不准——
/// step 90 的 GeometryReader 读出来是 0，step 91 的 safeAreaInset
/// 把栏留在最顶上、还把图往下顶了一条黑带（图 52）。这版不用
/// SwiftUI 安全区：状态栏高直接问 UIKit（statusBarManager，
/// 拿不到就 59），顶栏就是“状态栏高 + 8”这么个死数往下放。
/// 根 ZStack（step 94，图 54）：只加一个 `.ignoresSafeArea()`——
/// 根 ZStack 原来从安全区 y=59 开始算，但黑底和图都按 UIScreen
/// 绝对坐标摆（屏中心 426），于是都从 60pt 才开始、顶上留一条
/// 60pt 白带；顶栏又在 59pt 基础上再加 67pt，胶囊落到约 126pt，
/// 状态栏被算了两次。根上 ignore 之后坐标从 y=0 开始：黑底和图
/// 从 0 盖满、顶栏就是 67pt，只算一次。捏合/拖动/模糊/动态/亮度
/// 一字没动。
///
/// 顶栏和底板（step 93）：全是 iOS 底层液态玻璃，没有手画的——
/// 取消/完成和中间的标题都是玻璃胶囊（LiquidGlass 的 glassCapsuleFill，
/// 和顶栏名字牌同一块玻璃，按下去原生弹一下）；底下的控制板是
/// 玻璃面板（glassPanelFill），不是 step 92 那块手画的半透明黑底。
/// step 92 那套白字 + 黑底 + 黑渐变是手画的，Dolos 12:45 点名了：
/// 她早说过要用 iOS 底层液态玻璃交互逻辑，编辑器不能例外。
/// 开关和滑杆还是系统原生的 Toggle/Slider，只在旁边多写一个
/// “开/关”，一眼就能看出来现在是哪档——图 53 那版就是糊里糊涂
/// 开着模糊贴上去的；再加一个“恢复默认”，一 tap 回到
/// 缩放 1、没位移、模糊关、动态关、亮度 100，不用一张一张重调。
///
/// 模糊半径（step 93）：step 92 的 14 太糊了，整屏糊成一片、照片
/// 一点认不出来（图 53），改成 8——糊归糊、照片还认得出来，
/// 聊天页那层 WallpaperView 也同步改成 8，编辑器里看到什么样、
/// 贴上去就是什么样。
struct WallpaperEdit {
    var scale: CGFloat
    var offset: CGSize
    var blur: Bool
    var motion: Bool
    var brightness: Double // 0–100，默认 100（原图亮度）
}

struct WallpaperEditorView: View {
    let image: UIImage
    var onConfirm: (WallpaperEdit) -> Void
    var onCancel: () -> Void

    /// 捏合进行中的倍数、拖动进行中的位移（手一松就归零、
    /// 并进下面那两个正式值里）。
    @GestureState private var magnify: CGFloat = 1
    @GestureState private var drag: CGSize = .zero
    /// 已经落定的缩放（相对铺满的倍数）和位移。
    @State private var scale: CGFloat = 1
    @State private var offset: CGSize = .zero
    /// Telegram 的三个壁纸选项（step 92）：模糊开关、动态开关、
    /// 亮度滑杆（0–100，100 是原图）。
    @State private var blur: Bool
    @State private var motion: Bool
    @State private var brightness: Double
    @StateObject private var motionProvider = WallpaperMotionProvider()

    init(
        image: UIImage,
        initialBlur: Bool = false,
        initialMotion: Bool = false,
        initialBrightness: Double = 100,
        onConfirm: @escaping (WallpaperEdit) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.image = image
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        _blur = State(initialValue: initialBlur)
        _motion = State(initialValue: initialMotion)
        _brightness = State(initialValue: initialBrightness)
    }

    /// 状态栏高（step 92）：直接问 UIKit 正在前台的那个
    /// UIWindowScene 的 statusBarManager。灵动岛手机竖屏是 59，
    /// 刘海屏 47，没有刘海 20——读出来是多少就是多少，不用猜。
    /// 拿不到（不应该发生）就按 59 算。
    private var statusBarHeight: CGFloat {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let active = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first
        return active?.statusBarManager?.statusBarFrame.height ?? 59
    }

    /// 和聊天页同一块框：整屏。编辑器是全屏盖上来的，
    /// 这里的整屏就是聊天页那块整屏，框出来什么样、贴上就什么样。
    private var frame: CGSize { UIScreen.main.bounds.size }

    /// 动态开着时图多放大 8%，视差移动才有余量、不露白。
    private var motionScale: CGFloat { motion ? 1.08 : 1 }

    /// 手势进行中也实时算：捏着的时候图跟着手指走，
    /// 松手才落定、夹住——Telegram 的编辑器也是这样跟手的。
    private var effectiveScale: CGFloat { max(1, scale * magnify) }
    private var effectiveOffset: CGSize {
        WallpaperLayout.clampedOffset(
            CGSize(width: offset.width + drag.width, height: offset.height + drag.height),
            imageSize: image.size, frame: frame, userScale: effectiveScale, extraScale: motionScale
        )
    }
    /// 视差能移的余量：图比框多出来的那一半，减掉用户已经移掉的部分——
    /// 移到头图边正好贴着框边，再移就露白，所以视差也夹在这里面。
    private var parallax: CGSize {
        let d = WallpaperLayout.displayedSize(
            imageSize: image.size, frame: frame, userScale: effectiveScale, extraScale: motionScale
        )
        let margin = WallpaperLayout.parallaxMargin(displayed: d, frame: frame, offset: effectiveOffset)
        return CGSize(
            width: min(max(motionProvider.offset.width, -margin.width), margin.width),
            height: min(max(motionProvider.offset.height, -margin.height), margin.height)
        )
    }

    var body: some View {
        ZStack {
            // 黑底：显式整屏尺寸、居中放（step 94：根 ZStack 忽略安全区，
            // 所以这个 852pt 的框从 y=0 开始盖满整屏）；图没盖住的地方
            // 是黑的，不是白的。
            Color.black
                .frame(width: frame.width, height: frame.height)
                .position(x: frame.width / 2, y: frame.height / 2)

            let d = WallpaperLayout.displayedSize(
                imageSize: image.size, frame: frame, userScale: effectiveScale, extraScale: motionScale
            )
            Image(uiImage: image)
                .resizable()
                .frame(width: d.width, height: d.height)
                .position(
                    x: frame.width / 2 + effectiveOffset.width + parallax.width,
                    y: frame.height / 2 + effectiveOffset.height + parallax.height
                )
                .blur(radius: blur ? 8 : 0)
                .brightness((brightness - 100) / 250)
                // 捏合和拖动同时认：一个手捏着缩放、另一个手
                // 拖着移位置，两个手势不抢——simultaneousGesture
                // 就是干这个的。
                .gesture(
                    MagnifyGesture()
                        .updating($magnify) { value, state, _ in
                            state = value.magnification
                        }
                        .onEnded { value in
                            // 松手落定：1–4 倍，超出就夹回来；
                            // 放大后能移的范围变大了，位移也重夹一次。
                            scale = min(max(scale * value.magnification, 1), 4)
                            offset = WallpaperLayout.clampedOffset(
                                offset, imageSize: image.size,
                                frame: frame, userScale: scale, extraScale: motionScale
                            )
                        }
                )
                .simultaneousGesture(
                    DragGesture()
                        .updating($drag) { value, state, _ in
                            state = value.translation
                        }
                        .onEnded { value in
                            offset = WallpaperLayout.clampedOffset(
                                CGSize(
                                    width: offset.width + value.translation.width,
                                    height: offset.height + value.translation.height
                                ),
                                imageSize: image.size,
                                frame: frame, userScale: scale, extraScale: motionScale
                            )
                        }
                )

            VStack {
                HStack {
                    Button { onCancel() } label: {
                        Text("取消")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .glassCapsuleFill()
                    }
                    Spacer()
                    Text("调整壁纸")
                        .font(.headline)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .glassCapsuleFill()
                    Spacer()
                    Button {
                        onConfirm(WallpaperEdit(
                            scale: scale, offset: offset,
                            blur: blur, motion: motion, brightness: brightness
                        ))
                    } label: {
                        Text("完成")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .glassCapsuleFill()
                    }
                }
                .padding(.horizontal, 20)
                // 顶栏离顶的距离就是状态栏高 + 8pt，一个死数——
                // 灵动岛手机是 59 + 8 = 67pt，栏顶在灵动岛下面，
                // 不可能再落回最顶上。
                .padding(.top, statusBarHeight + 8)
                Spacer()
                // 底下的控制板：提示 + 模糊/动态开关 + 亮度滑杆 + 恢复默认。
                // 板子是原生液态玻璃（glassPanelFill），开关滑杆也是
                // 系统原生的；每档旁边都写着“开/关”，状态一眼看明白。
                VStack(spacing: 12) {
                    Text("捏合缩放，拖动移动")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.85))
                    HStack(spacing: 24) {
                        Toggle("模糊", isOn: $blur)
                        Text(blur ? "开" : "关")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                        Toggle("动态", isOn: $motion)
                        Text(motion ? "开" : "关")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                    }
                    .foregroundStyle(.white)
                    HStack(spacing: 10) {
                        Image(systemName: "sun.min.fill")
                            .foregroundStyle(.white.opacity(0.8))
                        Slider(value: $brightness, in: 0...100)
                            .tint(.white)
                        Image(systemName: "sun.max.fill")
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    Button {
                        scale = 1
                        offset = .zero
                        blur = false
                        motion = false
                        brightness = 100
                    } label: {
                        Text("恢复默认")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .glassCapsuleFill()
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .glassPanelFill(cornerRadius: 20)
                .padding(.horizontal, 20)
                .padding(.bottom, 28)
            }
        }
        // step 94（图 54）：根 ZStack 忽略安全区，坐标从 y=0 开始——
        // 黑底和图都按 UIScreen 绝对坐标摆，从 0 盖满；顶栏的 67pt
        // 也只算一次。只加这一行，别的不动。
        .ignoresSafeArea()
        .onAppear { if motion { motionProvider.start() } }
        .onDisappear { motionProvider.stop() }
        .onChange(of: motion) { _, on in
            if on { motionProvider.start() } else { motionProvider.stop() }
        }
    }
}
