import SwiftUI

struct ModelSettingsPage: View {
    @Environment(AgentProfile.self) private var profile
    @State private var baseURL = ""
    @State private var model = ""
    @State private var key = ""
    @State private var showKey = false
    @State private var models: [String] = []
    @State private var loading = false
    @State private var status: String?

    var body: some View {
        Form {
            Section {
                Picker("预设", selection: $baseURL) {
                    Text("自定义").tag("")
                    Text("OpenAI").tag("https://api.openai.com")
                    Text("DeepSeek").tag("https://api.deepseek.com")
                    Text("OpenRouter").tag("https://openrouter.ai/api")
                }
                TextField("Base URL", text: $baseURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
            } header: {
                Text("服务渠道")
            } footer: {
                Text("填写服务根地址；应用会处理兼容接口路径。")
            }

            Section("API 密钥") {
                HStack {
                    Group { if showKey { TextField("API Key", text: $key) } else { SecureField(profile.hasAPIKey ? "已保存，留空保持原值" : "API Key", text: $key) } }
                        .textInputAutocapitalization(.never).autocorrectionDisabled().privacySensitive()
                    Button { showKey.toggle() } label: { Image(systemName: showKey ? "eye.slash" : "eye") }.buttonStyle(.plain)
                }
                Label("密钥只存入 iOS Keychain，不进入配置文件和日志。", systemImage: "lock.shield").font(.caption).foregroundStyle(.secondary)
            }

            Section("模型") {
                TextField("模型 ID", text: $model).textInputAutocapitalization(.never).autocorrectionDisabled()
                Button { Task { await fetchModels() } } label: { HStack { Text("获取模型列表"); Spacer(); if loading { ProgressView() } } }.disabled(loading)
                ForEach(models, id: \.self) { item in Button { model = item } label: { HStack { Text(item).foregroundStyle(.primary); Spacer(); if item == model { Image(systemName: "checkmark").foregroundStyle(.tint) } } } }
            }

            Section("连接验证") {
                Button("保存并测试") { Task { await saveAndTest() } }.fontWeight(.semibold)
                if let status { Text(status).font(.subheadline).foregroundStyle(profile.testState == .ok ? .green : .secondary) }
            }

            if profile.isConfigured { Section { Button("删除当前渠道", role: .destructive) { profile.clearChannel(); baseURL="";model="";key="";models=[];status=nil } } }
        }
        .navigationTitle("模型与渠道").navigationBarTitleDisplayMode(.inline)
        .onAppear { baseURL=profile.baseURL;model=profile.modelName }
    }

    private func persist() {
        profile.baseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.modelName = model.trimmingCharacters(in: .whitespacesAndNewlines)
        if !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { profile.saveAPIKey(key); key="" }
    }
    private func fetchModels() async {
        persist(); loading=true; defer { loading=false }
        let result=await profile.fetchModelIDs();models=result.0
        status=result.1 ?? (models.isEmpty ? "服务没有列出模型，请手动填写模型 ID" : "已读取 \(models.count) 个模型")
    }
    private func saveAndTest() async {
        persist()
        guard !profile.normalizedBaseURL.isEmpty else { status="请填写服务地址";return }
        guard profile.hasAPIKey else { status="请填写 API Key";return }
        guard !profile.modelName.isEmpty else { status="请填写或选择模型";return }
        await profile.testConnection()
        switch profile.testState { case .ok: status="连接成功";case .failed(let text):status=text;default:break }
    }
}
