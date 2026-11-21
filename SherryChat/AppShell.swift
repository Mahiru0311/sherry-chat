import PhotosUI
import SwiftUI

@MainActor @Observable
final class ConversationStore {
    var previews: [ConversationPreview] = [.sample]
    var activeID = ConversationPreview.sample.id

    func newDraft() -> UUID {
        if let draft = previews.first(where: { $0.isDraft }) { activeID = draft.id; return draft.id }
        let draft = ConversationPreview(name: "新对话", lastMessage: "发送消息后自动命名", isDraft: true)
        previews.insert(draft, at: 0); activeID = draft.id; return draft.id
    }

    /// 参考 DeepChat：首句先给即时标题，前几轮结束后再生成更准确标题。
    func absorbUserMessage(_ text: String, for id: UUID) {
        guard let index = previews.firstIndex(where: { $0.id == id }) else { return }
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        previews[index].isDraft = false
        previews[index].turnSeeds.append(clean)
        previews[index].lastMessage = clean
        previews[index].date = .now
        previews[index].name = title(from: previews[index].turnSeeds)
    }

    private func title(from turns: [String]) -> String {
        let words = turns.prefix(3).joined(separator: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(words.prefix(24))
    }
}

struct AppShell: View {
    @State private var selection: RootTab = .chat
    @State private var store = ConversationStore()
    var body: some View {
        TabView(selection: $selection) {
            Tab("聊天", systemImage: "message.fill", value: .chat) {
                ChatView(onNewChat: { store.newDraft() }, onUserSent: { store.absorbUserMessage($0, for: store.activeID) }).id(store.activeID)
            }
            Tab("会话", systemImage: "bubble.left.and.bubble.right.fill", value: .conversations) {
                ConversationListView(previews: store.previews) { preview in store.activeID = preview.id; selection = .chat }
            }
            Tab("心情", systemImage: "sparkles", value: .mood) { MoodView() }
            Tab("我的", systemImage: "person.crop.circle.fill", value: .me) { MeView() }
        }
        .tint(.accentColor)
        .modifier(NativeTabMinimizeModifier())
    }
}

private struct NativeTabMinimizeModifier: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 26.0, *) { content.tabBarMinimizeBehavior(.onScrollDown) } else { content }
    }
}

enum RootTab: Hashable { case chat, conversations, mood, me }

struct ConversationPreview: Identifiable, Hashable {
    let id: UUID; var name: String; var lastMessage: String; var date: Date; var isDraft: Bool; var turnSeeds: [String]
    init(id: UUID = UUID(), name: String, lastMessage: String = "开始一段新的对话", date: Date = .now, isDraft: Bool = false, turnSeeds: [String] = []) {
        self.id = id; self.name = name; self.lastMessage = lastMessage; self.date = date; self.isDraft = isDraft; self.turnSeeds = turnSeeds
    }
    static let sample = ConversationPreview(name: "Sherry")
}

struct ConversationListView: View {
    let previews: [ConversationPreview]; let onSelect: (ConversationPreview) -> Void
    var body: some View {
        NavigationStack {
            List(previews.filter { !$0.isDraft }) { preview in
                Button { onSelect(preview) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "sparkles").foregroundStyle(.white).frame(width: 48, height: 48).background(Color.accentColor, in: Circle())
                        VStack(alignment: .leading, spacing: 4) { Text(preview.name).font(.headline).foregroundStyle(.primary); Text(preview.lastMessage).font(.subheadline).foregroundStyle(.secondary).lineLimit(1) }
                        Spacer(); Text(preview.date, style: .time).font(.caption).foregroundStyle(.tertiary)
                    }.padding(.vertical, 5)
                }.buttonStyle(.plain)
            }.toolbar { ToolbarItem(placement: .principal) { EmptyView() } }
        }
    }
}

struct MoodView: View { var body: some View { NavigationStack { ContentUnavailableView("心情", systemImage: "sparkles", description: Text("暂时保留的位置")) } } }

enum MeRoute: Hashable, Identifiable { case profile, plugins, memory, soul, model; var id: Self { self } }

struct MeView: View {
    @Environment(AgentProfile.self) private var profile
    @Environment(ToolsStore.self) private var toolsStore
    @State private var route: MeRoute?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    Button { route = .profile } label: {
                        VStack(spacing: 8) { AgentAvatar(size: 96); Text(profile.displayName).font(.title2.bold()).foregroundStyle(.primary); Text("Agent · \(agentNumber)").font(.subheadline).foregroundStyle(.secondary) }
                            .frame(maxWidth: .infinity).padding(.vertical, 16).background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
                    }.buttonStyle(.plain)
                    menuCard("插件", icon: "puzzlepiece.extension.fill") { route = .plugins }
                    menuCard("记忆", icon: "brain.head.profile") { route = .memory }
                    menuCard("人格", icon: "heart.text.square.fill") { route = .soul }
                    menuCard("模型", icon: "cpu") { route = .model }
                }.padding(.horizontal, 16).padding(.top, 0).padding(.bottom, 18)
            }.background(Color(.systemGroupedBackground)).toolbar { ToolbarItem(placement: .principal) { EmptyView() } }
                .navigationDestination(item: $route) { route in
                    switch route { case .profile: AgentProfileDetailsView(); case .plugins: PluginsPage().environment(toolsStore); case .memory: MemoryPage(); case .soul: SoulPage(); case .model: ModelPage() }
                }
        }
    }
    private var agentNumber: String { String(abs(profile.displayName.hashValue) % 9_000_000 + 1_000_000) }
    private func menuCard(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { HStack(spacing: 14) { Image(systemName: icon).font(.title3).foregroundStyle(.tint).frame(width: 34); Text(title).font(.headline).foregroundStyle(.primary); Spacer(); Image(systemName: "chevron.right").foregroundStyle(.tertiary) }.padding(16).background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16)) }.buttonStyle(.plain)
    }
}

