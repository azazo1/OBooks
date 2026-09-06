import Foundation
import OSLog

enum CloudHTTP {
    static let contentLimit: Int64 = 512 * 1024 * 1024

    struct ByteRange: Equatable {
        var start: Int64?
        var end: Int64?
        var total: Int64?
    }

    static func etag(_ response: HTTPURLResponse) -> String? {
        parseETag(response.value(forHTTPHeaderField: "ETag"))
    }

    static func parseETag(_ raw: String?) -> String? {
        guard var value = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        if value.hasPrefix("W/") {
            value = String(value.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        }
        if value.first == "\"", value.last == "\"", value.count >= 2 {
            value = String(value.dropFirst().dropLast())
        }
        return value.isEmpty ? nil : value
    }

    static func contentLength(_ response: HTTPURLResponse) -> Int64? {
        if let value = response.value(forHTTPHeaderField: "Content-Length"), let size = Int64(value), size >= 0 {
            return size
        }
        if response.expectedContentLength > 0 { return response.expectedContentLength }
        return nil
    }

    static func contentRange(_ raw: String?) -> ByteRange? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix("bytes ") else { return nil }
        let spec = String(trimmed.dropFirst(6)).trimmingCharacters(in: .whitespaces)
        let parts = spec.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        let total: Int64? = parts[1] == "*" ? nil : Int64(parts[1])
        if parts[0] == "*" { return ByteRange(start: nil, end: nil, total: total) }
        let bounds = parts[0].split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        guard bounds.count == 2, let start = Int64(bounds[0]), let end = Int64(bounds[1]) else { return nil }
        return ByteRange(start: start, end: end, total: total)
    }
}

struct CloudFileDownload: Equatable {
    var statusCode: Int
    var etag: String?
    var expectedSize: Int64?
    var bytesWritten: Int64
}

enum SyncFileTransfer {
    static func download(
        configuration: URLSessionConfiguration,
        request: URLRequest,
        to handle: FileHandle,
        existingBytes: Int64,
        progress: @escaping @Sendable (Int64, Int64?) -> Void
    ) async throws -> CloudFileDownload {
        let holder = StreamHolder()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let stream = StreamDownload(
                    handle: handle,
                    existingBytes: existingBytes,
                    progress: progress,
                    continuation: continuation
                )
                holder.stream = stream
                let session = URLSession(configuration: configuration, delegate: stream, delegateQueue: nil)
                stream.session = session
                let task = session.dataTask(with: request)
                stream.task = task
                task.resume()
            }
        } onCancel: {
            holder.stream?.task?.cancel()
        }
    }
}

private final class StreamHolder: @unchecked Sendable {
    var stream: StreamDownload?
}

private final class StreamDownload: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    let handle: FileHandle
    let existingBytes: Int64
    let progress: @Sendable (Int64, Int64?) -> Void
    var continuation: CheckedContinuation<CloudFileDownload, Error>?
    var session: URLSession?
    var task: URLSessionTask?
    var statusCode = 0
    var etag: String?
    var expectedSize: Int64?
    var bytesWritten: Int64 = 0
    var discardedExisting = false
    private let logger = Logger(subsystem: "com.obooks.app", category: "sync.transfer")

    init(
        handle: FileHandle,
        existingBytes: Int64,
        progress: @escaping @Sendable (Int64, Int64?) -> Void,
        continuation: CheckedContinuation<CloudFileDownload, Error>
    ) {
        self.handle = handle
        self.existingBytes = existingBytes
        self.progress = progress
        self.continuation = continuation
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let http = response as? HTTPURLResponse else {
            completionHandler(.cancel)
            fail(CloudSyncError.message("服务端响应无效"))
            return
        }
        statusCode = http.statusCode
        etag = CloudHTTP.etag(http)
        if statusCode == 401 {
            completionHandler(.cancel)
            fail(CloudSyncError.unauthorized)
            return
        }
        if statusCode == 416 {
            completionHandler(.cancel)
            if let total = CloudHTTP.contentRange(http.value(forHTTPHeaderField: "Content-Range"))?.total,
               total > 0, existingBytes >= total {
                expectedSize = total
                succeed(bytesWritten: 0)
            } else {
                fail(CloudSyncError.message("续传范围无效"))
            }
            return
        }
        if statusCode == 200 {
            expectedSize = CloudHTTP.contentLength(http)
            if !truncateToStart() {
                completionHandler(.cancel)
                return
            }
            discardedExisting = existingBytes > 0
        } else if statusCode == 206 {
            let range = CloudHTTP.contentRange(http.value(forHTTPHeaderField: "Content-Range"))
            expectedSize = range?.total
            if let start = range?.start, start != existingBytes {
                if start == 0 {
                    if !truncateToStart() {
                        completionHandler(.cancel)
                        return
                    }
                    discardedExisting = true
                } else {
                    completionHandler(.cancel)
                    fail(CloudSyncError.message("续传范围无效"))
                    return
                }
            }
        } else {
            completionHandler(.cancel)
            fail(CloudSyncError.message("同步请求失败: HTTP \(statusCode)"))
            return
        }
        if let expectedSize, expectedSize > CloudHTTP.contentLimit {
            completionHandler(.cancel)
            fail(CloudSyncError.message("文件过大"))
            return
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let next = baseOffset() + bytesWritten + Int64(data.count)
        if next > CloudHTTP.contentLimit {
            task?.cancel()
            fail(CloudSyncError.message("文件过大"))
            return
        }
        do {
            try handle.write(contentsOf: data)
            bytesWritten += Int64(data.count)
            progress(baseOffset() + bytesWritten, expectedSize)
        } catch {
            task?.cancel()
            fail(error)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            if (error as? URLError)?.code == .cancelled, continuation == nil { return }
            fail(error)
            return
        }
        succeed(bytesWritten: bytesWritten)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }

    private func baseOffset() -> Int64 {
        discardedExisting ? 0 : existingBytes
    }

    @discardableResult
    private func truncateToStart() -> Bool {
        do {
            try handle.truncate(atOffset: 0)
            try handle.seek(toOffset: 0)
            return true
        } catch {
            fail(error)
            return false
        }
    }

    private func succeed(bytesWritten: Int64) {
        do { try handle.synchronize() } catch { fail(error); return }
        finish(.success(CloudFileDownload(
            statusCode: statusCode,
            etag: etag,
            expectedSize: expectedSize,
            bytesWritten: bytesWritten
        )))
    }

    private func fail(_ error: Error) {
        try? handle.synchronize()
        logger.error("文件传输失败: \(error.localizedDescription, privacy: .public)")
        finish(.failure(error))
    }

    private func finish(_ result: Result<CloudFileDownload, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        session?.finishTasksAndInvalidate()
        session = nil
        continuation.resume(with: result)
    }
}
