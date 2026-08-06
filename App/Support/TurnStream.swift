import Foundation
import YushiKit

/// 回合事件流（第 2 批）：URLSession bytes → SSEParser → TurnEventEnvelope 异步序列。
/// 网络绑定按既定分层放 App 层（SSEParser.swift:18 约定；Linux corelibs 对 bytes(for:) 支持差，
/// 解析器留在 Core 保住 CI 可测线）。
///
/// 流礼仪（约定的另一端是网关 server.ts；原网页版 sse.ts 已删）：
/// - data 行是 TurnEventEnvelope 信封；completed / error 是终止帧，服务端发完主动关流
/// - `event: gone` = 回合已被网关清理（超保留窗/重启）——按正常终止处理，上层回落拉历史
/// - 掉线（无终止帧即断流）自动重连，带 Last-Event-ID 严格续传（回放 id 大于游标的信封）
enum TurnStream {
    /// 打开 turnId 的事件流。正常收尾（终止帧 / gone）→ 流正常结束；
    /// 反复重连仍失败 → 抛错（上层把 streaming 中的消息标成连接中断）。
    static func events(
        client: GatewayClient,
        turnId: String
    ) -> AsyncThrowingStream<TurnEventEnvelope, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                let config = URLSessionConfiguration.default
                config.timeoutIntervalForRequest = 300 // SSE 空闲档：思考长静默不算超时
                config.timeoutIntervalForResource = 3600
                let session = URLSession(configuration: config)
                defer { session.finishTasksAndInvalidate() }

                var lastEnvelopeId: Int?
                var attempts = 0
                var terminal = false

                while !terminal && !Task.isCancelled {
                    do {
                        guard let url = client.url(path: "/api/turns/\(turnId)/events") else {
                            throw GatewayError.invalidURL
                        }
                        var request = URLRequest(url: url)
                        request.timeoutInterval = 300
                        request.setValue("text/event-stream", forHTTPHeaderField: "accept")
                        if let token = client.config.authToken, !token.isEmpty {
                            request.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
                        }
                        if let lastEnvelopeId {
                            request.setValue(String(lastEnvelopeId), forHTTPHeaderField: "Last-Event-ID")
                        }

                        let (bytes, response) = try await session.bytes(for: request)
                        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                            throw GatewayError.http(
                                status: (response as? HTTPURLResponse)?.statusCode ?? 0,
                                detail: "事件流连接被拒"
                            )
                        }
                        attempts = 0

                        var parser = SSEParser()
                        var lineBuf: [UInt8] = []
                        for try await byte in bytes {
                            lineBuf.append(byte)
                            // 只在行尾冲刷：UTF-8 多字节序列不含 0x0A，中文不会被劈坏
                            guard byte == 0x0A else { continue }
                            let piece = String(decoding: lineBuf, as: UTF8.self)
                            lineBuf.removeAll(keepingCapacity: true)
                            for sse in parser.feed(piece) {
                                if sse.event == "gone" {
                                    terminal = true
                                    break
                                }
                                guard let env = TurnEventEnvelope.decode(sseData: sse.data) else { continue }
                                lastEnvelopeId = env.id
                                continuation.yield(env)
                                switch env.event {
                                case .completed, .error:
                                    terminal = true
                                default:
                                    break
                                }
                                if terminal { break }
                            }
                            if terminal { break }
                        }

                        if !terminal {
                            // 服务端断流但没给终止帧：稍候重连续传
                            attempts += 1
                            if attempts > 5 { throw GatewayError.transport("事件流反复中断") }
                            try await Task.sleep(nanoseconds: 1_500_000_000)
                        }
                    } catch is CancellationError {
                        break
                    } catch {
                        if Task.isCancelled { break }
                        attempts += 1
                        if attempts > 5 {
                            continuation.finish(throwing: error)
                            return
                        }
                        try? await Task.sleep(nanoseconds: 1_500_000_000)
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
