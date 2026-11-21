import SwiftUI

/// iOS 27 液态玻璃：四个 helper——`glassPanelFill`（加号菜单）、
/// `glassCircleFill`（圆形按钮）、`glassCapsuleFill`（顶栏名字牌）、
/// `glassFieldFill`（输入框）。玻璃只上在导航层，气泡保持实色。
/// iOS 26 上都是交互玻璃（`.regular.interactive()`，按/长按原生弹一下；
/// Reduce Motion 时只留普通玻璃）。回退：iOS 18–25 用毛玻璃材料 +
/// 0.5pt 白色内描边 + 轻阴影；开了“减弱透明度”用实色底。
/// 深色模式不手写色值，全走系统材料和语义色。
extension View {
    /// 液态玻璃圆角面板底：加号菜单。
    func glassPanelFill(cornerRadius: CGFloat = 20) -> some View {
        modifier(GlassPanelModifier(cornerRadius: cornerRadius))
    }

    /// 液态玻璃圆按钮底：加号圆。
    func glassCircleFill() -> some View {
        modifier(GlassCircleModifier())
    }

    /// 液态玻璃胶囊底：顶栏名字牌（“Sherry >”）。
    func glassCapsuleFill() -> some View {
        modifier(GlassCapsuleModifier())
    }

    /// 液态玻璃输入框底：固定圆角 23pt，直接挂在 TextField 上。
    /// 单层原生玻璃，只包有真实内容的 TextField，绝不包空 Capsule
    /// （空形状默认黑填充，玻璃一盖就是实灰）；没有描边、没有灰底。
    func glassFieldFill() -> some View {
        modifier(GlassFieldModifier())
    }
}

/// 白描边透明度：普通 0.15，增强对比度 0.25。
private func glassEdgeOpacity(contrast: ColorSchemeContrast) -> Double {
    contrast == .increased ? 0.25 : 0.15
}

/// iOS 26 玻璃：减弱动态时普通玻璃，否则交互玻璃（按/长按自己弹一下）。
@available(iOS 26.0, *)
private func interactiveGlass(reduceMotion: Bool) -> Glass {
    reduceMotion ? .regular : .regular.interactive()
}

private struct GlassPanelModifier: ViewModifier {
    var cornerRadius: CGFloat
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(interactiveGlass(reduceMotion: reduceMotion), in: RoundedRectangle(cornerRadius: cornerRadius))
        } else if reduceTransparency {
            content.background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: cornerRadius))
        } else {
            content
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(.white.opacity(glassEdgeOpacity(contrast: contrast)), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
        }
    }
}

private struct GlassCircleModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            // 0.5pt 细描边：白底上 .regular 玻璃近乎透明，描边是轮廓线、
            // 不是底下垫的层，+ 一直看得清。
            content
                .glassEffect(interactiveGlass(reduceMotion: reduceMotion), in: Circle())
        } else if reduceTransparency {
            content.background(Color(.systemBackground), in: Circle())
        } else {
            content
                .background(.quaternary, in: Circle())
                .overlay(
                    Circle()
                        .strokeBorder(.white.opacity(glassEdgeOpacity(contrast: contrast)), lineWidth: 0.5)
                )
        }
    }
}

/// 名字牌的玻璃：iOS 26 上是胶囊形液态玻璃；低版本回退到
/// 原来的实色白药丸（细灰描边 + 轻阴影），样子不变。
private struct GlassCapsuleModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(interactiveGlass(reduceMotion: reduceMotion), in: Capsule())
        } else {
            content
                .background(Color(.systemBackground), in: Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(Color(.separator), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
        }
    }
}

/// 输入框的玻璃：主版本是 iOS 26 上固定圆角 23pt 的液态玻璃；
/// 低版本回退到实色 systemGray6——不是毛玻璃，输入框不要糊。
/// 圆角是死的、不跟框高走：Telegram 的做法，圆角 = 一行高的一半
/// （`floor(minimalInputHeight * 0.5)`，ChatTextInputPanelNode L3349），
/// 框长高只长高、不变圆——胶囊（圆角 = 高/2）打字一多就越变越圆，
/// 截图 31 里那个大药丸就是这么来的。
/// 描边撤了：一层原生玻璃，不自己加层（空框看不见就换玻璃 tint，不加描边）。
/// 对比版（Telegram）：框是实色圆角矩形（浅色 #F1F1F3、深色 #232E3C），
/// 圆角 17（floor(35 * 0.5)），不是玻璃——Telegram 的输入框本来就没有玻璃。
private struct GlassFieldModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ViewBuilder
    func body(content: Content) -> some View {
        if ChatTheme.isTelegramStyle {
            content.background(ChatTheme.textFieldBackgroundColor, in: RoundedRectangle(cornerRadius: ChatTheme.fieldCornerRadius))
        } else if #available(iOS 26.0, *) {
            content.glassEffect(interactiveGlass(reduceMotion: reduceMotion), in: RoundedRectangle(cornerRadius: 23))
        } else {
            content.background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 23))
        }
    }
}
