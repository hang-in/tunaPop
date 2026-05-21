import Foundation

struct SSEEvent: Sendable {
    let name: String?
    let data: String
}

struct SSEStreamParser {
    /// Server-Sent Events 스트림 바이트 라인을 비동기 시퀀스로 파싱하는 헬퍼
    static func parse(_ lines: AsyncLineSequence<URLSession.AsyncBytes>) -> AsyncThrowingStream<SSEEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var currentEventName: String? = nil
                    for try await line in lines {
                        try Task.checkCancellation()
                        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { continue }
                        
                        if trimmed.hasPrefix("event: ") {
                            currentEventName = String(trimmed.dropFirst(7)).trimmingCharacters(in: .whitespacesAndNewlines)
                            continue
                        }
                        
                        if trimmed.hasPrefix("data: ") {
                            let dataPayload = String(trimmed.dropFirst(6)).trimmingCharacters(in: .whitespacesAndNewlines)
                            continuation.yield(SSEEvent(name: currentEventName, data: dataPayload))
                        }
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch let urlError as URLError where urlError.code == .cancelled {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}
