import SwiftUI

struct AppShell: View {
    @State private var selection: RootTab = .chat
    @State private var collapsed = false
    @State private var conversations: [ConversationPreview] = [.sample]
    @State private var chatSeed = UUID()

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                switch selection {
                case .chat:
                    ChatView(onNewChat: createNewChat, onNavigationCollapse: { collapsed = true })
                        .id(chatSeed)
                case .conversations:
                    ConversationListView(previews: conversations) { preview in
                        selection = .chat
                        collapsed = true
                        chatSeed = preview.id
                    }
                case .mood:
                    MoodView()
                case .me:
                    MeView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            CompactGlassNavigation(selection: $selection, collapsed: $collapsed)
                .padding(.leading, 14)
                .padding(.bottom, 8)
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    private func createNewChat() {
        let preview = ConversationPreview(name: "新对话", lastMessage: "发送第一条消息后自动命名")
        conversations.insert(preview, at: 0)
        chatSeed = preview.id
    }
}

enum RootTab: CaseIterable, Hashable {
    case chat, conversations, mood, me
    var title: String { switch self { case .chat: "聊天"; case .conversations: "会话"; case .mood: "心情"; case .me: "我的" } }
    var icon: String { switch self { case .chat: "message.fill"; case .conversations: "bubble.left.and.bubble.right.fill"; case .mood: "sparkles"; case .me: "person.crop.circle.fill" } }
}

struct CompactGlassNavigation: View {
    @Binding var selection: RootTab
    @Binding var collapsed: Bool

    var body: some View {
        HStack(spacing: 4) {
            ForEach(collapsed ? [selection] : RootTab.allCases, id: \.self) { tab in
                Button {
                    if collapsed && tab == selection {
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) { collapsed = false }
                    } else {
                        selection = tab
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) { collapsed = true }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab.icon)
                            .frame(width: 24, height: 24)
                        if !collapsed { Text(tab.title).font(.caption.weight(.semibold)) }
                    }
                    .foregroundStyle(selection == tab ? Color.accentColor : Color.secondary)
                    .padding(.horizontal, collapsed ? 10 : 9)
                    .frame(height: 48)
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .glassCapsuleFill()
    }
}

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
            .navigationTitle("会话")
            .safeAreaPadding(.bottom, 70)
        }
    }
}

struct MoodView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView("心情", systemImage: "sparkles", description: Text("暂时保留的位置"))
                .navigationTitle("心情")
                .safeAreaPadding(.bottom, 70)
        }
    }
}

struct MeView: View {
    @Environment(AgentProfile.self) private var profile
    @Environment(ToolsStore.self) private var toolsStore
    @State private var showProfile = false
    @State private var showTools = false
    @State private var showMemorySoul = false
    @State private var showModel = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    Button { showProfile = true } label: {
                        VStack(spacing: 10) {
                            profileAvatar(size: 88)
                            Text(profile.displayName).font(.title2.bold()).foregroundStyle(.primary)
                            Text("Agent · \(agentNumber)").font(.subheadline).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 22)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22))
                    }.buttonStyle(.plain)

                    menuCard(title: "插件", subtitle: "MCP · Skills · 工具", icon: "puzzlepiece.extension.fill") { showTools = true }
                    menuCard(title: "记忆核 · Soul", subtitle: "记忆与人格设定", icon: "brain.head.profile") { showMemorySoul = true }
                    menuCard(title: "模型", subtitle: profile.modelName.isEmpty ? "尚未配置" : profile.modelName, icon: "cpu") { showModel = true }
                }.padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 90)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("我的")
        }
        .sheet(isPresented: $showProfile) { ProfileView().environment(toolsStore) }
        .sheet(isPresented: $showTools) { ToolPickerSheet().environment(toolsStore) }
        .sheet(isPresented: $showMemorySoul) { ProfileView().environment(toolsStore) }
        .sheet(isPresented: $showModel) { ProfileView().environment(toolsStore) }
    }

    private var agentNumber: String { String(abs(profile.displayName.hashValue) % 9_000_000 + 1_000_000) }
    @ViewBuilder private func profileAvatar(size: CGFloat) -> some View {
        if let url = profile.avatarURL { LocalImage(url: url, pixelWidth: nil, pixelHeight: nil, fixedSize: CGSize(width: size, height: size)).clipShape(Circle()) }
        else { Image(systemName: "sparkles").font(.system(size: 32, weight: .semibold)).foregroundStyle(.white).frame(width: size, height: size).background(Color.accentColor, in: Circle()) }
    }
    private func menuCard(title: String, subtitle: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.title3).foregroundStyle(.tint).frame(width: 34)
                VStack(alignment: .leading, spacing: 3) { Text(title).font(.headline).foregroundStyle(.primary); Text(subtitle).font(.subheadline).foregroundStyle(.secondary) }
                Spacer(); Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }.padding(16).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
        }.buttonStyle(.plain)
    }
}
