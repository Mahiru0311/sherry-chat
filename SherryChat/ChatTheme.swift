import SwiftUI
import UIKit

/// 聊天页的视觉主题：默认是信息 App 那套（主版本），
/// `TELEGRAM_STYLE` 编译条件开着就是 Telegram 那套（对比版）。
/// 两个版本共用同一份代码、同一套列表/输入/长按逻辑，
/// 只换颜色、尺寸和顶栏排布——对比版不是 Telegram 源码，
/// Telegram-iOS 是 UIKit + Texture、绑着整个 Telegram 的账号/
/// 数据库/网络栈，拆不出来单跑；这里是按它的行为与数字
/// （research/telegram-chat-page.md）在 SwiftUI 里重画的。
enum ChatTheme {
    /// 统一使用 iMessage 视觉，不再提供 Telegram 编译分支。
    static let isTelegramStyle = false

    // MARK: - 气泡颜色

    /// 自己发的气泡底：主版本是信息 App 的蓝；对比版是 Telegram 的淡绿
    /// （浅色 #E1FFC7、深色 #2B5278，Telegram 主题色板）。
    static func bubbleBackground(isFromMe: Bool) -> Color {
        #if TELEGRAM_STYLE
        if isFromMe {
            return Color(UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? UIColor(red: 0.169, green: 0.322, blue: 0.471, alpha: 1) // #2B5278
                    : UIColor(red: 0.882, green: 1.0, blue: 0.780, alpha: 1) // #E1FFC7
            })
        }
        return Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.094, green: 0.145, blue: 0.200, alpha: 1) // #182533
                : .white
        })
        #else
        return isFromMe ? .blue : Color(.systemGray5)
        #endif
    }

    /// 气泡里的字：主版本自己发的白字；对比版两边都跟随系统正文色
    /// （Telegram 淡绿气泡上是深色字、深色气泡上是白字）。
    static func bubbleForeground(isFromMe: Bool) -> Color {
        #if TELEGRAM_STYLE
        return .primary
        #else
        return isFromMe ? .white : .primary
        #endif
    }

    // MARK: - 气泡尺寸（Telegram 的数见 research/telegram-chat-page.md §2.2）

    /// 气泡最大宽：主版本 280（MessageKit 量的信息 App 数）；
    /// 对比版是屏宽 − 36（Telegram compactInset）。
    static var bubbleMaxWidth: CGFloat {
        #if TELEGRAM_STYLE
        return UIScreen.main.bounds.width - 36
        #else
        return 280
        #endif
    }

    /// 外角：主版本 18（MessageKit）；对比版 16（Telegram 默认）。
    static var bubbleOuterRadius: CGFloat {
        #if TELEGRAM_STYLE
        return 16
        #else
        return 18
        #endif
    }

    /// 贴着的内角：主版本 5；对比版 8（Telegram 默认，mergeBubbleCorners）。
    static var bubbleInnerRadius: CGFloat {
        #if TELEGRAM_STYLE
        return 8
        #else
        return 5
        #endif
    }

    /// 尾巴往外伸：主版本 5（MessageKit 弯尾巴 v2）；对比版 6（Telegram 尾巴列宽）。
    static var bubbleTailOut: CGFloat {
        #if TELEGRAM_STYLE
        return 6
        #else
        return 5
        #endif
    }

    /// 文字内边距：主版本尾巴侧 18 / 另一侧 14 / 上下 7（MessageKit）；
    /// 对比版左右 11 / 上下 6（Telegram text.bubbleInsets）。
    static var textInsetTailSide: CGFloat {
        #if TELEGRAM_STYLE
        return 11
        #else
        return 18
        #endif
    }

    static var textInsetOtherSide: CGFloat {
        #if TELEGRAM_STYLE
        return 11
        #else
        return 14
        #endif
    }

    static var textInsetVertical: CGFloat {
        #if TELEGRAM_STYLE
        return 6
        #else
        return 7
        #endif
    }

    /// 组和组之间 / 组里两条之间：主版本 8 / 2（信息 App）；
    /// 对比版 2 / 0（Telegram：组间 2pt + 1px、组内 0）。
    static var groupSpacing: CGFloat {
        #if TELEGRAM_STYLE
        return 2
        #else
        return 8
        #endif
    }

    static var withinGroupSpacing: CGFloat {
        #if TELEGRAM_STYLE
        return 0
        #else
        return 2
        #endif
    }

    // MARK: - 顶栏

    /// 顶栏内容高（不含状态栏）：统一采用 iMessage 的紧凑导航栏。
    /// 头像、名称和在线状态都在同一行，详情与工具按钮位于右侧。
    static var headerHeight: CGFloat {
        return 56
    }

    /// 对比版顶栏底：Telegram 的顶栏是实色条（浅色白、深色 #17212B），
    /// 不是玻璃/材质——主版本才用材质 + tint。
    static var headerBackgroundColor: Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.090, green: 0.129, blue: 0.169, alpha: 1) // #17212B
                : .white
        })
    }

    /// 对比版才有的行尾时间 + 状态：Telegram 把时间/勾放在气泡
    /// 最后一行行尾，不在气泡下面另起一行。
    static var showsInlineTimeAndStatus: Bool {
        #if TELEGRAM_STYLE
        return true
        #else
        return false
        #endif
    }

    // MARK: - 对比版（Telegram）输入面板与背景

    /// 输入面板底色：Telegram 的输入面板是满宽实色条（浅色白、深色 #17212B），
    /// 不是悬浮玻璃。主版本不用这项。
    static var inputPanelBackgroundColor: Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.090, green: 0.129, blue: 0.169, alpha: 1) // #17212B
                : .white
        })
    }

    /// 输入框底色（对比版）：浅色 #F1F1F3、深色 #232E3C 的实色圆角矩形，
    /// 不是玻璃。Telegram 的框就是一块实色底。
    static var textFieldBackgroundColor: Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.137, green: 0.180, blue: 0.235, alpha: 1) // #232E3C
                : UIColor(red: 0.945, green: 0.945, blue: 0.953, alpha: 1) // #F1F1F3
        })
    }

    /// 对比版默认聊天背景：Telegram 默认壁纸是带淡淡图案的底色，
    /// 浅色 #E7EBF0、深色 #0E1621。没有自定义壁纸时就用它，
    /// 不是系统底色——没图案的素底看着就不是 Telegram。
    static var chatBackgroundColor: Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.055, green: 0.086, blue: 0.129, alpha: 1) // #0E1621
                : UIColor(red: 0.906, green: 0.922, blue: 0.941, alpha: 1) // #E7EBF0
        })
    }

    /// 底栏总高：主版本 70（输入框 46 + 上下 padding 16 + 底边 8）；
    /// 对比版 57（Telegram：面板最小高 49 = 14 + 框 35，再加基高 8）。
    static var inputBarHeight: CGFloat {
        #if TELEGRAM_STYLE
        return 57
        #else
        return 70
        #endif
    }

    /// 消息行左右边距：主版本 12；对比版 3（Telegram edgeInset 3.0，
    /// 气泡几乎贴着屏幕边）。
    static var rowHorizontalPadding: CGFloat {
        #if TELEGRAM_STYLE
        return 3
        #else
        return 12
        #endif
    }

    /// 输入框上下 padding：主版本 12（框 46）；对比版 6
    /// （Telegram 框最小高 35：6 + 字约 23 + 6）。
    static var fieldVerticalPadding: CGFloat {
        #if TELEGRAM_STYLE
        return 6
        #else
        return 12
        #endif
    }

    /// 输入框圆角：主版本 23；对比版 17（Telegram：floor(35 * 0.5)）。
    static var fieldCornerRadius: CGFloat {
        #if TELEGRAM_STYLE
        return 17
        #else
        return 23
        #endif
    }

    /// 发送圆钮直径：对比版 40（Telegram 发送按钮组宽 40pt）。
    static var sendButtonSize: CGFloat {
        #if TELEGRAM_STYLE
        return 40
        #else
        return 44
        #endif
    }

    /// 输入行里三件的间距：主版本 10；对比版 8。
    static var inputRowSpacing: CGFloat {
        #if TELEGRAM_STYLE
        return 8
        #else
        return 10
        #endif
    }
}
