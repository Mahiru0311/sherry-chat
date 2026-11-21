import SwiftUI

struct AppShell: View {
    @State private var selection: RootTab = .chat
    @State private var conversations: [ConversationPreview] = [.sample]
    @State private var chatSeed = UUID()

    @ViewBuilder
    var body: some View {
        if #available(iOS 26.0, *) {
            nativeTabs.tabBarMinimizeBehavior(.onScrollDown)
        } else {
            nativeTabs
        }
    }

    private var nativeTabs: some View {
        TabView(selection: $selection) {
            Tab("聊天", systemImage: "message.fill", value: .chat) {
                ChatView(onNewChat: createNewChat).id(chatSeed)
            }
            Tab("会话", systemImage: "bubble.left.and.bubble.right.fill", value: .conversations) {
                ConversationListView(previews: conversations) { preview in
                    chatSeed = preview.id
                    selection = .chat
                }
            }
            Tab("心情", systemImage: "sparkles", value: .mood) { MoodView() }
            Tab("我的", systemImage: "person.crop.circle.fill", value: .me) { MeView() }
        }
        .tint(.accentColor)
    }

    private func createNewChat() {
        let preview = ConversationPreview(name: "新对话", lastMessage: "发送第一条消息后自动命名")
        conversations.insert(preview, at: 0)
        chatSeed = preview.id
    }
}

enum RootTab: Hashable { case chat, conversations, mood, me }

struct ConversationPreview: Identifiable, Hashable {
    let id: UUID
    var name: String
    var lastMessage: String
    var date: Date
    init(id: UUID = UUID(), name: String, lastMessage: String = "开始一段新的对话", date: Date = .now) {
        self.id = id; self.name = name; self.lastMessage = lastMessage; self.date = date
    }
    static let sample = ConversationPreview(name: "Sherry")
}

struct ConversationListView: View {
    let previews: [ConversationPreview]
    let onSelect: (ConversationPreview) -> Void
    var body: some View {
        NavigationStack {
            List(previews) { preview in
                Button { onSelect(preview) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "sparkles").foregroundStyle(.white).frame(width: 48, height: 48).background(Color.accentColor, in: Circle())
                        VStack(alignment: .leading, spacing: 4) {
                            Text(preview.name).font(.headline).foregroundStyle(.primary)
                            Text(preview.lastMessage).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Text(preview.date, style: .time).font(.caption).foregroundStyle(.tertiary)
                    }.padding(.vertical, 5)
                }.buttonStyle(.plain)
            }
            .toolbar { ToolbarItem(placement: .principal) { EmptyView() } }
        }
    }
}

struct MoodView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView("心情", systemImage: "sparkles", description: Text("暂时保留的位置"))
                .toolbar { ToolbarItem(placement: .principal) { EmptyView() } }
        }
    }
}

struct MeView: View {
    @Environment(AgentProfile.self) private var profile
    @Environment(ToolsStore.self) private var toolsStore
    @State private var route: MeRoute?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    Button { route = .profile } label: {
                        VStack(spacing: 8) {
                            profileAvatar(size: 92)
                            Text(profile.displayName).font(.title2.bold()).foregroundStyle(.primary)
                            Text("Agent · \(agentNumber)").font(.subheadline).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 18)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
                    }.buttonStyle(.plain)

