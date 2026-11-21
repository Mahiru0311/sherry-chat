import SwiftUI

/// 一条消息在它那组里的位置，决定气泡四个角怎么圆、有没有尾巴。
/// 信息 App 的规矩：组里上下挨着的两条，贴着的那两个角几乎是直角；
/// 只有一组里最后一条（或者单独一条）才有尾巴。
enum BubblePosition {
    case single
    case first
    case middle
    case last
}

/// 信息 App 的气泡形状：**一条连续轮廓**，不是身子 + 尾巴两块叠填——
/// 尾巴是轮廓本身往外拐、再拐回来，身子和尾巴同一个 Path 一次填完，
/// 交界处从原理上就没有缝。
///
/// 数字的出处（每一项都有来源，不凭感觉）：
/// 主版本（信息 App / MessageKit）：
/// - 外角 18pt、贴着的内角 5pt：贴着的角两边都变小——组里第一条的
///   两个下角、中间条的四个角、最后一条的两个上角都变内角，
///   气泡才连成一根柱子。
/// - 尾巴只在组内最后一条 / 单条上，往外 5pt、高 6pt（= 外角 18 的
///   三分之一）、尖端贴底边、不往下伸：MessageKit 弯尾巴 v2。
/// 对比版（Telegram，research/telegram-chat-page.md §2.2）：
/// 外角 16、内角 8、尾巴列宽 6pt。
/// 数字都从 ChatTheme 取，两个版本共用这一份画法。
/// 文字内边距、最大宽、间距不在这里：主版本尾巴侧 18 / 另一侧 14 /
/// 上下 7、最大宽 280、组内 2pt / 组间 8pt，都是 MessageKit 量的数；
/// 对比版左右 11 / 上下 6、最大宽屏宽 − 36、组内 0 / 组间 2pt，
/// 在 MessageCell 那边。
/// 尾巴在右边发的气泡上画，对方发的用整条路径 x 镜像。
struct BubbleShape: Shape {
    var isFromMe: Bool
    var position: BubblePosition

    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        // 短气泡别让圆角超过宽/高的一半，不然 addArc 会画坏。
        let outer = min(ChatTheme.bubbleOuterRadius, h / 2, w / 2)
        let inner = min(ChatTheme.bubbleInnerRadius, outer)
        // 贴着上一条的两个上角、贴着下一条的两个下角变小；
        // 不贴的角保持外角。
        let topRadius: CGFloat
        let bottomRadius: CGFloat
        switch position {
        case .single:
            topRadius = outer
            bottomRadius = outer
        case .first:
            topRadius = outer
            bottomRadius = inner
        case .middle:
            topRadius = inner
            bottomRadius = inner
        case .last:
            topRadius = inner
            bottomRadius = outer
        }
        let hasTail = position == .last || position == .single
        let tailH = min(6, h * 0.25)
        let tailOut: CGFloat = ChatTheme.bubbleTailOut
        let tailBase: CGFloat = 11

        var p = Path()
        // 先按“自己发、尾巴在右”画，再给对方发的整条镜像。
        p.move(to: CGPoint(x: topRadius, y: 0))
        p.addLine(to: CGPoint(x: w - topRadius, y: 0))
        p.addArc(tangent1End: CGPoint(x: w, y: 0), tangent2End: CGPoint(x: w, y: topRadius), radius: topRadius)
        if hasTail {
            p.addLine(to: CGPoint(x: w, y: h - tailH))
            // 钩形 quad：控制点 (w+2, h - tailH/2)，从竖边平滑拐出来、
            // 到尖端时斜向下——弯尾巴 v2 的样子，尖端是个软尖。
            p.addQuadCurve(
                to: CGPoint(x: w + tailOut, y: h),
                control: CGPoint(x: w + 2, y: h - tailH / 2)
            )
            // 回来沿着底边走直线，尖端贴着底边。
            p.addLine(to: CGPoint(x: w - tailBase, y: h))
        } else {
            p.addLine(to: CGPoint(x: w, y: h - bottomRadius))
            p.addArc(tangent1End: CGPoint(x: w, y: h), tangent2End: CGPoint(x: w - bottomRadius, y: h), radius: bottomRadius)
        }
        p.addLine(to: CGPoint(x: bottomRadius, y: h))
        p.addArc(tangent1End: CGPoint(x: 0, y: h), tangent2End: CGPoint(x: 0, y: h - bottomRadius), radius: bottomRadius)
        p.addLine(to: CGPoint(x: 0, y: topRadius))
        p.addArc(tangent1End: CGPoint(x: 0, y: 0), tangent2End: CGPoint(x: topRadius, y: 0), radius: topRadius)
        p.closeSubpath()

        if isFromMe {
            return p
        }
        // 对方发：整条路径左右镜像（尾巴在左、贴着的角在左下）。
        return p.applying(CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: w, ty: 0))
    }
}

/// 气泡的颜色：主版本自己发的蓝、对方发的灰，深浅色都跟着系统走；
/// 对比版是 Telegram 的淡绿/白（浅色）和蓝灰（深色），见 ChatTheme。
enum BubbleColors {
    static func background(isFromMe: Bool) -> Color {
        ChatTheme.bubbleBackground(isFromMe: isFromMe)
    }

    static func foreground(isFromMe: Bool) -> Color {
        ChatTheme.bubbleForeground(isFromMe: isFromMe)
    }
}

/// 日期行：信息 App 那种居中的小灰字。
/// 今天 / 昨天 / 星期几 / 具体日期，时间是短格式。
enum DateLabel {
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f
    }()

    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE HH:mm"
        return f
    }()

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    static func text(for date: Date, relativeTo now: Date = Date()) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "今天 " + timeFormatter.string(from: date)
        }
        if calendar.isDateInYesterday(date) {
            return "昨天 " + timeFormatter.string(from: date)
        }
        if let weekAgo = calendar.date(byAdding: .day, value: -7, to: now),
           date > weekAgo {
            return weekdayFormatter.string(from: date)
        }
        return dateFormatter.string(from: date)
    }
}
