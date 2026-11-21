import PhotosUI
import SwiftUI
import UIKit

/// 点头像进来的个人页（Dolos 2026-11-18：照 Muse App 的个人页样子）。
/// 上面大头像 + 名字 + 连接状态，中间一条胶囊菜单（SOUL 与记忆 / 连接），
/// SOUL 和记忆放一个菜单、两张卡并排（图三），连接单独一个菜单——
/// 不再是三个菜单、也不再把三块堆在一页上（截图 26、32 的毛病）。
/// - × 不在工具栏里：iOS 26 会给工具栏按钮自己再画一层玻璃圆，
///   跟我们画的灰圆叠成两层（截图 26 左上角）；现在 × 是内容里
///   一行自己的按钮，只有一个圆。
/// - 右上角分享删了（Dolos：没必要）。
/// - SOUL、记忆、API 的编辑器还是原来的那几份，只按菜单分开摆。
struct ProfileView: View {
    @Environment(AgentProfile.self) private var profile
    @Environment(\.dismiss) private var dismiss

    @Environment(ToolsStore.self) private var toolsStore
    @State private var selectedTab: ProfileTab = .soulMemory
    @State private var showTools = false
    @State private var showSoulEditor = false
    @State private var soulDraft = ""
    /// 记忆列表不再嵌在页里（step 63）：点记忆卡开单独一页。
    @State private var showMemoryList = false
    /// 更换壁纸（step 81）：个人页右上角，先弹个小菜单问
    /// 选照片还是恢复默认，选照片再开系统相册。
    @State private var showWallpaperDialog = false
    @State private var showWallpaperPicker = false
    @State private var wallpaperItem: PhotosPickerItem?
    /// 壁纸没换上时的提示（step 82）：之前失败是悄悄没的，
    /// 现在弹一句，让她知道是没换上、不是没点到。
    @State private var wallpaperError = ""
    @State private var showWallpaperError = false
    /// 小菜单里点了“选择照片”先记下来（step 83）：菜单还在收，
    /// 这时开相册会被吞掉；等菜单收完（showWallpaperDialog 变 false）
    /// 再开，见下面 onChange。
    @State private var pendingWallpaperPick = false
    /// 壁纸编辑器（step 89，Telegram 的逻辑）：选完照片先调再贴。
    /// 刚选出来的那张图和数据先放这儿，编辑器调好点“完成”
    /// 才真的存；点“取消”就丢掉，个人页还在。
    @State private var wallpaperPickData: Data?
    @State private var wallpaperPickImage: UIImage?
    @State private var showWallpaperEditor = false
    /// 编辑器点了“完成”、图已经存好了：编辑器收完再关个人页，
    /// 回聊天页当场看到新壁纸（见下面 onChange）。
    @State private var wallpaperApplied = false
    /// 头像铅笔徽标的菜单（step 84）：原来是手搭的玻璃卡 + 根上
    /// 的点按收起（step 82）——看着是 iOS 玻璃，收起/弹簧/震动
    /// 都得自己写，Dolos 说“没有交互逻辑”。现在直接用系统 Menu：
    /// 玻璃菜单、系统弹簧、点别处自动收起、震动都是系统给的。
    /// 两行不变：更换虚拟形象 / 编辑名称，没有“更改声音”。

