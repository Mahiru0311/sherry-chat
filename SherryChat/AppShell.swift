import SwiftUI

@MainActor @Observable
final class ConversationStore {
    var previews: [ConversationPreview]
    var activeID: UUID

    init() {
        let loaded = Self.load()
        previews = loaded.isEmpty ? [.sample] : loaded
        activeID = previews.first?.id ?? ConversationPreview.sample.id
    }

    @discardableResult
    func newDraft() -> UUID {
        if let draft = previews.first(where: { $0.isDraft }) { activeID = draft.id; return draft.id }
        let draft = ConversationPreview(name: "新对话", lastMessage: "发送消息后自动命名", isDraft: true)
        previews.insert(draft, at: 0); activeID = draft.id; save(); return draft.id
    }

    func select(_ preview: ConversationPreview) { activeID = preview.id }

    /// 首句即时命名，前 3 条用户消息持续优化；后续可无缝替换成 JSON Schema 模型标题。
    func absorbUserMessage(_ text: String, for id: UUID) {
        guard let index = previews.firstIndex(where: { $0.id == id }) else { return }
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        previews[index].isDraft = false
        if previews[index].turnSeeds.count < 3 { previews[index].turnSeeds.append(clean) }
        previews[index].lastMessage = clean
        previews[index].date = .now
        previews[index].name = title(from: previews[index].turnSeeds)
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
    @State private var selection: RootTab = .chat
    @State private var store = ConversationStore()

    var body: some View {
        TabView(selection: $selection) {
            Tab("聊天", systemImage: "message.fill", value: .chat) {
                ChatView(onNewChat: { store.newDraft() }, onUserSent: { store.absorbUserMessage($0, for: store.activeID) }).id(store.activeID)
            }
            Tab("会话", systemImage: "bubble.left.and.bubble.right.fill", value: .conversations) {
                ConversationListView(previews: store.previews, onSelect: { store.select($0); selection = .chat }, onDelete: store.delete)
            }
            Tab("动态", systemImage: "sparkles", value: .mood) { ActivityFeedView() }
            Tab("我的", systemImage: "person.crop.circle.fill", value: .me) { MeView() }
        }
        .tint(.accentColor)
        .modifier(NativeTabMinimizeModifier())
    }
}

private struct NativeTabMinimizeModifier: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View { if #available(iOS 26.0, *) { content.tabBarMinimizeBehavior(.onScrollDown) } else { content } }
}

enum RootTab: Hashable { case chat, conversations, mood, me }

struct ConversationPreview: Identifiable, Hashable, Codable {
    let id: UUID; var name: String; var lastMessage: String; var date: Date; var isDraft: Bool; var turnSeeds: [String]
    init(id: UUID = UUID(), name: String, lastMessage: String = "开始一段新的对话", date: Date = .now, isDraft: Bool = false, turnSeeds: [String] = []) { self.id=id; self.name=name; self.lastMessage=lastMessage; self.date=date; self.isDraft=isDraft; self.turnSeeds=turnSeeds }
    static let sample = ConversationPreview(name: "Sherry")
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
