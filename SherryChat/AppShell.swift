import SwiftUI

/// App 的四个一级页面：聊天、会话、心情、我的。
/// 聊天页本身保持纯聊天，个人资料和工具只从“我的”进入。
struct AppShell: View {
    @Environment(AgentProfile.self) private var profile
    @Environment(ToolsStore.self) private var toolsStore
    @State private var selection: RootTab = .chat
    @State private var conversations: [ConversationPreview] = [.sample]
    @State private var showNewChat = false

    var body: some View {
        TabView(selection: $selection) {
            ChatView()
                .tabItem { Label("聊天", systemImage: "message.fill") }
                .tag(RootTab.chat)

            ConversationListView(previews: conversations, onNew: { showNewChat = true })
                .tabItem { Label("会话", systemImage: "bubble.left.and.bubble.right.fill") }
                .tag(RootTab.conversations)

            MoodView()
                .tabItem { Label("心情", systemImage: "sparkles") }
                .tag(RootTab.mood)

            MeView()
                .tabItem { Label("我的", systemImage: "person.crop.circle.fill") }
                .tag(RootTab.me)
        }
        .tint(.accentColor)
        .sheet(isPresented: $showNewChat) {
            NewChatView { name in
                conversations.insert(ConversationPreview(name: name), at: 0)
                showNewChat = false
                selection = .chat
            }
        }
    }
}

enum RootTab: Hashable { case chat, conversations, mood, me }

struct ConversationPreview: Identifiable, Hashable {
    let id = UUID()
    var name: String
    var lastMessage: String = "开始一段新的对话"
    var date: Date = .now
    static let sample = ConversationPreview(name: "Sherry")
}

struct ConversationListView: View {
    let previews: [ConversationPreview]
    let onNew: () -> Void

    var body: some View {
        NavigationStack {
            List(previews) { preview in
                HStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(.white)
                        .frame(width: 48, height: 48)
                        .background(Color.accentColor, in: Circle())
                    VStack(alignment: .leading, spacing: 4) {
                        Text(preview.name).font(.headline)
                        Text(preview.lastMessage).font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(preview.date, style: .time).font(.caption).foregroundStyle(.tertiary)
                }
                .padding(.vertical, 5)
            }
            .navigationTitle("会话")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: onNew) { Image(systemName: "square.and.pencil") }
                }
            }
        }
    }
}

struct NewChatView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    let onCreate: (String) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("新对话") {
                    TextField("对方名称", text: $name)
                }
            }
            .navigationTitle("新增聊天")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("开始") {
                        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        onCreate(value.isEmpty ? "新的 Sherry" : value)
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

struct MoodView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView("今天的心情", systemImage: "sparkles", description: Text("这里会记录 Sherry 今天想和你分享的片段。"))
                .navigationTitle("心情")
        }
    }
}

struct MeView: View {
    @Environment(AgentProfile.self) private var profile
    @Environment(ToolsStore.self) private var toolsStore
    @State private var showProfile = false
    @State private var showTools = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button { showProfile = true } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "sparkles")
                                .foregroundStyle(.white)
                                .frame(width: 64, height: 64)
                                .background(Color.accentColor, in: Circle())
                            VStack(alignment: .leading, spacing: 4) {
                                Text(profile.displayName).font(.title3.weight(.semibold)).foregroundStyle(.primary)
                                Text("编辑头像与名字").font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
                Section("能力") {
                    Button { showTools = true } label: {
                        Label("MCP 与 Skills", systemImage: "wand.and.stars")
                    }
                }
            }
            .navigationTitle("我的")
        }
        .sheet(isPresented: $showProfile) { ProfileView().environment(toolsStore) }
        .sheet(isPresented: $showTools) { ToolPickerSheet().environment(toolsStore) }
    }
}
