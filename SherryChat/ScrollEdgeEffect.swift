import SwiftUI
import UIKit

/// iOS 26 原生 Scroll Edge Effect（滚动边缘效果）：内容滑到列表边缘时，
/// 系统在边缘画一段渐变模糊/淡出，代替我们手写的渐变遮罩。
/// - SwiftUI：`.scrollEdgeEffectStyle(.soft, for:)`；UIKit：`UIScrollView` 的
///   `topEdgeEffect` / `bottomEdgeEffect`（`.soft` = 渐变模糊淡出）。
/// 我们的列表是 FluidGroup 的 TiledView（UIKit UICollectionView 套在
/// UIViewRepresentable 里），SwiftUI 的修饰器够不到它里面的 scroll view，
/// 所以下面这个小帮手直接找到那台 UICollectionView，把原生的
/// topEdgeEffect / bottomEdgeEffect 开到 `.soft`。不改 vendored 的
/// FluidGroup 代码。`scrollEdgeEffectStyle` 那个 SwiftUI 修饰器也顺手
/// 挂上，万一系统能桥接就多一层保障。
/// effect 画在 scroll view 自身的边缘上，列表边缘的准确渲染
/// （band 多宽、淡出多柔）这边没有模拟器，看不到，只能保证调的是
/// 原生 API、位置对得上，真机上以 Dolos 的截图为准。

extension View {
    /// iOS 26 原生滚动边缘效果（soft 渐变模糊），顶 + 底。
    /// 低版本上什么都不做（没有这个 API，也没有手写渐变去仿）。
    @ViewBuilder
    func nativeScrollEdgeEffectSoft() -> some View {
        if #available(iOS 26.0, *) {
            self
                .scrollEdgeEffectStyle(.soft, for: .top)
                .scrollEdgeEffectStyle(.soft, for: .bottom)
        } else {
            self
        }
    }
}

/// 找到这页里那台 UICollectionView（TiledView 的那台），
/// 把它的原生 topEdgeEffect / bottomEdgeEffect 开到 .soft。
struct ScrollEdgeEffectConfigurator: UIViewRepresentable {
    func makeUIView(context: Context) -> EdgeEffectView {
        EdgeEffectView()
    }

    func updateUIView(_ uiView: EdgeEffectView, context: Context) {
        uiView.configureIfNeeded()
    }
}

/// 一个透明的 UIView，借着自己在层级里的位置往上找到根，
/// 再往下找第一台 UICollectionView。只找 UICollectionView——
/// 附件条那个横向 ScrollView 是普通的 UIScrollView，不会被误认。
final class EdgeEffectView: UIView {
    private var configured = false
    private var retryScheduled = false

    override func didMoveToWindow() {
        super.didMoveToWindow()
        configureIfNeeded()
        scheduleRetryIfNeeded()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        configureIfNeeded()
    }

    /// 找到 collectionView 就设好，设好一次就不再动。
    /// 找不到时留着下次再试（collectionView 建好的时序我们控制不了）。
    func configureIfNeeded() {
        guard !configured, window != nil else { return }
        guard #available(iOS 26.0, *) else { return }
        var root: UIView = self
        while let parent = root.superview { root = parent }
        guard let collectionView = root.firstSubview(ofType: UICollectionView.self) else { return }
        collectionView.topEdgeEffect.style = .soft
        collectionView.bottomEdgeEffect.style = .soft
        configured = true
    }

    private func scheduleRetryIfNeeded() {
        guard !retryScheduled else { return }
        retryScheduled = true
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            configureIfNeeded()
        }
    }
}

private extension UIView {
    /// 从自己开始往下找第一台指定类型的 view。
    func firstSubview<T: UIView>(ofType type: T.Type) -> T? {
        if let match = self as? T { return match }
        for subview in subviews {
            if let found = subview.firstSubview(ofType: type) { return found }
        }
        return nil
    }
}
