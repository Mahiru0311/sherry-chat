import Foundation
import Observation
import Security
import UIKit

/// 一条记忆：只存一句话 + 什么时候记的。
struct MemoryNote: Identifiable, Codable, Equatable {
    var id: UUID
    var text: String
    var createdAt: Date

    init(id: UUID = UUID(), text: String, createdAt: Date = Date()) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
    }
}

/// 测试连接的结果，画在 API 区下面。
enum ConnectionTestState: Equatable {
    case idle
    case testing
    case ok
    case failed(String)
}

/// 个人页的唯一数据口：SOUL、记忆、API 设置都在这里。
/// 以后接 AI 的客户端也从这里读：soul 当 system prompt，
/// 记忆拼成上下文。全部本地存，不上网。
/// Key 只进 Keychain，不进 UserDefaults、不进代码、不进日志。
@MainActor @Observable
final class AgentProfile {
    // MARK: - SOUL

    /// 雪莉的性格（以后就是 AI 的 system prompt）。
    /// 默认就是 Dolos 认识的那个雪莉，短短几句。
    var soul: String {
        didSet { saveSoul() }
    }

    /// 雪莉的名字（记忆页“更换名称”改的）：默认 Sherry，
    /// 显示在顶栏名字牌和个人页上，也进 AI 的 system prompt。
    var displayName: String {
        didSet { UserDefaults.standard.set(displayName, forKey: Keys.displayName) }
    }

    /// 头像文件在 Application Support 里的路径（只存路径串，
    /// 不存图本身）。没换过就是 nil，画默认的 sparkles 蓝圆。
    var avatarPath: String? {
        didSet { UserDefaults.standard.set(avatarPath, forKey: Keys.avatarPath) }
    }
    var avatarURL: URL? { avatarPath.map { URL(fileURLWithPath: $0) } }

    /// 聊天壁纸文件在 Application Support 里的路径。没设就是 nil，
    /// 聊天页是系统底色；设了就铺在消息列表后面（列表本身透明）。
    var wallpaperPath: String? {
        didSet { UserDefaults.standard.set(wallpaperPath, forKey: Keys.wallpaperPath) }
    }
    var wallpaperURL: URL? { wallpaperPath.map { URL(fileURLWithPath: $0) } }

    /// 壁纸的缩放与位移（step 89，编辑器调出来的）：scale 是相对
    /// 铺满（cover）的倍数，1 就是刚好铺满；offset 是相对居中的
    /// 位移（pt）。都进 UserDefaults，重启还在；渲染时
    /// WallpaperLayout 还会再夹一次，旧值不会留出白边。
    var wallpaperScale: CGFloat = 1 {
        didSet { UserDefaults.standard.set(wallpaperScale, forKey: Keys.wallpaperScale) }
    }
    var wallpaperOffset: CGSize = .zero {
        didSet {
            UserDefaults.standard.set(wallpaperOffset.width, forKey: Keys.wallpaperOffsetX)
            UserDefaults.standard.set(wallpaperOffset.height, forKey: Keys.wallpaperOffsetY)
        }
    }

    /// 壁纸的模糊 / 动态 / 亮度（step 92，Telegram 的三个开关）：
    /// 模糊是开关，动态是开关（手机倾斜时壁纸视差移），
    /// 亮度是 0–100 的滑杆（100 就是原图）。都进 UserDefaults，
    /// 重启还在；恢复默认壁纸时一起清掉。
    var wallpaperBlur: Bool = false {
        didSet { UserDefaults.standard.set(wallpaperBlur, forKey: Keys.wallpaperBlur) }
    }
    var wallpaperMotion: Bool = false {
        didSet { UserDefaults.standard.set(wallpaperMotion, forKey: Keys.wallpaperMotion) }
    }
    var wallpaperBrightness: Double = 100 {
        didSet { UserDefaults.standard.set(wallpaperBrightness, forKey: Keys.wallpaperBrightness) }
    }