struct AgentAvatar: View {
    @Environment(AgentProfile.self) private var profile; let size: CGFloat
    var body: some View { Group { if let url = profile.avatarURL { LocalImage(url: url, pixelWidth: nil, pixelHeight: nil, fixedSize: CGSize(width: size, height: size)).clipShape(Circle()) } else { Image(systemName: "sparkles").font(.system(size: size * 0.38, weight: .semibold)).foregroundStyle(.white).frame(width: size, height: size).background(Color.accentColor, in: Circle()) } } }
}

struct AgentProfileDetailsView: View {
    @Environment(AgentProfile.self) private var profile
    @State private var name = ""; @State private var region = "冰岛"; @State private var item: PhotosPickerItem?
    var body: some View {
        List { Section {
            PhotosPicker(selection: $item, matching: .images) { HStack { Text("头像"); Spacer(); AgentAvatar(size: 46) } }
            NavigationLink { NameEditor(value: name) { profile.setDisplayName($0) } } label: { row("名字", profile.displayName) }
            NavigationLink { TextField("地区", text: $region).padding() } label: { row("地区", region) }
            row("Agent 号", String(abs(profile.displayName.hashValue) % 9_000_000 + 1_000_000))
        } }.navigationTitle("个人资料").navigationBarTitleDisplayMode(.inline).onAppear { name = profile.displayName }
            .onChange(of: item) { _, value in Task { if let data = try? await value?.loadTransferable(type: Data.self) { let url = FileManager.default.temporaryDirectory.appendingPathComponent("agent-avatar.jpg"); try? data.write(to: url); _ = profile.setAvatar(from: url) } } }
    }
    private func row(_ title: String, _ value: String) -> some View { HStack { Text(title); Spacer(); Text(value).foregroundStyle(.secondary) } }
}

struct NameEditor: View { @Environment(\.dismiss) private var dismiss; @State var value: String; let save: (String)->Void; var body: some View { Form { TextField("名字", text:$value) }.navigationTitle("名字").toolbar { Button("保存") { save(value); dismiss() } } } }

struct PluginsPage: View {
    @Environment(ToolsStore.self) private var store
    var body: some View { List { Section("Skills") { ForEach(store.tools.filter{$0.source == .skill}) { tool in Toggle(tool.name, isOn: binding(tool.id)) } }; Section("MCP") { ForEach(store.tools.filter{$0.source == .mcp}) { tool in Toggle(tool.name, isOn: binding(tool.id)) } } }.navigationTitle("插件").navigationBarTitleDisplayMode(.inline) }
    private func binding(_ id:String)->Binding<Bool>{ Binding(get:{store.tools.first(where:{$0.id==id})?.isEnabled ?? false},set:{_ in store.toggle(id)}) }
}

struct MemoryPage: View {
    @Environment(AgentProfile.self) private var profile; @State private var text=""
    var body: some View { List { Section("Agent 对你的了解") { ForEach(profile.memories) { Text($0.text) }.onDelete { profile.memories.remove(atOffsets:$0) } }; Section("添加记忆") { TextField("例如：我喜欢清亮的界面", text:$text); Button("保存") { let v=text.trimmingCharacters(in:.whitespacesAndNewlines); if !v.isEmpty { profile.memories.append(MemoryNote(text:v)); text="" } } } }.navigationTitle("记忆").navigationBarTitleDisplayMode(.inline) }
}

struct SoulPage: View {
    @Environment(AgentProfile.self) private var profile
    @State private var draft = ""
    var body: some View {
        Form {
            Section("当前人格") {
                TextEditor(text: $draft).frame(minHeight: 220)
                Button("保存人格") { profile.soul = draft }
            }
            if let proposal = profile.soulDraft {
                Section("Agent 提议") {
                    Text(proposal)
                    HStack {
                        Button("采用") { profile.approveSoulDraft(); draft = profile.soul }
                        Spacer()
                        Button("忽略", role: .destructive) { profile.rejectSoulDraft() }
                    }
                }
            }
            Section {
                Button("将当前编辑存为待审草稿") { profile.proposeSoulDraft(draft) }
            } footer: {
                Text("Agent 的人格变化先进入草稿，经你确认后才生效；进行中的对话保持原有人格。")
            }
        }
        .navigationTitle("人格")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { draft = profile.soul }
    }
}

struct ModelPage: View {
    @Environment(AgentProfile.self) private var profile; @State private var base=""; @State private var model=""
    var body: some View { Form { Section("连接") { TextField("API 地址",text:$base).textInputAutocapitalization(.never); TextField("模型 ID",text:$model).textInputAutocapitalization(.never); Button("保存") { profile.baseURL=base; profile.modelName=model } } }.navigationTitle("模型").navigationBarTitleDisplayMode(.inline).onAppear { base=profile.baseURL; model=profile.modelName } }
}