    private static var shortDate: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "yy.MM.dd"
        return formatter
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                topBar
                avatarBlock
                menuPill
                sectionContent
                // 最下面一行小字构建号（step 69）：只用来确认装的是哪一版——
                // 每次发新包这行跟着改，Dolos 报回这行写的是什么，
                // 就知道她装的是不是最新版，不用再猜是不是装错了包。
                Text("Sherry Chat · 构建 step-94")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .background(Color(.systemBackground))
        .sheet(isPresented: $showSoulEditor) { soulEditor }
        .sheet(isPresented: $showMemoryList) { memoryListSheet }
        .sheet(isPresented: $showTools) {
            ToolPickerSheet()
                .environment(toolsStore)
        }
        // 更换壁纸（step 81：从记忆页挪到个人页右上角）：
        // step 83 又改了这条链（Dolos：选壁纸还是没效果）：
        // 小菜单收起的同时开相册，presentation 会被吞掉——step 82
        // 用 350ms 兜了一次，她那边还是没弹出来，而且 showWallpaperPicker
        // 一旦置 true 就卡在 true，再点也没反应。现在不经过小菜单了：
        // 没设过壁纸，点按钮直接开相册（Telegram 也是点一下直接进
        // 相册/图库）；已经设了，才弹小菜单（换一张 / 恢复默认 / 取消），
        // 换一张也不在菜单里直接开，只记个 pending，等菜单收完再开
        // （见下面 onChange(of: showWallpaperDialog)）。
        // 每一步还是验、断了就弹一句“没换上”；换成了关掉个人页，
        // 回聊天页当场看到新壁纸。
        .confirmationDialog("更换壁纸", isPresented: $showWallpaperDialog) {
            Button("选择照片") {
                // 只记下来，不在这里开相册：菜单还在收，sheet 顶不上来。
                pendingWallpaperPick = true
            }
            if profile.wallpaperURL != nil {
                Button("恢复默认", role: .destructive) {
                    profile.removeWallpaper()
                    // 回默认也一样：关掉个人页，回到聊天页当场看到。
                    dismiss()
                }
            }
            Button("取消", role: .cancel) {}
        }
        .onChange(of: showWallpaperDialog) { _, isShowing in
            // 小菜单收完了、又确实点了“选择照片”，这时再开相册：
            // presentation 不会被收起中的菜单吞掉。
            if !isShowing, pendingWallpaperPick {
                pendingWallpaperPick = false
                showWallpaperPicker = true
            }
        }
        .photosPicker(isPresented: $showWallpaperPicker, selection: $wallpaperItem, matching: .images)
        .onChange(of: wallpaperItem) { _, item in
            guard let item else { return }
            wallpaperItem = nil
            Task {
                // 选完先不贴：数据读出来、解成图，交给编辑器先调
                // （step 89，Telegram 的逻辑：捏合缩放、拖动移动，
                // 调好点“完成”才贴）。解不出来才是真的没换上。
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let picked = UIImage(data: data) else {
                    wallpaperError = "壁纸没换上，再试一次"
                    showWallpaperError = true
                    return
                }
                wallpaperPickData = data
                wallpaperPickImage = picked
                showWallpaperEditor = true
            }
        }
        // 壁纸编辑器（step 89）：全屏盖上来，图就是整屏。
        // 完成：存图 + 存调好的缩放位移，收掉编辑器；
        // 取消：什么都不存，编辑器收掉、个人页还在。
        .fullScreenCover(isPresented: $showWallpaperEditor) {
            if let picked = wallpaperPickImage {
                // 新图进编辑器一律从默认开始（step 93，图 53）：
                // 缩放 1、没位移、模糊关、动态关、亮度 100。
                // 原来这里传的是上一张壁纸留下的模糊/动态/亮度，
                // 换新图还开着——上一张开着糊，这张一贴上也是糊的，
                // 她还以为是新图本身的问题。默认就是“关”，
                // 想糊自己再开；关在聊天页里就是真关，不糊。
                WallpaperEditorView(
                    image: picked,
                    onConfirm: { edit in confirmWallpaper(edit) },
                    onCancel: {
                        wallpaperPickData = nil
                        wallpaperPickImage = nil
                        showWallpaperEditor = false
                    }
                )
            }
        }
        .onChange(of: showWallpaperEditor) { _, isShowing in
            // 编辑器收完了、图也存好了：这时再关个人页，
            // 回聊天页当场看到新壁纸。等编辑器收完再关，
            // 两个 dismiss 不会顶在一起。
            if !isShowing, wallpaperApplied {
                wallpaperApplied = false
                wallpaperPickData = nil
                wallpaperPickImage = nil
                dismiss()
            }
        }
        .alert("壁纸", isPresented: $showWallpaperError) {
            Button("好") {}
        } message: {
            Text(wallpaperError)
        }
    }

    /// 编辑器点了“完成”（step 89 起，step 92 多了模糊/动态/亮度）：
    /// 图存进去、调好的值也存进去，然后收掉编辑器；个人页是编辑器
    /// 收完才关的（上面 onChange(of: showWallpaperEditor)），不顶在一起。
    /// 存不进去就弹一句“没换上”，编辑器还开着、可以再点一次完成。
    private func confirmWallpaper(_ edit: WallpaperEdit) {
        guard let data = wallpaperPickData else { return }
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("wallpaper-pick.jpg")
        guard (try? data.write(to: tempURL)) != nil,
              profile.setWallpaper(from: tempURL) else {
            wallpaperError = "壁纸没换上，再试一次"
            showWallpaperError = true
            return
        }
        profile.setWallpaperTransform(scale: edit.scale, offset: edit.offset, blur: edit.blur, motion: edit.motion, brightness: edit.brightness)
        wallpaperApplied = true
        showWallpaperEditor = false
    }

    // MARK: - 顶上一行：左 ×、右壁纸（step 82）
    // × 是 44pt 大玻璃圆（Dolos：原来 36pt 太小了）；
    // 右上角是壁纸按钮：44pt 玻璃圆 + 图标（图 40 的 Muse
    // 个人页右上角就是个圆圈图标），不再把“更换壁纸”四个字
    // 直接写上面（Dolos 22:15）。
    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .glassCircleFill()
            }
            .buttonStyle(.plain)
            Spacer()
            Button {
                // 没设过壁纸：直接开相册，不经过小菜单（step 83）——
                // 小菜单收起的同时开相册会被吞掉，Dolos 那边点了
                // 还是没弹出来。已经设了：才弹小菜单（换一张 /
                // 恢复默认 / 取消），换一张等菜单收完再开。
                if profile.wallpaperURL == nil {
                    showWallpaperPicker = true
                } else {
                    showWallpaperDialog = true
                }
            } label: {
                Image(systemName: "photo.on.rectangle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .glassCircleFill()
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 8)
    }

    // MARK: - 头像 + 名字 + 状态 + SOUL 预览

    private var avatarBlock: some View {
        VStack(spacing: 8) {
            // 头像 + 右下角的铅笔徽标（step 82，图 40）：小玻璃圆
            // 里一支铅笔，压在头像右下角边上。点它弹系统 Menu
            // （step 84：原来手搭的玻璃卡 + 根上的点按收起，
            // 看着是玻璃、交互全得自己写；系统 Menu 的弹簧、
            // 点别处收起、震动都是现成的）。
            ZStack(alignment: .bottomTrailing) {
                // 头像：换过就用换的图（step 80/81，个人页“更换头像”），
                // 没换过就是原来的 sparkles 蓝圆。
                if let avatarURL = profile.avatarURL {
                    LocalImage(url: avatarURL, pixelWidth: nil, pixelHeight: nil, fixedSize: CGSize(width: 96, height: 96))
                        .clipShape(Circle())
                } else {
                    Image(systemName: "sparkles")
                        .font(.system(size: 36, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 96, height: 96)
                        .background(Color.accentColor, in: Circle())
                }
                Menu {
                    Button {
                        profile.pendingAvatarChange = true
                        dismiss()
                    } label: {
                        Label("更换虚拟形象", systemImage: "person.circle")
                    }
                    Button {
                        profile.pendingNameChange = true
                        dismiss()
                    } label: {
                        Label("编辑名称", systemImage: "pencil")
                    }
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 32, height: 32)
                        .glassCircleFill()
                }
                .offset(x: 4, y: 4)
            }
            Text(profile.displayName)
                .font(.title2)
                .bold()
            HStack(spacing: 4) {
                Image(systemName: "bolt.fill")
                Text(profile.isConfigured ? "已连接" : "未连接")
            }
            .font(.subheadline)
            .fontWeight(.semibold)
            .foregroundStyle(profile.isConfigured ? .green : .secondary)
            Text(profile.soul)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
        }
        .padding(.top, 8)
    }

    // MARK: - 胶囊菜单：SOUL 与记忆 / 连接（照 Muse 那条 pill 的样子）
    // 整条是一层原生液态玻璃（step 64）：原来是 systemGray5 的扁平
    // 灰底，图 33 深色下就是一条死灰；玻璃在深色浅色下都是真材质。
    // 选中的那段还是原来的实色药丸 + 轻阴影，嵌在玻璃里面——
    // 那是段内的填充，不是第二层玻璃。
    private var menuPill: some View {
        VStack(spacing: 0) {
            ForEach(ProfileTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { selectedTab = tab }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: tab.icon)
                            .foregroundStyle(.tint)
                            .frame(width: 24)
                        Text(tab.title)
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 48)
                }
                .buttonStyle(.plain)
                if tab != ProfileTab.allCases.last {
                    Divider().padding(.leading, 52)
                }
            }
        }
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.35), lineWidth: 0.5))
    }

    // MARK: - 菜单内容：一次只显示一个菜单

    @ViewBuilder
    private var sectionContent: some View {
        switch selectedTab {
        case .soulMemory:
            soulMemorySection
        case .connection:
            APISectionView(profile: profile)
        case .tools:
            toolsSection
        }
    }

    private var toolsSection: some View {
        Button { showTools = true } label: {
            HStack(spacing: 14) {
                Image(systemName: "wand.and.stars")
                    .font(.title2)
                    .foregroundStyle(.tint)
                    .frame(width: 34)
                VStack(alignment: .leading, spacing: 4) {
                    Text("MCP 与 Skills")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("已启用 \(toolsStore.enabledTools.count) 个工具，管理可用能力")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
    }

    /// SOUL 与记忆一个菜单（Dolos 2026-11-18：看图三，两张卡并排）。
    /// 上面是 SOUL 的文字预览，下面两张卡：SOUL 卡点开改性格，
    /// 记忆卡点开单独一页看记忆（step 63：“共几条”和下面那列
    /// 记忆列表没必要写——卡上只留“点一点查看”，列表挪到单独一页里）。
    private var soulMemorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(profile.soul)
                .font(.body)
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button {
                    soulDraft = profile.soul
                    showSoulEditor = true
                } label: {
                    ProfileCard(
                        title: "SOUL",
                        footnote: "点一点编辑",
                        bottomText: "更新于 \(Self.shortDate.string(from: profile.soulUpdatedAt))",
                        icon: "heart.fill",
                        color: Color(red: 0.64, green: 0.55, blue: 0.40)
                    )
                }
                .buttonStyle(.plain)
                Button {
                    showMemoryList = true
                } label: {
                    ProfileCard(
                        title: "记忆",
                        footnote: "点一点查看",
                        bottomText: latestMemoryText,
                        icon: "message.fill",
                        color: Color(red: 0.20, green: 0.55, blue: 0.35)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// 记忆单独一页：原来嵌在卡下面的那列列表整个搬进来，
    /// 点一条改、垃圾桶删、“加一条”加——功能一个没少，
    /// 只是不在主页面上占地方了。
    /// 左上角 × 是 44pt 的大玻璃圆（step 80）；右上角只有“完成”。
    /// 更换壁纸 / 换头像 / 换名字不在这页（step 81：Dolos 说
    /// 它们属于个人页，记忆页只留记忆列表）。
    private var memoryListSheet: some View {
        NavigationStack {
            ScrollView {
                MemorySectionView(profile: profile)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
            }
            .navigationTitle("记忆")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showMemoryList = false } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 44, height: 44)
                            .glassCircleFill()
                    }
                    .buttonStyle(.plain)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { showMemoryList = false }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    /// 记忆卡底下那行小字：最近一条记忆的日期，没有就写没有。
    private var latestMemoryText: String {
        if let latest = profile.memories.map(\.createdAt).max() {
            "最近 \(Self.shortDate.string(from: latest))"
        } else {
            "还没有记忆"
        }
    }

    // MARK: - SOUL 编辑器

    private var soulEditor: some View {
        NavigationStack {
            TextEditor(text: $soulDraft)
                .padding()
                .navigationTitle("SOUL")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("取消") { showSoulEditor = false }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("保存") {
                            profile.soul = soulDraft
                            showSoulEditor = false
                        }
                        .fontWeight(.semibold)
                    }
                }
        }
        .presentationDetents([.medium, .large])
    }
}

/// 菜单分两项：SOUL 与记忆放一起（两张卡并排，照图三），连接单独一项。
/// 一个菜单只管自己那块内容。
private enum ProfileTab: String, CaseIterable {
    case soulMemory
    case connection
    case tools

    var title: String {
        switch self {
        case .soulMemory: return "SOUL 与记忆"
        case .connection: return "连接"
        case .tools: return "工具"
        }
    }

    var icon: String {
        switch self {
        case .soulMemory: return "heart.fill"
        case .connection: return "bolt.fill"
        case .tools: return "wand.and.stars"
        }
    }
}

/// 卡片本体：标题 + 一行小字 + 底部日期 + 右下角小图标。
/// 颜色是固定的棕/绿（照参考图），白字。
private struct ProfileCard: View {
    var title: String
    var footnote: String
    var bottomText: String
    var icon: String
    var color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title2)
                .bold()
            Text(footnote)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.85))
            Spacer()
            Text(bottomText)
                .font(.subheadline)
        }
        .foregroundStyle(.white)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 160)
        .background(color, in: RoundedRectangle(cornerRadius: 20))
        .overlay(alignment: .bottomTrailing) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.white.opacity(0.9))
                .padding(16)
        }
    }
}

