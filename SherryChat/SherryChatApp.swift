import AVFoundation
import Speech
import SwiftUI

/// 自研 v2 版 Sherry Chat 的入口。第一阶段只有一个聊天页，
/// 不接任何网络，不用 swift-chat。
/// 个人页的唯一数据口（AgentProfile：SOUL、记忆、API 设置）
/// 在这里建一份，全 App 共用——以后接 AI 的客户端也从这里读。
@main
struct SherryChatApp: App {
    @State private var profile = AgentProfile()
    @State private var toolsStore = ToolsStore()

    var body: some Scene {
        WindowGroup {
            AppShell()
                .environment(profile)
                .environment(toolsStore)
                .task {
                    // 听写预检：首次打开时把语音识别 + 麦克风授权
                    // 提前走一遍，只打印、不阻塞 UI。
                    await precheckDictationPermissions()
                }
        }
    }
}

/// 首次打开时请求语音识别 + 麦克风授权，并把状态打印出来。
/// 只跑一次授权流程：系统以前弹过、已决定过的不会再弹。
private func precheckDictationPermissions() async {
    let speechStatus = await withCheckedContinuation { continuation in
        SFSpeechRecognizer.requestAuthorization { status in
            continuation.resume(returning: status)
        }
    }
    let micGranted = await withCheckedContinuation { continuation in
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            continuation.resume(returning: granted)
        }
    }
    let recognizer = SFSpeechRecognizer()
    print(
        "[SherryChat] dictation precheck: speech=\(speechStatus.rawValue) "
            + "mic=\(micGranted) recognizerAvailable=\(recognizer?.isAvailable ?? false) "
            + "locale=\(Locale.current.identifier)"
    )
}