    /// 记忆页那两个按钮立的 intent（step 80，不持久化）：
    /// 更换头像 / 更换名称点完，下一条发出的消息就是内容——
    /// 发图换头像、发字换名字。Conversation.send() 里消费，
    /// 没发对东西（换头像没发图、换名字没打字）flag 就留着等下一条。
    var pendingAvatarChange = false
    var pendingNameChange = false

    /// 换头像拷不动时的一句提示（step 83）：send() 里置上，
    /// ChatView 弹出来告诉用户，别悄悄留着 flag 等下一条误触发。
    var avatarChangeError: String? = nil

    /// SOUL 上次改动的日期，画在 SOUL 卡片下面。
    private(set) var soulUpdatedAt: Date

    // MARK: - 记忆

    var memories: [MemoryNote] {
        didSet { saveMemories() }
    }

    // MARK: - API 接入

    /// base URL 和模型名放 UserDefaults；Key 不放这里，只进 Keychain。
    var baseURL: String {
        didSet { UserDefaults.standard.set(baseURL, forKey: Keys.baseURL) }
    }

    var modelName: String {
        didSet { UserDefaults.standard.set(modelName, forKey: Keys.modelName) }
    }

    /// Key 有没有存进 Keychain。只存有没有，不存 Key 本身。
    private(set) var hasAPIKey = false

    /// 测试连接的状态，画在 API 区下面。
    var testState: ConnectionTestState = .idle

    /// API 配齐了没有：地址 + 模型 + Key 都有才算配齐。
    var isConfigured: Bool {
        hasAPIKey
            && !normalizedBaseURL.isEmpty
            && !modelName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// 给以后 AI 客户端的 system prompt：现在就是 SOUL 全文。
    /// 名字改过就补一句（step 80）：SOUL 里还写着“你是雪莉”，
    /// 不补这句 AI 下次还自称雪莉。
    var systemPrompt: String {
        var prompt = soul
        if displayName != "Sherry" {
            prompt += "\n\n你的名字是「\(displayName)」，请用这个名字称呼自己，不要再用“雪莉”这个名字。"
        }
        return prompt
    }

    /// 给以后 AI 客户端的上下文：记忆一行一条。
    var memoryContext: String {
        memories.map { "- \($0.text)" }.joined(separator: "\n")
    }

    init() {
        let defaults = UserDefaults.standard
        self.soul = defaults.string(forKey: Keys.soul) ?? Self.defaultSoul
        self.displayName = defaults.string(forKey: Keys.displayName) ?? "Sherry"
        self.avatarPath = defaults.string(forKey: Keys.avatarPath)
        self.wallpaperPath = defaults.string(forKey: Keys.wallpaperPath)
        let savedScale = defaults.double(forKey: Keys.wallpaperScale)
        self.wallpaperScale = savedScale >= 1 ? savedScale : 1
        self.wallpaperOffset = CGSize(
            width: defaults.double(forKey: Keys.wallpaperOffsetX),
            height: defaults.double(forKey: Keys.wallpaperOffsetY)
        )
        self.wallpaperBlur = defaults.bool(forKey: Keys.wallpaperBlur)
        self.wallpaperMotion = defaults.bool(forKey: Keys.wallpaperMotion)
        let savedBrightness = defaults.object(forKey: Keys.wallpaperBrightness) as? Double ?? 100
        self.wallpaperBrightness = min(max(savedBrightness, 0), 100)
        self.soulUpdatedAt = defaults.object(forKey: Keys.soulUpdatedAt) as? Date ?? Date()
        self.baseURL = defaults.string(forKey: Keys.baseURL) ?? ""
        self.modelName = defaults.string(forKey: Keys.modelName) ?? ""
        self.memories = Self.loadMemories()
        self.hasAPIKey = Self.readAPIKey() != nil
        // 存着的头像/壁纸路径可能是 stale 的（step 85，图 45）：
        // 路径在、文件没了或者解不出来时，顶栏画的是 LocalImage 的
        // 灰占位（深色下就是个纯黑圆），而不是默认的 sparkles 蓝圆。
        // 启动时验一遍：文件不在、或者不是一张能解出来的图，
        // 就把路径清掉、回到默认头像/系统底色，别留着黑圆。
        // 注意 init 里 didSet 不跑，清掉内存里的值不够，还得把
        // UserDefaults 里那条旧串也删了，不然下次启动又读回来。
        // 验的是本地小文件，启动时读一次，不影响平时。
        // 必须放在最后：Swift 规定所有 stored 属性都赋完值才能用 self。
        if let path = avatarPath, !Self.isDecodableImage(atPath: path) {
            avatarPath = nil
            defaults.removeObject(forKey: Keys.avatarPath)
        }
        if let path = wallpaperPath, !Self.isDecodableImage(atPath: path) {
            wallpaperPath = nil
            defaults.removeObject(forKey: Keys.wallpaperPath)
        }
    }

    // MARK: - 名字 / 头像 / 壁纸

    /// 改名（记忆页“更换名称”）：前后空格不要，空的不改，
    /// 最长 20 个字——名字牌装不下更长的。
    func setDisplayName(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        displayName = String(trimmed.prefix(20))
    }

    private static var profileFilesDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("profile")
    }