/// 记忆单独一页的内容（step 63：从卡下面搬出来，不再嵌在主页面里）。
/// 点一条改，每条右边有个垃圾桶点一下就删，上面“加一条”新写一条。
/// 加、改都是原来的 sheet，没变。
/// 换头像 / 换名字 / 换壁纸不在这页（step 81：它们属于个人页）。
private struct MemorySectionView: View {
    @Bindable var profile: AgentProfile
    @State private var showAdd = false
    @State private var newText = ""
    @State private var editing: MemoryNote?
    @State private var editText = ""

    private static var shortDate: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "yy.MM.dd"
        return formatter
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 头上只剩“加一条”——“共几条”删了（step 63，Dolos：没必要写）。
            HStack {
                Spacer()
                // “加一条”是玻璃药丸（step 62）：原来 `.bordered`
                // 是扁平的灰底，深色下跟记忆列表的底混在一起；玻璃
                // 在深色浅色下都看得清。记忆卡右下角那个 message.fill
                // 图标不用动——它画在绿卡上，卡本身就是实色（照图三）。
                Button { showAdd = true } label: {
                    Label("加一条", systemImage: "plus")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .glassPanelFill(cornerRadius: 14)
                }
                .buttonStyle(.plain)
            }
            if profile.memories.isEmpty {
                Text("还没有记忆，点“加一条”写一句。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(profile.memories) { note in
                    HStack(alignment: .top, spacing: 8) {
                        Button {
                            editing = note
                            editText = note.text
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(note.text)
                                    .font(.body)
                                Text(Self.shortDate.string(from: note.createdAt))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Button {
                            if let index = profile.memories.firstIndex(where: { $0.id == note.id }) {
                                profile.removeMemories(at: IndexSet(integer: index))
                            }
                        } label: {
                            // 垃圾桶是玻璃圆里的红图标（step 62）：原来是光秃秃的
                            // 红图标，没有底、深色下不好点、也不像个按钮。
                            Image(systemName: "trash")
                                .font(.system(size: 15))
                                .foregroundStyle(.red)
                                .frame(width: 32, height: 32)
                                .glassCircleFill()
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 4)
                    if note.id != profile.memories.last?.id {
                        Divider()
                    }
                }
            }
        }
        // 单独一页了，不再是卡下面那块圆角灰底——页本身就是 ScrollView，
        // 列表直接铺在页上。
        .sheet(isPresented: $showAdd) {
            NavigationStack {
                VStack(spacing: 16) {
                    TextField("写一句要记住的事…", text: $newText, axis: .vertical)
                        .lineLimit(3...6)
                        .textFieldStyle(.roundedBorder)
                    Spacer()
                }
                .padding()
                .navigationTitle("新记忆")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("取消") { showAdd = false }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("保存") {
                            profile.addMemory(newText)
                            newText = ""
                            showAdd = false
                        }
                        .fontWeight(.semibold)
                        .disabled(newText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .presentationDetents([.medium])
        }
        .sheet(item: $editing) { note in
            NavigationStack {
                TextEditor(text: $editText)
                    .padding()
                    .navigationTitle("改记忆")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("取消") { editing = nil }
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("保存") {
                                profile.updateMemory(id: note.id, text: editText)
                                editing = nil
                            }
                            .fontWeight(.semibold)
                            .disabled(editText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
            }
            .presentationDetents([.medium, .large])
        }
    }
}

/// API 接入区（step 66，照 Dsh-go 重做：ccch1mneyyy/dsh-Go，AGPL-3.0，
/// 设置 › 模型 › 渠道页，行为和数字只参考、不抄代码——它是 Flutter，
/// 代码本来也粘不过来）。
/// Dsh-go 的做法：设置按要做的事分组，进子页的行右侧显示当前状态；
/// 顶部一张卡显示账号/Key 和状态；渠道分官方/订阅/自定义三组，
/// 自定义渠道填兼容协议 + Base URL + API Key，点“获取模型”勾选
/// 要用的模型，没有列表就手动填模型 ID；测试连接用已保存的 Key
/// 读模型列表，不消耗 token；“已保存”不等于鉴权成功，测了才知道；
/// API Key 留空就是保留原来的；删渠道时地址、模型和 Key 一起删。
/// 我们只有一个自定义渠道（OpenAI 兼容），就按这个样子摆：
/// 上面一张状态卡，下面一张渠道卡（每行左边是项、右边是当前值，
/// 点进去改），再加测试连接和删除渠道。
/// Key 只进 Keychain：SecureField 只用来输新 Key，输完点保存
/// 才写进去、输入框立刻清掉；界面只显示“已保存/未保存”，
/// 不回显 Key、不进日志。
private struct APISectionView: View {
    @Bindable var profile: AgentProfile

    @State private var showBaseURLEditor = false
    @State private var baseURLDraft = ""
    @State private var showKeyEditor = false
    @State private var keyInput = ""
    @State private var showModelEditor = false
    @State private var modelDraft = ""
    @State private var availableModels: [String] = []
    @State private var modelsLoading = false
    @State private var modelsError: String?
    @State private var showDeleteConfirm = false

    var body: some View {
        VStack(spacing: 12) {
            statusCard
            channelCard
            Button("删除渠道", role: .destructive) {
                showDeleteConfirm = true
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .glassPanelFill(cornerRadius: 20)
            .buttonStyle(.plain)
            .alert("删掉这个渠道？", isPresented: $showDeleteConfirm) {
                Button("取消", role: .cancel) {}
                Button("删除", role: .destructive) {
                    profile.clearChannel()
                }
            } message: {
                Text("地址、模型和 API Key 一起删掉。")
            }
        }
        .sheet(isPresented: $showBaseURLEditor) { baseURLEditor }
        .sheet(isPresented: $showKeyEditor) { keyEditor }
        .sheet(isPresented: $showModelEditor) { modelEditor }
    }

    // MARK: - 顶部状态卡（Dsh-go 设置页顶部的账号卡）

    /// 一行状态 + 一行现状：配齐了写地址域名和模型名，
    /// 没配齐写还差哪几项，不写“未连接”就完了。
    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "bolt.fill")
                Text(profile.isConfigured ? "已连接" : "未连接")
            }
            .font(.headline)
            .foregroundStyle(profile.isConfigured ? .green : .secondary)
            Text(statusDetail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassPanelFill(cornerRadius: 20)
    }

    private var statusDetail: String {
        if profile.isConfigured {
            let host = URL(string: profile.normalizedBaseURL)?.host ?? profile.normalizedBaseURL
            return "\(host) · \(profile.modelName)"
        }
        var missing: [String] = []
        if profile.normalizedBaseURL.isEmpty { missing.append("地址") }
        if !profile.hasAPIKey { missing.append("Key") }
        if profile.modelName.trimmingCharacters(in: .whitespaces).isEmpty { missing.append("模型") }
        return "还差" + missing.joined(separator: "、") + "，填好下面就能连上。"
    }

    // MARK: - 渠道卡：每行左边是项、右边是当前值，点进去改

    private var channelCard: some View {
        VStack(spacing: 0) {
            channelRow(label: "兼容协议", value: "OpenAI 兼容")
            Divider().padding(.leading, 16)
            channelRow(label: "Base URL", value: baseURLDisplay) {
                baseURLDraft = profile.baseURL
                showBaseURLEditor = true
            }
            Divider().padding(.leading, 16)
            channelRow(
                label: "API Key",
                value: profile.hasAPIKey ? "已保存" : "未保存",
                valueColor: profile.hasAPIKey ? .green : .secondary
            ) {
                keyInput = ""
                showKeyEditor = true
            }
            Divider().padding(.leading, 16)
            channelRow(
                label: "模型",
                value: profile.modelName.isEmpty ? "未设置" : profile.modelName
            ) {
                modelDraft = profile.modelName
                availableModels = []
                modelsError = nil
                showModelEditor = true
            }
            Divider().padding(.leading, 16)
            testRow
            if profile.testState != .idle {
                testResultView
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }
        }
        .glassPanelFill(cornerRadius: 20)
    }

    /// 地址行右侧显示域名（太长时中间截断），没填显示“未设置”。
    private var baseURLDisplay: String {
        if let host = URL(string: profile.normalizedBaseURL)?.host {
            return host
        }
        return profile.baseURL.isEmpty ? "未设置" : profile.baseURL
    }

    /// 一行：左边是项，右边是当前值；能点的行带 >，点整行都进。
    @ViewBuilder
    private func channelRow(
        label: String,
        value: String,
        valueColor: Color = .secondary,
        action: (() -> Void)? = nil
    ) -> some View {
        let content = HStack {
            Text(label)
                .font(.body)
            Spacer()
            Text(value)
                .font(.body)
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .truncationMode(.middle)
            if action != nil {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
        if let action {
            Button(action: action) { content }
                .buttonStyle(.plain)
        } else {
            content
        }
    }

    /// 测试连接：用已保存的 Key 读模型列表，不消耗 token。
    private var testRow: some View {
        Button {
            Task { await profile.testConnection() }
        } label: {
            HStack {
                Text("测试连接")
                    .font(.body)
                    .foregroundStyle(.blue)
                Spacer()
                if profile.testState == .testing {
                    ProgressView()
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(profile.testState == .testing)
    }

    @ViewBuilder
    private var testResultView: some View {
        switch profile.testState {
        case .idle:
            EmptyView()
        case .testing:
            Text("正在连接…")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .ok:
            Text("连通了 ✓")
                .font(.caption)
                .foregroundStyle(.green)
        case .failed(let reason):
            Text(reason)
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    // MARK: - 三个编辑器：地址 / Key / 模型

    /// 地址编辑器：只填根地址，不用填完整接口；结尾的 /v1 自动去掉。
    private var baseURLEditor: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                TextField("https://api.example.com", text: $baseURLDraft)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
                Text("只填根地址，不用填完整接口；结尾的 /v1 会自动去掉，没写协议默认补 https。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding()
            .navigationTitle("Base URL")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { showBaseURLEditor = false }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") {
                        profile.baseURL = baseURLDraft
                        showBaseURLEditor = false
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium])
    }

    /// Key 编辑器：Dsh-go 的做法——留空就是保留原来的 Key，
    /// 填了新的点保存才换；清除是把 Keychain 里的删掉。
    private var keyEditor: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                SecureField("粘贴 API Key", text: $keyInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
                Text(profile.hasAPIKey
                     ? "已有 Key，留空点保存就是保留原来的；填了新的才会换掉。"
                     : "Key 只存进手机钥匙串，界面上不会显示出来。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if profile.hasAPIKey {
                    Button("清除 Key", role: .destructive) {
                        profile.deleteAPIKey()
                        keyInput = ""
                        showKeyEditor = false
                    }
                }
                Spacer()
            }
            .padding()
            .navigationTitle("API Key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { showKeyEditor = false }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") {
                        if !keyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            profile.saveAPIKey(keyInput)
                        }
                        keyInput = ""
                        showKeyEditor = false
                    }
                    .fontWeight(.semibold)
                    .disabled(keyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !profile.hasAPIKey)
                }
            }
        }
        .presentationDetents([.medium])
    }

    /// 模型编辑器：上面手动填模型 ID，下面点“获取模型”
    /// 从服务方读列表、点一个就用它（Dsh-go 的获取模型）；
    /// 服务方不列模型时，手动填就行。
    private var modelEditor: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    TextField("手动填模型 ID", text: $modelDraft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)
                    Button("保存") {
                        profile.modelName = modelDraft
                        showModelEditor = false
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(modelDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Button {
                    Task { await loadModels() }
                } label: {
                    HStack {
                        Text("获取模型")
                        Spacer()
                        if modelsLoading { ProgressView() }
                    }
                }
                .buttonStyle(.bordered)
                .disabled(modelsLoading)
                Text("从服务方读模型列表，不消耗 token；点一个就用它。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let modelsError {
                    Text(modelsError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                if !availableModels.isEmpty {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(availableModels, id: \.self) { id in
                                Button {
                                    profile.modelName = id
                                    showModelEditor = false
                                } label: {
                                    HStack {
                                        Text(id)
                                            .font(.body)
                                            .foregroundStyle(.primary)
                                        Spacer()
                                        if id == profile.modelName {
                                            Image(systemName: "checkmark")
                                                .foregroundStyle(.blue)
                                        }
                                    }
                                    .padding(.vertical, 10)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                if id != availableModels.last {
                                    Divider()
                                }
                            }
                        }
                    }
                }
                Spacer()
            }
            .padding()
            .navigationTitle("模型")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { showModelEditor = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// 读模型列表：成功就列出来点着选；空列表或失败都写明原因，
    /// 不假装读到了。
    private func loadModels() async {
        modelsLoading = true
        modelsError = nil
        let (ids, error) = await profile.fetchModelIDs()
        modelsLoading = false
        if let error {
            modelsError = error
            availableModels = []
        } else {
            availableModels = ids
            if ids.isEmpty {
                modelsError = "读到了，但这个服务没有列出模型，手动填模型 ID 吧。"
            }
        }
    }
}
