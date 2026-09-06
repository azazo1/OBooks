import Foundation

private final class SyncRedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

private final class SyncTransferProgress: NSObject, URLSessionDownloadDelegate, URLSessionTaskDelegate {
    let onProgress: @Sendable (Double) -> Void
    init(onProgress: @escaping @Sendable (Double) -> Void) { self.onProgress = onProgress }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesWritten > 512 * 1024 * 1024 { downloadTask.cancel(); return }
        if totalBytesExpectedToWrite > 0 { onProgress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        if totalBytesExpectedToSend > 0 { onProgress(Double(totalBytesSent) / Double(totalBytesExpectedToSend)) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

@MainActor
final class SyncAPI {
    let server: URL
    private let credentials: any SyncCredentialStorage
    private let session: URLSession
    private var accessToken: String?
    private var expiresAt = Date.distantPast
    private var refreshTask: Task<SyncTokens, Error>?
    var onServerTime: ((TimeInterval) -> Void)?

    init(server: URL, credentials: any SyncCredentialStorage, session: URLSession? = nil) {
        self.server = server
        self.credentials = credentials
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 15 * 60
        configuration.httpShouldSetCookies = false
        self.session = session ?? URLSession(configuration: configuration, delegate: SyncRedirectPolicy(), delegateQueue: nil)
    }

    static func validateServer(_ value: String) throws -> URL {
        guard var components = URLComponents(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil, components.query == nil, components.fragment == nil,
              components.scheme == "https" || (components.scheme == "http" && ["localhost", "127.0.0.1", "[::1]", "::1"].contains(host)) else {
            throw CloudSyncError.message("服务地址必须使用 HTTPS, 本机回环地址可使用 HTTP")
        }
        while components.path.hasSuffix("/") { components.path.removeLast() }
        guard let url = components.url else { throw CloudSyncError.message("服务地址无效") }
        return url
    }

    func login(username: String, password: String, deviceID: String, deviceName: String) async throws -> SyncTokens {
        struct Login: Encodable { var username: String; var password: String; var deviceID: String; var deviceName: String }
        do {
            let body = try SyncCoding.encoder().encode(Login(username: username, password: password, deviceID: deviceID, deviceName: deviceName))
            let tokens: SyncTokens = try await request("v1/auth/login", method: "POST", body: body, authenticated: false)
            try accept(tokens)
            return tokens
        } catch {
            throw CloudSyncError.forLogin(error)
        }
    }

    func logout() async throws {
        guard let refresh = try credentials.read() else { return }
        let body = try JSONEncoder().encode(["refreshToken": refresh])
        let (_, response) = try await session.data(for: makeRequest("v1/auth/logout", method: "POST", body: body))
        try check(response, data: Data())
        accessToken = nil
        expiresAt = .distantPast
        try credentials.remove()
    }

    func updateAccount(deviceName: String?, currentPassword: String?, newPassword: String?) async throws {
        struct Body: Encodable {
            var deviceName: String?
            var currentPassword: String?
            var newPassword: String?
        }
        do {
            let body = try SyncCoding.encoder().encode(Body(deviceName: deviceName, currentPassword: currentPassword, newPassword: newPassword))
            try await authorized { token in
                var request = self.makeRequest("v1/auth/account", method: "POST", body: body)
                request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
                let (data, response) = try await self.session.data(for: request)
                try self.check(response, data: data)
            }
        } catch let error as URLError {
            throw CloudSyncError.message(CloudSyncError.connectionMessage(error))
        }
    }

    func pull(cursor: Int64) async throws -> SyncPull {
        try await request("v1/sync/pull", query: [URLQueryItem(name: "cursor", value: String(cursor))])
    }

    func push(_ changes: [SyncChange]) async throws -> SyncPush {
        struct Push: Encodable { var changes: [SyncChange] }
        return try await request("v1/sync/push", method: "POST", body: SyncCoding.encoder().encode(Push(changes: changes)))
    }

    func fileExists(bookID: String, kind: String) async throws -> Bool {
        try await authorized { token in
            var request = self.makeRequest("v1/books/\(bookID)/\(kind)", method: "HEAD")
            request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
            let (data, response) = try await self.session.data(for: request)
            if (response as? HTTPURLResponse)?.statusCode == 404 { return false }
            try self.check(response, data: data)
            return true
        }
    }

    func upload(_ file: URL, bookID: String, kind: String, progress: @escaping @Sendable (Double) -> Void) async throws {
        try await authorized { token in
            var request = self.makeRequest("v1/books/\(bookID)/\(kind)", method: "PUT")
            request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
            request.setValue(kind == "content" ? "application/epub+zip" : "image/png", forHTTPHeaderField: "Content-Type")
            let delegate = SyncTransferProgress(onProgress: progress)
            let (data, response) = try await self.session.upload(for: request, fromFile: file, delegate: delegate)
            try self.check(response, data: data)
        }
    }

    func download(bookID: String, kind: String, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        try await authorized { token in
            var request = self.makeRequest("v1/books/\(bookID)/\(kind)")
            request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
            let delegate = SyncTransferProgress(onProgress: progress)
            let (url, response) = try await self.session.download(for: request, delegate: delegate)
            do { try self.check(response, data: Data()) } catch { try? FileManager.default.removeItem(at: url); throw error }
            return url
        }
    }

    private func request<T: Decodable>(_ path: String, method: String = "GET", body: Data? = nil, authenticated: Bool = true, query: [URLQueryItem] = []) async throws -> T {
        let perform: (String?) async throws -> T = { token in
            var request = self.makeRequest(path, method: method, body: body, query: query)
            if let token { request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
            let (data, response) = try await self.session.data(for: request)
            try self.check(response, data: data, sessionRetry: authenticated)
            guard data.count <= 16 * 1024 * 1024 else { throw CloudSyncError.message("服务端响应过大") }
            return try SyncCoding.decoder().decode(T.self, from: data)
        }
        if authenticated { return try await authorized { token in try await perform(token) } }
        return try await perform(nil)
    }

    private func authorized<T>(_ operation: (String) async throws -> T) async throws -> T {
        let token = try await token()
        do { return try await operation(token) }
        catch CloudSyncError.unauthorized {
            expiresAt = .distantPast
            return try await operation(try await self.token())
        }
    }

    private func token() async throws -> String {
        if let accessToken, expiresAt > Date().addingTimeInterval(30) { return accessToken }
        if let refreshTask { return try await refreshTask.value.accessToken }
        guard let refreshToken = try credentials.read() else { throw CloudSyncError.unauthorized }
        let task = Task { @MainActor in
            let body = try JSONEncoder().encode(["refreshToken": refreshToken])
            let tokens: SyncTokens = try await self.request("v1/auth/refresh", method: "POST", body: body, authenticated: false)
            try self.accept(tokens)
            return tokens
        }
        refreshTask = task
        defer { refreshTask = nil }
        return try await task.value.accessToken
    }

    private func accept(_ tokens: SyncTokens) throws {
        try credentials.write(tokens.refreshToken)
        accessToken = tokens.accessToken
        expiresAt = Date().addingTimeInterval(TimeInterval(tokens.expiresIn))
        onServerTime?(tokens.serverTime)
    }

    private func makeRequest(_ path: String, method: String = "GET", body: Data? = nil, query: [URLQueryItem] = []) -> URLRequest {
        var components = URLComponents(url: server.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.httpBody = body
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        return request
    }

    private func check(_ response: URLResponse, data: Data, sessionRetry: Bool = true) throws {
        guard let http = response as? HTTPURLResponse else { throw CloudSyncError.message("服务端响应无效") }
        if http.statusCode == 401 {
            let message = serverMessage(from: data)
            if sessionRetry, message == nil || message == "请重新登录" || (message?.contains("会话") == true) {
                throw CloudSyncError.unauthorized
            }
            throw CloudSyncError.message(message ?? "账号或密码无效")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw CloudSyncError.message(serverMessage(from: data) ?? "同步请求失败: HTTP \(http.statusCode)")
        }
    }

    private func serverMessage(from data: Data) -> String? {
        struct Failure: Decodable { struct Detail: Decodable { var message: String }; var error: Detail }
        return (try? JSONDecoder().decode(Failure.self, from: data))?.error.message
    }
}