    /// 把一张图拷成头像（Application Support/profile/avatar-<uuid>.jpg），
    /// 成功才换。返回成功与否——拷不动就不换，旧头像留着。
    @discardableResult
    func setAvatar(from sourceURL: URL) -> Bool {
        setProfileImage(from: sourceURL, filePrefix: "avatar", keyPath: \.avatarPath)
    }

    /// 把一张图拷成聊天壁纸（Application Support/profile/wallpaper-<uuid>.jpg）。
    @discardableResult
    func setWallpaper(from sourceURL: URL) -> Bool {
        setProfileImage(from: sourceURL, filePrefix: "wallpaper", keyPath: \.wallpaperPath)
    }

    /// 恢复默认壁纸：文件删掉、路径清掉，聊天页回系统底色。
    /// 缩放位移也回到铺满居中，不然下次再设一张图还带着旧值。
    /// 模糊/动态/亮度也一起清掉。
    func removeWallpaper() {
        if let path = wallpaperPath {
            try? FileManager.default.removeItem(atPath: path)
        }
        wallpaperPath = nil
        wallpaperScale = 1
        wallpaperOffset = .zero
        wallpaperBlur = false
        wallpaperMotion = false
        wallpaperBrightness = 100
    }

    /// 壁纸编辑器调好的值（step 89 起，step 92 加了模糊/动态/亮度）：
    /// 编辑器那边已经夹过，这里只存；scale 小于 1 的按 1 算，
    /// 亮度夹在 0–100 里。
    func setWallpaperTransform(scale: CGFloat, offset: CGSize, blur: Bool, motion: Bool, brightness: Double) {
        wallpaperScale = max(1, scale)
        wallpaperOffset = offset
        wallpaperBlur = blur
        wallpaperMotion = motion
        wallpaperBrightness = min(max(brightness, 0), 100)
    }

    /// 文件在不在、能不能解成一张图：头像/壁纸路径的验货用。
    /// 路径只存串，文件没了、或者拷进来的是解不出来的东西时，
    /// 顶栏/聊天页不能拿个黑圆/空白顶着，要回到默认。
    private static func isDecodableImage(atPath path: String) -> Bool {
        guard FileManager.default.fileExists(atPath: path) else { return false }
        return UIImage(contentsOfFile: path) != nil
    }

