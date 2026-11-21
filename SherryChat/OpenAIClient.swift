import Foundation

/// OpenAI 兼容的流式客户端：chat completions + SSE。
/// 只做一件事：发请求、逐 token 回来。Key 由调用方传进来，
/// 这里不存 Key、不打日志、不猜服务商和模型。
/// 失败原因都翻成一句大白话（`AIError.reason`），调用方直接画出来。
enum AIError: Error {
    case badURL
    case unauthorized // 401，Key 不对
    case notFound // 404，这个地址没有聊天接口
    case rateLimited // 429，请求太多了
    case badRequest // 400，常常是模型名不对
    case http(Int)
    case network
    case emptyReply
    case badResponse

    var reason: String {
        switch self {
        case .badURL: return "地址写错了，检查一下 base URL"
        case .unauthorized: return "Key 不对，检查一下 API Key"
        case .notFound: return "这个地址没有聊天接口，检查一下 base URL"
        case .rateLimited: return "请求太多了，等一会儿再试"
        case .badRequest: return "请求被拒绝了，检查一下模型名"
        case .http(let code): return "对方返回了 \(code)，稍后再试"
        case .network: return "网络连不上，检查网络或 base URL"
        case .emptyReply: return "对方回了个空消息，再试一次"
        case .badResponse: return "对方回的东西看不懂，再试一次"
        }
    }
}

/// 发给 API 的一条消息：role 是 system/user/assistant。
struct ChatAPIMessage: Codable, Sendable {
    var role: String
    var content: String
}

/// 流式客户端：`actor` + `URLSession.bytes(for:)` 逐行读 SSE。
/// token 攒约 33ms 一刷（EchoUI 的 StreamChunkCoalescer 思路），
/// 别每个 token 都刷一次 UI。
/// 读到的是一段段文本（`AsyncThrowingStream<String, Error>`），
/// 调用方把它们拼到同一条消息上，id 全程不变。
actor OpenAIClient {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func completeChat(
        baseURL: String,
        model: String,
        apiKey: String,
        messages: [ChatAPIMessage]
    ) async throws -> String {
        guard let url = URL(string: baseURL + "/v1/chat/completions") else { throw AIError.badURL }
        var request = URLRequest(url: url, timeoutInterval: 60)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(ChatCompletionsRequest(model: model, messages: messages, stream: false))
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AIError.badResponse }
        switch http.statusCode { case 200: break; case 401: throw AIError.unauthorized; case 404: throw AIError.notFound; case 429: throw AIError.rateLimited; case 400: throw AIError.badRequest; default: throw AIError.http(http.statusCode) }
        guard let content = try? JSONDecoder().decode(ChatCompletion.self, from: data).choices.first?.message.content,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AIError.emptyReply }
        return content
    }

    func streamChat(
        baseURL: String,
        model: String,
        apiKey: String,
        messages: [ChatAPIMessage]
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let url = URL(string: baseURL + "/v1/chat/completions") else {
                        throw AIError.badURL
                    }
                    var request = URLRequest(url: url, timeoutInterval: 120)
                    request.httpMethod = "POST"
                    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.httpBody = try JSONEncoder().encode(
                        ChatCompletionsRequest(model: model, messages: messages, stream: true)
                    )
                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        throw AIError.badResponse
                    }
                    switch http.statusCode {
                    case 200: break
                    case 401: throw AIError.unauthorized
                    case 404: throw AIError.notFound
                    case 429: throw AIError.rateLimited
                    case 400: throw AIError.badRequest
                    default: throw AIError.http(http.statusCode)
                    }
                    // SSE：一行一个 data: {...}，空行和 ":" 注释跳过，
                    // "[DONE]" 就是流完了。内容在 choices[].delta.content 里。
                    var pending = ""
                    var lastFlush = Date()
                    var gotAny = false
                    for try await line in bytes.lines {
                        if Task.isCancelled { break }
                        guard line.hasPrefix("data:") else { continue }
                        let data = line.dropFirst("data:".count)
                            .trimmingCharacters(in: .whitespaces)
                        if data == "[DONE]" { break }
                        guard let json = data.data(using: .utf8),
                              let chunk = try? JSONDecoder().decode(ChatChunk.self, from: json),
                              let content = chunk.choices.first?.delta.content,
                              !content.isEmpty
                        else { continue }
                        gotAny = true
                        pending += content
                        if Date().timeIntervalSince(lastFlush) >= 0.033 {
                            continuation.yield(pending)
                            pending = ""
                            lastFlush = Date()
                        }
                    }
                    if !pending.isEmpty { continuation.yield(pending) }
                    if !gotAny { throw AIError.emptyReply }
                    continuation.finish()
                } catch let error as AIError {
                    continuation.finish(throwing: error)
                } catch is URLError {
                    continuation.finish(throwing: AIError.network)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            // 调用方不读了（比如重试删了那条消息），就把网络任务也停掉。
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// POST /v1/chat/completions 的请求体。
private struct ChatCompletion: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable { var content: String }
        var message: Message
    }
    var choices: [Choice]
}

private struct ChatCompletionsRequest: Encodable {
    var model: String
    var messages: [ChatAPIMessage]
    var stream: Bool
}

/// SSE 里一帧：只要 choices[].delta.content。
private struct ChatChunk: Decodable {
    struct Choice: Decodable {
        struct Delta: Decodable {
            var content: String?
        }
        var delta: Delta
    }
    var choices: [Choice]
}
