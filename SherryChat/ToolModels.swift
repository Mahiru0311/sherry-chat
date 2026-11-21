import Foundation
import Observation
import SwiftUI

/// MCP 与本地 Skill 的统一描述。执行层先保持可替换，界面只依赖这个模型。
struct ToolDescriptor: Identifiable, Hashable, Sendable {
    enum Source: String, Hashable, Sendable { case skill = "Skill"; case mcp = "MCP" }
    let id: String
    let name: String
    let summary: String
    let icon: String
    let source: Source
    var isEnabled: Bool

    static func == (lhs: ToolDescriptor, rhs: ToolDescriptor) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

@MainActor @Observable
final class ToolsStore {
    var tools: [ToolDescriptor] = [
        ToolDescriptor(id: "skill.web-search", name: "网页搜索", summary: "查找资料并整理成对话上下文", icon: "magnifyingglass", source: .skill, isEnabled: true),
        ToolDescriptor(id: "skill.memory", name: "记忆助手", summary: "把重要内容保存到 Sherry 的长期记忆", icon: "brain.head.profile", source: .skill, isEnabled: true),
        ToolDescriptor(id: "skill.image", name: "图像理解", summary: "理解你发送的图片和截图", icon: "photo", source: .skill, isEnabled: true),
        ToolDescriptor(id: "mcp.files", name: "本地文件", summary: "通过 MCP 读取和整理已选择的文件", icon: "folder", source: .mcp, isEnabled: false),
        ToolDescriptor(id: "mcp.calendar", name: "日历", summary: "查看和安排你的日程", icon: "calendar", source: .mcp, isEnabled: false)
    ]
    var isShowingTools = false

    var enabledTools: [ToolDescriptor] { tools.filter(\.isEnabled) }

    func toggle(_ id: String) {
        guard let index = tools.firstIndex(where: { $0.id == id }) else { return }
        tools[index].isEnabled.toggle()
    }
}

struct ToolPickerSheet: View {
    @Environment(ToolsStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Text("工具会在需要时由 Sherry 提议使用。你可以随时关闭，也可以在每次调用前确认。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
                toolSection(.skill, title: "Skills")
                toolSection(.mcp, title: "MCP 服务")
            }
            .navigationTitle("工具与 Skills")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }.fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private func toolSection(_ source: ToolDescriptor.Source, title: String) -> some View {
        Section(title) {
            ForEach(store.tools.filter { $0.source == source }) { tool in
                Button { store.toggle(tool.id) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: tool.icon)
                            .font(.title3)
                            .foregroundStyle(tool.isEnabled ? Color.accentColor : Color.secondary)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(tool.name).foregroundStyle(.primary)
                            Text(tool.summary).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: tool.isEnabled ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(tool.isEnabled ? Color.accentColor : Color.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private extension ToolDescriptor.Source {
    static var allCases: [Self] { [.skill, .mcp] }
}