    /// 头像 / 壁纸共用的拷法：每次写一个带 uuid 的新文件名，
    /// 旧文件删掉。文件名每次都变，地址才真的变——读图的 view
    /// （LocalImage / WallpaperView 的 .task）才会重新读；
    /// 原来固定叫 avatar.jpg / wallpaper.jpg，第二次换地址不变，
    /// 图就不刷新，Dolos 那边换了也看不见（step 83）。
    /// 拷完验一下解不解得出来（step 85）：拷进来的是解不出来的
    /// 东西时别把路径存下来——存了顶栏就是个黑圆；删掉、返回失败，
    /// 调用方弹一句“没换上”就行。
    private func setProfileImage(from sourceURL: URL, filePrefix: String, keyPath: ReferenceWritableKeyPath<AgentProfile, String?>) -> Bool {
        let dir = Self.profileFilesDirectory
        let dest = dir.appendingPathComponent("\(filePrefix)-\(UUID().uuidString).jpg")
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: sourceURL, to: dest)
            guard Self.isDecodableImage(atPath: dest.path) else {
                try? FileManager.default.removeItem(at: dest)
                return false
            }
            if let oldPath = self[keyPath: keyPath], oldPath != dest.path {
                try? FileManager.default.removeItem(atPath: oldPath)
            }
            self[keyPath: keyPath] = dest.path
            return true
        } catch {
            return false
        }
    }

    // MARK: - SOUL 存取

    private func saveSoul() {
        UserDefaults.standard.set(soul, forKey: Keys.soul)
        soulUpdatedAt = Date()
        UserDefaults.standard.set(soulUpdatedAt, forKey: Keys.soulUpdatedAt)
    }

    // MARK: - 记忆存取

    func addMemory(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        memories.append(MemoryNote(text: trimmed))
    }

    func updateMemory(id: UUID, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let index = memories.firstIndex(where: { $0.id == id })
        else { return }
        memories[index].text = trimmed
    }

    func removeMemories(at offsets: IndexSet) {
        memories.remove(atOffsets: offsets)
    }

    private static var memoriesFileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("sherry-memories.json")
    }

    /// 没有存过的记忆文件时，用几条 App 本来就知道的先顶上。
    private static func loadMemories() -> [MemoryNote] {
        let url = memoriesFileURL
        if let data = try? Data(contentsOf: url),
           let notes = try? JSONDecoder().decode([MemoryNote].self, from: data) {
            return notes
        }
        let seeded = [
            MemoryNote(text: "Dolos，中文名毛毛，不要叫 Ling。"),
            MemoryNote(text: "提醒和日程都按上海时间（Asia/Shanghai）。"),
            MemoryNote(text: "Dolos 喜欢《魔法少女的魔女审判》里的橘雪莉。"),
        ]
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(seeded).write(to: url)
        return seeded
    }

    private func saveMemories() {
        let url = Self.memoriesFileURL
        guard let data = try? JSONEncoder().encode(memories) else { return }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url)
    }

    // MARK: - Keychain（只存 Key）

    private static let keychainService = "com.sherry.chat.apikey"

    func saveAPIKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: "apikey",
        ]
        SecItemDelete(query as CFDictionary)
        var addQuery = query
        addQuery[kSecValueData as String] = Data(trimmed.utf8)
        SecItemAdd(addQuery as CFDictionary, nil)
        hasAPIKey = true
    }

    func deleteAPIKey() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: "apikey",
        ]
        SecItemDelete(query as CFDictionary)
        hasAPIKey = false
    }

    /// 发请求时才从 Keychain 读一次 Key（Conversation.send 里，
    /// 配齐了才调）。不存、不打日志、不回显。
    func apiKey() -> String? {
        Self.readAPIKey()
    }

    private static func readAPIKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: "apikey",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }
    /// Dsh-go 的做法（ccch1mneyyy/dsh-Go，AGPL-3.0，设置 › 模型 ›
    /// 添加渠道 / 渠道详情）：渠道和它的 Key 一起删。
    /// 这里只有一个自定义渠道，删了就是地址 + 模型 + Key 全清。
    func clearChannel() {
        baseURL = ""
        modelName = ""
        deleteAPIKey()
        testState = .idle
    }

    // MARK: - 地址归一化 + 测试连接

    /// 去首尾空格、去末尾 `/`、去尾部 `/v1`；没写协议就补 https；
    /// 官方域名 http 强制升 https。拼请求时再加 `/v1/...`。
    var normalizedBaseURL: String {
        var url = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while url.hasSuffix("/") { url.removeLast() }
        if url.hasSuffix("/v1") { url = String(url.dropLast("/v1".count)) }
        guard !url.isEmpty else { return "" }
        if !url.contains("://") { url = "https://" + url }
        if let host = URL(string: url)?.host,
           host == "api.openai.com", url.hasPrefix("http://") {
            url = "https://" + url.dropFirst("http://".count)
        }
        return url
    }

    /// 用 GET {base}/v1/models 试一下通不通，只报通/不通。
    /// Key 只放进请求头里，不打印、不进日志。
    /// Dsh-go 的测试连接也是这一招：用已保存的 Key 读模型列表，
    /// 不消耗 token；“已保存”不等于鉴权成功，测了才知道。
    func testConnection() async {
        testState = .testing
        let (_, error) = await fetchModelIDs()
        if let error {
            testState = .failed(error)
        } else {
            testState = .ok
        }
    }

    /// GET {base}/v1/models，成功返回模型 id 列表（Dsh-go 的“获取模型”，
    /// 勾选要用的模型；服务方不列模型时再手动填模型 ID）。
    /// 失败返回原因，和 testConnection 是一套说法。
    /// 返回 (模型列表, 错误原因)：只其一有值。没用 Result——
    /// Swift 6 里 Result 的 Failure 得是 Error，String 不合规。
    func fetchModelIDs() async -> ([String], String?) {
        let base = normalizedBaseURL
        guard !base.isEmpty else { return ([], "先填 base URL") }
        guard let url = URL(string: base + "/v1/models") else {
            return ([], "地址写错了，检查一下")
        }
        var request = URLRequest(url: url, timeoutInterval: 15)
        if let key = Self.readAPIKey() {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            switch code {
            case 200:
                let ids = (try? JSONDecoder().decode(ModelListResponse.self, from: data))?.data.map(\.id) ?? []
                return (ids.sorted(), nil)
            case 401:
                return ([], "连上了，但 Key 不对（401）")
            case 404:
                return ([], "连上了，但这个地址没有 /v1/models（404），检查 base URL")
            default:
                return ([], "连上了，但返回了 \(code)")
            }
        } catch {
            return ([], "连不上：\(error.localizedDescription)")
        }
    }
}

