import PhotosUI
import SwiftUI

enum MeRoute: Hashable, Identifiable { case profile, plugins, memory, soul, model; var id: Self { self } }

struct MeView: View {
    @Environment(AgentProfile.self) private var profile
    @Environment(ToolsStore.self) private var tools
    @State private var route: MeRoute?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    Button { route = .profile } label: {
                        VStack(spacing: 8) {
                            AgentAvatar(size: 96)
                            Text(profile.displayName).font(.title2.bold()).foregroundStyle(.primary)
                            Text("Agent · \(profile.agentID)").font(.subheadline).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 16)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
                    }.buttonStyle(.plain)
                    menu("插件", "puzzlepiece.extension.fill", badge: nil) { route = .plugins }
                    menu("记忆", "brain.head.profile", badge: nil) { route = .memory }
                    menu("人格", "heart.text.square.fill", badge: profile.soulDraft == nil ? nil : "待确认") { route = .soul }
                    menu("模型", "cpu", badge: profile.modelName.isEmpty ? "未配置" : profile.modelName) { route = .model }
                }.padding(.horizontal, 16).padding(.top, 2).padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .toolbar { ToolbarItem(placement: .principal) { EmptyView() } }
            .navigationDestination(item: $route) { value in
                switch value {
                case .profile: AgentProfileDetailsView()
                case .plugins: PluginsPage().environment(tools)
                case .memory: MemoryPage()
                case .soul: SoulPage()
                case .model: ModelSettingsPage()
                }
            }
        }
    }

    private func menu(_ title: String, _ icon: String, badge: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.title3).foregroundStyle(.tint).frame(width: 34)
                Text(title).font(.headline).foregroundStyle(.primary)
                Spacer()
                if let badge { Text(badge).font(.subheadline).foregroundStyle(.secondary).lineLimit(1) }
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }.padding(16).background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        }.buttonStyle(.plain)
    }
}

struct AgentAvatar: View {
    @Environment(AgentProfile.self) private var profile
    let size: CGFloat
    var body: some View {
        Group {
            if let url = profile.avatarURL { LocalImage(url: url, pixelWidth: nil, pixelHeight: nil, fixedSize: CGSize(width: size, height: size)).clipShape(Circle()) }
            else { Image(systemName: "sparkles").font(.system(size: size * 0.38, weight: .semibold)).foregroundStyle(.white).frame(width: size, height: size).background(Color.accentColor.gradient, in: Circle()) }
        }
    }
}

struct AgentProfileDetailsView: View {
    @Environment(AgentProfile.self) private var profile
    @State private var photo: PhotosPickerItem?
    var body: some View {
        List { Section {
            PhotosPicker(selection: $photo, matching: .images) { HStack { Text("头像"); Spacer(); AgentAvatar(size: 48) } }
            NavigationLink { TextValueEditor(title: "名字", initial: profile.displayName) { profile.setDisplayName($0) } } label: { row("名字", profile.displayName) }
            NavigationLink { TextValueEditor(title: "地区", initial: profile.region) { profile.region = $0 } } label: { row("地区", profile.region) }
            row("Agent 号", profile.agentID)
        } }
        .navigationTitle("个人资料").navigationBarTitleDisplayMode(.inline)
        .onChange(of: photo) { _, item in Task { if let data = try? await item?.loadTransferable(type: Data.self) { let url = FileManager.default.temporaryDirectory.appendingPathComponent("agent-avatar.jpg"); try? data.write(to: url); _ = profile.setAvatar(from: url) } } }
    }
    private func row(_ title: String, _ value: String) -> some View { HStack { Text(title); Spacer(); Text(value).foregroundStyle(.secondary) } }
}

struct TextValueEditor: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    @State var value: String
    let save: (String) -> Void
    init(title: String, initial: String, save: @escaping (String) -> Void) { self.title = title; _value = State(initialValue: initial); self.save = save }
    var body: some View { Form { TextField(title, text: $value) }.navigationTitle(title).navigationBarTitleDisplayMode(.inline).toolbar { Button("保存") { let clean = value.trimmingCharacters(in: .whitespacesAndNewlines); if !clean.isEmpty { save(clean) }; dismiss() }.fontWeight(.semibold) } }
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

struct MemoryPage: View {
    @Environment(AgentProfile.self) private var profile
    @State private var text = ""
    var body: some View {
        List {
            Section("Agent 对你的了解") { ForEach(profile.memories) { note in NavigationLink { MemoryEditor(note: note) } label: { Text(note.text) } }.onDelete(perform: profile.removeMemories) }
            Section("添加") { TextField("一条稳定的事实或偏好", text: $text, axis: .vertical); Button("保存记忆") { profile.addMemory(text); text = "" } }
        }.navigationTitle("记忆").navigationBarTitleDisplayMode(.inline)
    }
}

struct MemoryEditor: View {
    @Environment(AgentProfile.self) private var profile
    @Environment(\.dismiss) private var dismiss
    let note: MemoryNote
    @State private var text: String
    init(note: MemoryNote) { self.note = note; _text = State(initialValue: note.text) }
    var body: some View { Form { TextEditor(text: $text).frame(minHeight: 180) }.navigationTitle("编辑记忆").toolbar { Button("保存") { profile.updateMemory(id: note.id, text: text); dismiss() } } }
}

struct SoulPage: View {
    @Environment(AgentProfile.self) private var profile
    @State private var draft = ""
    var body: some View {
        Form {
            Section("当前人格") { TextEditor(text: $draft).frame(minHeight: 220); Button("保存人格") { profile.soul = draft } }
            if let proposal = profile.soulDraft { Section("Agent 提议") { Text(proposal); Button("采用") { profile.approveSoulDraft(); draft = profile.soul }; Button("忽略", role: .destructive) { profile.rejectSoulDraft() } } }
            Section { Button("保存为待审草稿") { profile.proposeSoulDraft(draft) } } footer: { Text("Agent 的自我变化先进入草稿，只有你确认后才会成为新人格。") }
        }.navigationTitle("人格").navigationBarTitleDisplayMode(.inline).onAppear { draft = profile.soul }
    }
}
