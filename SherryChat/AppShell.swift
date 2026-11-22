import SwiftUI

@MainActor @Observable
final class ConversationStore {
    var previews: [ConversationPreview]
    var activeID: UUID

    init() {
        let loaded = Self.load()
        let initial = loaded.isEmpty ? [ConversationPreview.sample] : loaded
        previews = initial
        activeID = initial.first?.id ?? ConversationPreview.sample.id
    }

    @discardableResult
    func newDraft() -> UUID {
        if let draft = previews.first(where: { $0.isDraft }) { activeID = draft.id; return draft.id }
        let draft = ConversationPreview(name: "新对话", lastMessage: "发送消息后自动命名", isDraft: true)
        previews.insert(draft, at: 0); activeID = draft.id; save(); return draft.id
    }

    func select(_ preview: ConversationPreview) { activeID = preview.id }

    func titleTranscript(for id: UUID) -> [String] {
        previews.first(where: { $0.id == id })?.turnSeeds ?? []
    }

    func shouldGenerateTitle(for id: UUID) -> Bool {
        guard let item = previews.first(where: { $0.id == id }) else { return false }
        return !item.titleLocked && item.titleSource != "model" && !item.turnSeeds.isEmpty
    }

    func applyGeneratedTitle(_ title: String, to id: UUID, expectedSeeds: [String]) {
        guard !title.isEmpty,
              let index = previews.firstIndex(where: { $0.id == id }),
              previews[index].turnSeeds == expectedSeeds,
              !previews[index].titleLocked else { return }
        previews[index].name = title
        previews[index].titleSource = "model"
        save()
    }

    func messages(for id: UUID) -> [ChatMessage] {
        previews.first(where: { $0.id == id })?.messages.map(\.chatMessage) ?? []
    }

    func saveMessages(_ messages: [ChatMessage], for id: UUID) {
        guard let index = previews.firstIndex(where: { $0.id == id }) else { return }
        previews[index].messages = messages.map(StoredMessage.init)
        if let last = messages.last {
            previews[index].lastMessage = last.snippet
            previews[index].date = last.sentAt
        }
        save()
    }

    /// 首句即时命名，前 3 条用户消息持续优化；后续可无缝替换成 JSON Schema 模型标题。
    func absorbUserMessage(_ text: String, for id: UUID) {
        guard let index = previews.firstIndex(where: { $0.id == id }) else { return }
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        previews[index].isDraft = false
        if previews[index].turnSeeds.count < 3 { previews[index].turnSeeds.append(clean) }
        previews[index].lastMessage = clean
        previews[index].date = .now
        if !previews[index].titleLocked {
            previews[index].name = title(from: previews[index].turnSeeds)
            previews[index].titleSource = "local"
        }
        previews.sort { $0.date > $1.date }
        save()
    }

    func delete(at offsets: IndexSet) { previews.remove(atOffsets: offsets); save() }

    private func title(from turns: [String]) -> String {
        let source = turns.prefix(3).joined(separator: " ").replacingOccurrences(of: "\n", with: " ")
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        let stop = trimmed.firstIndex(where: { "。！？!?，,".contains($0) }) ?? trimmed.endIndex
        let phrase = String(trimmed[..<stop])
        return String((phrase.isEmpty ? trimmed : phrase).prefix(24))
    }

    private static var fileURL: URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent("conversations.json") }
    private static func load() -> [ConversationPreview] { guard let data = try? Data(contentsOf: fileURL) else { return [] }; return (try? JSONDecoder().decode([ConversationPreview].self, from: data)) ?? [] }
    private func save() { let url = Self.fileURL; try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true); if let data = try? JSONEncoder().encode(previews) { try? data.write(to: url, options: .atomic) } }
}

struct AppShell: View {
    @Environment(AgentProfile.self) private var profile
    @State private var selection: RootTab = .chat
    @State private var store = ConversationStore()
    @State private var titleTask: Task<Void, Never>?

    var body: some View {
        TabView(selection: $selection) {
            Tab("聊天", systemImage: "message.fill", value: .chat) {
                ChatView(
                    initialMessages: store.messages(for: store.activeID),
                    onMessagesChanged: { messages in
                        store.saveMessages(messages, for: store.activeID)
                        scheduleModelTitleIfNeeded(conversationID: store.activeID)
                    },
                    onNewChat: { store.newDraft() },
                    onUserSent: { store.absorbUserMessage($0, for: store.activeID) }
                )
                .id(store.activeID)
            }
            Tab("会话", systemImage: "bubble.left.and.bubble.right.fill", value: .conversations) {
                ConversationListView(previews: store.previews, onSelect: { store.select($0); selection = .chat }, onDelete: store.delete)
            }
            Tab("动态", systemImage: "sparkles", value: .mood) { MoodView() }
            Tab("我的", systemImage: "person.crop.circle.fill", value: .me) { MeView() }
        }
        .tint(.accentColor)
        .modifier(NativeTabMinimizeModifier(selection: selection))
    }

    private func scheduleModelTitleIfNeeded(conversationID: UUID) {
        guard store.shouldGenerateTitle(for: conversationID),
              profile.isConfigured,
              let key = profile.apiKey() else { return }
        let seeds = store.titleTranscript(for: conversationID)
        guard !seeds.isEmpty else { return }
        titleTask?.cancel()
        titleTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            if let title = try? await OpenAIClient().generateShortTitle(
                baseURL: profile.normalizedBaseURL,
                model: profile.modelName,
                apiKey: key,
                transcript: seeds
            ) {
                store.applyGeneratedTitle(title, to: conversationID, expectedSeeds: seeds)
            }
        }
    }
}