/// GET /v1/models 的返回：只要 data 里的 id。
private struct ModelListResponse: Decodable {
    var data: [ModelEntry]
}

private struct ModelEntry: Decodable {
    var id: String
}

// MARK: - 默认值

extension AgentProfile {
    /// 默认 SOUL：Dolos 认识的那个雪莉，短短几句。
    static let defaultSoul =
        "你是雪莉，自称名侦探、性格开朗的魔法少女。说话温柔爱笑，对有趣的事眼睛会亮起来；护着朋友，遇到谜题先冲上去。回答简短、像正常人聊天，别啰嗦，别端架子。"

    private enum Keys {
        static let soul = "agent.soul"
        static let soulUpdatedAt = "agent.soulUpdatedAt"
        static let displayName = "agent.displayName"
        static let avatarPath = "agent.avatarPath"
        static let wallpaperPath = "agent.wallpaperPath"
        static let wallpaperScale = "agent.wallpaperScale"
        static let wallpaperOffsetX = "agent.wallpaperOffsetX"
        static let wallpaperOffsetY = "agent.wallpaperOffsetY"
        static let wallpaperBlur = "agent.wallpaperBlur"
        static let wallpaperMotion = "agent.wallpaperMotion"
        static let wallpaperBrightness = "agent.wallpaperBrightness"
        static let baseURL = "agent.baseURL"
        static let modelName = "agent.modelName"
    }
}