                    menuCard(title: "插件", subtitle: "MCP · Skills", icon: "puzzlepiece.extension.fill") { route = .plugins }
                    menuCard(title: "记忆核 · Soul", subtitle: "记忆与人格", icon: "brain.head.profile") { route = .memory }
                    menuCard(title: "模型", subtitle: profile.modelName.isEmpty ? "尚未配置" : profile.modelName, icon: "cpu") { route = .model }
                }.padding(.horizontal, 16).padding(.top, 2).padding(.bottom, 18)
            }
            .background(Color(.systemGroupedBackground))
            .toolbar { ToolbarItem(placement: .principal) { EmptyView() } }
            .navigationDestination(item: $route) { route in
                switch route {
                case .profile: AgentProfileDetailsView()
                case .plugins: PluginsPage().environment(toolsStore)
                case .memory: MemorySoulPage()
                case .model: ModelPage()
                }
            }
        }
    }

    private var agentNumber: String { String(abs(profile.displayName.hashValue) % 9_000_000 + 1_000_000) }
    @ViewBuilder private func profileAvatar(size: CGFloat) -> some View {
        if let url = profile.avatarURL { LocalImage(url: url, pixelWidth: nil, pixelHeight: nil, fixedSize: CGSize(width: size, height: size)).clipShape(Circle()) }
        else { Image(systemName: "sparkles").font(.system(size: 34, weight: .semibold)).foregroundStyle(.white).frame(width: size, height: size).background(Color.accentColor, in: Circle()) }
    }
    private func menuCard(title: String, subtitle: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.title3).foregroundStyle(.tint).frame(width: 34)
                VStack(alignment: .leading, spacing: 3) { Text(title).font(.headline).foregroundStyle(.primary); Text(subtitle).font(.subheadline).foregroundStyle(.secondary) }
                Spacer(); Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }.padding(16).background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        }.buttonStyle(.plain)
    }
}

enum MeRoute: Hashable, Identifiable { case profile, plugins, memory, model; var id: Self { self } }

struct AgentProfileDetailsView: View {
    @Environment(AgentProfile.self) private var profile
    @State private var name = ""
    @State private var region = "冰岛"
    var body: some View {
        List {
            Section {
                NavigationLink { Text("头像通过聊天发送图片更换").foregroundStyle(.secondary) } label: { detailRow("头像", value: "", avatar: true) }
                NavigationLink { TextField("名字", text: $name).padding().onSubmit { profile.setDisplayName(name) } } label: { detailRow("名字", value: profile.displayName) }
                NavigationLink { TextField("地区", text: $region).padding() } label: { detailRow("地区", value: region) }
                detailRow("Agent 号", value: String(abs(profile.displayName.hashValue) % 9_000_000 + 1_000_000))
            }
        }
        .navigationTitle("个人资料").navigationBarTitleDisplayMode(.inline)
        .onAppear { name = profile.displayName }
    }
    @ViewBuilder private func detailRow(_ title: String, value: String, avatar: Bool = false) -> some View {
        HStack { Text(title); Spacer(); if avatar { Image(systemName: "sparkles").foregroundStyle(.white).frame(width: 42, height: 42).background(Color.accentColor, in: Circle()) } else { Text(value).foregroundStyle(.secondary) } }
    }
}

struct PluginsPage: View {
    @Environment(ToolsStore.self) private var store
    var body: some View {
        List {
            Section("Skills") { ForEach(store.tools.filter { $0.source == .skill }) { tool in Toggle(isOn: binding(tool.id)) { Label(tool.name, systemImage: tool.icon) } } }
            Section("MCP") { ForEach(store.tools.filter { $0.source == .mcp }) { tool in Toggle(isOn: binding(tool.id)) { Label(tool.name, systemImage: tool.icon) } } }
        }.navigationTitle("插件").navigationBarTitleDisplayMode(.inline)
    }
    private func binding(_ id: String) -> Binding<Bool> { Binding(get: { store.tools.first(where: { $0.id == id })?.isEnabled ?? false }, set: { _ in store.toggle(id) }) }
}

struct MemorySoulPage: View {
    @Environment(AgentProfile.self) private var profile
    var body: some View { List { Section("Soul") { Text(profile.soul).foregroundStyle(.secondary) }; Section("记忆核") { ForEach(profile.memories) { Text($0.text) } } }.navigationTitle("记忆核 · Soul").navigationBarTitleDisplayMode(.inline) }
}

struct ModelPage: View {
    @Environment(AgentProfile.self) private var profile
    var body: some View { List { Section("当前模型") { LabeledContent("模型", value: profile.modelName.isEmpty ? "尚未配置" : profile.modelName); LabeledContent("连接", value: profile.isConfigured ? "已连接" : "未连接") } }.navigationTitle("模型").navigationBarTitleDisplayMode(.inline) }
}