private struct NativeTabMinimizeModifier: ViewModifier {
    let selection: RootTab

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            // 聊天内容从底部开始，查看历史的主要手势方向与普通 List 相反。
            // Apple 对 bottom-aligned scroll view 推荐 onScrollUp。
            if selection == .chat {
                content.tabBarMinimizeBehavior(.onScrollUp)
            } else {
                content.tabBarMinimizeBehavior(.onScrollDown)
            }
        } else {
            content
        }
    }
}

enum RootTab: Hashable { case chat, conversations, mood, me }

struct StoredMessage: Codable, Hashable {
    var id: UUID
    var text: String
    var isMine: Bool
    var sentAt: Date

    init(_ message: ChatMessage) {
        id = message.id
        text = message.text
        isMine = message.sender == .me
        sentAt = message.sentAt
    }

    var chatMessage: ChatMessage {
        ChatMessage(
            id: id,
            text: text,
            sender: isMine ? .me : .sherry,
            sentAt: sentAt,
            status: isMine ? .read : nil
        )
    }
}

struct ConversationPreview: Identifiable, Hashable, Codable {
    let id: UUID
    var name: String
    var lastMessage: String
    var date: Date
    var isDraft: Bool
    var turnSeeds: [String]
    var messages: [StoredMessage]
    var titleSource: String
    var titleLocked: Bool

    init(
        id: UUID = UUID(),
        name: String,
        lastMessage: String = "开始一段新的对话",
        date: Date = .now,
        isDraft: Bool = false,
        turnSeeds: [String] = [],
        messages: [StoredMessage] = [],
        titleSource: String = "placeholder",
        titleLocked: Bool = false
    ) {
        self.id = id
        self.name = name
        self.lastMessage = lastMessage
        self.date = date
        self.isDraft = isDraft
        self.turnSeeds = turnSeeds
        self.messages = messages
        self.titleSource = titleSource
        self.titleLocked = titleLocked
    }

    static let sample = ConversationPreview(name: "Sherry", messages: Conversation.sampleMessages().map(StoredMessage.init))

    private enum CodingKeys: String, CodingKey { case id, name, lastMessage, date, isDraft, turnSeeds, messages, titleSource, titleLocked }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        lastMessage = try c.decode(String.self, forKey: .lastMessage)
        date = try c.decode(Date.self, forKey: .date)
        isDraft = try c.decode(Bool.self, forKey: .isDraft)
        turnSeeds = try c.decodeIfPresent([String].self, forKey: .turnSeeds) ?? []
        messages = try c.decodeIfPresent([StoredMessage].self, forKey: .messages) ?? []
        titleSource = try c.decodeIfPresent(String.self, forKey: .titleSource) ?? "local"
        titleLocked = try c.decodeIfPresent(Bool.self, forKey: .titleLocked) ?? false
    }
}

struct ConversationListView: View {
    let previews: [ConversationPreview]; let onSelect: (ConversationPreview) -> Void; let onDelete: (IndexSet) -> Void
    var body: some View {
        NavigationStack {
            List {
                Section("最近对话") {
                    ForEach(previews.filter { !$0.isDraft }) { preview in
                        Button { onSelect(preview) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "sparkles").foregroundStyle(.white).frame(width: 48,height:48).background(Color.accentColor.gradient,in:Circle())
                                VStack(alignment:.leading,spacing:4){Text(preview.name).font(.headline).foregroundStyle(.primary);Text(preview.lastMessage).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)}
                                Spacer();Text(preview.date,style:.time).font(.caption).foregroundStyle(.tertiary)
                            }.padding(.vertical,5)
                        }.buttonStyle(.plain)
                    }.onDelete(perform:onDelete)
                }
            }
            .toolbar { ToolbarItem(placement:.principal){EmptyView()} }
        }
    }
}

/// “心情”不是占位：根据最近记忆生成今天的关系摘要与可回看的心情卡片。
struct MoodView: View {
    @Environment(AgentProfile.self) private var profile
    @State private var note = ""
    @AppStorage("mood.today.note") private var savedNote = ""
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:16){
                    VStack(alignment:.leading,spacing:8){Text("今天").font(.largeTitle.bold());Text(Date.now,format:.dateTime.year().month().day().weekday()).foregroundStyle(.secondary);Text(savedNote.isEmpty ? dailySummary : savedNote).font(.title3).padding(.top,6)}.padding(20).frame(maxWidth:.infinity,alignment:.leading).glassPanelFill(cornerRadius:24)
                    VStack(alignment:.leading,spacing:10){Label("写下此刻",systemImage:"square.and.pencil").font(.headline);TextField("一句话记录今天",text:$note,axis:.vertical);Button("保存心情"){let v=note.trimmingCharacters(in:.whitespacesAndNewlines);if !v.isEmpty{savedNote=v;note=""}}.buttonStyle(.borderedProminent)}.padding(18).background(Color(.secondarySystemGroupedBackground),in:RoundedRectangle(cornerRadius:20))
                    if !profile.memories.isEmpty { VStack(alignment:.leading,spacing:10){Text("最近记住的你").font(.headline);ForEach(profile.memories.suffix(3)){memory in Label(memory.text,systemImage:"heart.fill").foregroundStyle(.secondary)}}.padding(18).background(Color(.secondarySystemGroupedBackground),in:RoundedRectangle(cornerRadius:20)) }
                }.padding(16).padding(.bottom,20)
            }.background(Color(.systemGroupedBackground)).toolbar{ToolbarItem(placement:.principal){EmptyView()}}
        }
    }
    private var dailySummary:String { profile.memories.last.map{"今天的 Sherry 还记得：\($0.text)"} ?? "今天也可以从一句真心话开始。" }
}
