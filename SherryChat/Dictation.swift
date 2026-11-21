import AVFoundation
import Combine
import Speech

/// 输入框右边的麦克风：点一下开始听写，再点一下停。
/// 用系统 Speech 框架（SFSpeechRecognizer）：说话的时候字一句一句出来，
/// 停了就留在输入框里等发送。失败必须告诉用户（errorMessage），
/// 每种失败都有一句人话，ChatView 用 alert 弹出来，不许点了没反应。
@MainActor
final class DictationManager: NSObject, ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var unavailable = false
    /// 正在等系统回授权：这段时间里再点一次麦克风是取消，
    /// 不是再开一回——没这个状态，授权回来之前点的第二下
    /// 会又开一次，听写就关不掉了。
    @Published private(set) var isStarting = false

    /// 最近一次听写失败的原因（用户能看懂的话）。ChatView 盯着它弹 alert；
    /// 成功开始一次听写就清掉。
    @Published var errorMessage: String?

    /// 听写出来的字（半句也会先给出来）。ChatView 盯着它，
    /// 接在开始听写时输入框里已有的字后面。
    @Published var liveText = ""

    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var engine: AVAudioEngine?
    /// 开听写的代次：每次 start / cancelStart 都 +1，
    /// 授权回调只认当前这一代——取消了的那次回来就作废。
    private var startEpoch = 0

    func start() {
        errorMessage = nil
        let recognizer = SFSpeechRecognizer()
        guard let recognizer, recognizer.isAvailable else {
            unavailable = true
            errorMessage = "语音识别当前不可用，可能是网络不通或系统服务没准备好，稍后再试一次。"
            return
        }
        self.recognizer = recognizer
        isStarting = true
        startEpoch += 1
        let epoch = startEpoch

        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            Task { @MainActor in
                guard let self else { return }
                // 不是这一代的回调（中间取消过、又开了一回）：
                // 作废，什么都不做。
                guard epoch == self.startEpoch else { return }
                self.isStarting = false
                switch status {
                case .authorized:
                    self.beginSession(with: recognizer)
                case .denied, .restricted:
                    self.unavailable = true
                    self.errorMessage = "语音识别未授权：请去“设置 → 隐私与安全 → 语音识别”里打开 Sherry Chat，再点一次麦克风。"
                case .notDetermined:
                    self.unavailable = true
                    self.errorMessage = "语音识别还没决定授权，请再点一次麦克风，系统弹授权时点“好”。"
                @unknown default:
                    self.unavailable = true
                    self.errorMessage = "语音识别授权状态未知，请再试一次。"
                }
            }
        }
    }

    /// 授权还没回来时取消：代次 +1，让已经在路上的那次授权回调回来就作废。
    func cancelStart() {
        startEpoch += 1
        isStarting = false
    }

    private func beginSession(with recognizer: SFSpeechRecognizer) {
        let engine = AVAudioEngine()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            unavailable = true
            errorMessage = "没能打开麦克风：请检查“设置 → 隐私与安全 → 麦克风”里的开关，再试一次。"
            return
        }

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    self.liveText = result.bestTranscription.formattedString
                    if result.isFinal {
                        self.stop()
                    }
                } else if error != nil {
                    // 正常点停会 cancel 任务，那时 isRecording 已经是 false，
                    // 别把“自己点的停”当成失败报出来。
                    if self.isRecording {
                        self.errorMessage = "听写中断了，可能是网络问题，请再试一次。"
                        self.stop()
                    }
                }
            }
        }

        self.engine = engine
        self.request = request
        do {
            try engine.start()
            isRecording = true
            unavailable = false
        } catch {
            stop()
            unavailable = true
            errorMessage = "听写启动失败，请再试一次。"
        }
    }

    func stop() {
        engine?.stop()
        engine?.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        engine = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        isRecording = false
        isStarting = false
    }
}
