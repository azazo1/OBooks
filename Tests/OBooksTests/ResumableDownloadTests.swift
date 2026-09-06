import Foundation
import XCTest
@testable import OBooks

final class ResumableDownloadTests: XCTestCase {
    func testParseETagAndContentRange() {
        XCTAssertEqual(CloudHTTP.parseETag("\"abc\""), "abc")
        XCTAssertEqual(CloudHTTP.parseETag("W/\"abc\""), "abc")
        XCTAssertEqual(CloudHTTP.parseETag("abc"), "abc")
        XCTAssertEqual(CloudHTTP.contentRange("bytes 10-19/100"), CloudHTTP.ByteRange(start: 10, end: 19, total: 100))
        XCTAssertEqual(CloudHTTP.contentRange("bytes */80"), CloudHTTP.ByteRange(start: nil, end: nil, total: 80))
        XCTAssertNil(CloudHTTP.contentRange("invalid"))
    }

    func testPrepareResumesMatchingETagAndRestartsOnChange() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let bookID = String(repeating: "a", count: 64)
        let download = ResumableDownload.content(rootURL: directory, bookID: bookID)
        XCTAssertEqual(try download.prepare(remoteETag: "tag1", remoteSize: 100), 0)

        let handle = try download.openHandle(reset: true)
        try handle.write(contentsOf: Data(repeating: 1, count: 40))
        try handle.close()
        try download.saveSidecar(.init(etag: "tag1", expectedSize: 100))
        XCTAssertEqual(try download.prepare(remoteETag: "tag1", remoteSize: 100), 40)

        XCTAssertEqual(try download.prepare(remoteETag: "tag2", remoteSize: 100), 0)
        XCTAssertEqual(download.localSize, 0)
        XCTAssertNil(download.loadSidecar())
    }

    func testRangeResumeAfterDisconnect() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let payload = Data((0..<4096).map { UInt8($0 % 251) })
        RangeHTTPStub.reset(file: payload, etag: "tag1")
        let download = ResumableDownload.content(rootURL: directory, bookID: String(repeating: "b", count: 64))
        let first = try download.openHandle(reset: true)
        try first.write(contentsOf: payload.prefix(1000))
        try first.close()
        try download.saveSidecar(.init(etag: "tag1", expectedSize: Int64(payload.count)))
        XCTAssertEqual(download.localSize, 1000)

        let offset = try download.prepare(remoteETag: "tag1", remoteSize: Int64(payload.count))
        XCTAssertEqual(offset, 1000)
        let second = try download.openHandle(reset: false)
        var request = URLRequest(url: URL(string: "https://example.com/v1/books/x/content")!)
        request.setValue("bytes=1000-", forHTTPHeaderField: "Range")
        let result = try await SyncFileTransfer.download(
            configuration: RangeHTTPStub.configuration(),
            request: request,
            to: second,
            existingBytes: 1000,
            progress: { _, _ in }
        )
        try second.close()
        XCTAssertEqual(result.statusCode, 206)
        XCTAssertEqual(try Data(contentsOf: download.partialURL), payload)
        XCTAssertTrue(RangeHTTPStub.requests.contains { $0.value(forHTTPHeaderField: "Range") == "bytes=1000-" })
    }

    func testCancelledDownloadKeepsPartialAndResumes() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let payload = Data(repeating: 7, count: 64 * 1024)
        RangeHTTPStub.reset(file: payload, etag: "keep", hangAfter: 2048)
        let download = ResumableDownload.content(rootURL: directory, bookID: String(repeating: "c", count: 64))
        let handle = try download.openHandle(reset: true)
        try download.saveSidecar(.init(etag: "keep", expectedSize: Int64(payload.count)))
        let task = Task {
            try await SyncFileTransfer.download(
                configuration: RangeHTTPStub.configuration(),
                request: URLRequest(url: URL(string: "https://example.com/v1/books/x/content")!),
                to: handle,
                existingBytes: 0,
                progress: { _, _ in }
            )
        }
        let started = Date()
        while download.localSize == 0, Date().timeIntervalSince(started) < 2 {
            try await Task.sleep(for: .milliseconds(20))
        }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("取消后不应成功")
        } catch {
            try handle.close()
        }
        let kept = download.localSize
        XCTAssertGreaterThan(kept, 0)
        XCTAssertNotNil(download.loadSidecar())

        RangeHTTPStub.hangAfter = nil
        let offset = try download.prepare(remoteETag: "keep", remoteSize: Int64(payload.count))
        XCTAssertEqual(offset, kept)
        let resumeHandle = try download.openHandle(reset: false)
        var request = URLRequest(url: URL(string: "https://example.com/v1/books/x/content")!)
        request.setValue("bytes=\(kept)-", forHTTPHeaderField: "Range")
        _ = try await SyncFileTransfer.download(
            configuration: RangeHTTPStub.configuration(),
            request: request,
            to: resumeHandle,
            existingBytes: kept,
            progress: { _, _ in }
        )
        try resumeHandle.close()
        XCTAssertEqual(try Data(contentsOf: download.partialURL), payload)
    }
}

private final class RangeHTTPStub: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var fileData = Data()
    private static var etagValue = "tag"
    static var hangAfter: Int?
    static var requests: [URLRequest] = []
    private var awaitingCancel = false

    static func reset(file: Data, etag: String, hangAfter: Int? = nil) {
        lock.lock()
        fileData = file
        etagValue = etag
        self.hangAfter = hangAfter
        requests = []
        lock.unlock()
    }

    static func configuration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RangeHTTPStub.self]
        configuration.timeoutIntervalForRequest = 5
        configuration.timeoutIntervalForResource = 5
        return configuration
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.requests.append(request)
        let file = Self.fileData
        let etag = Self.etagValue
        let hangAfter = Self.hangAfter
        Self.lock.unlock()

        if request.httpMethod == "HEAD" {
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                headerFields: ["ETag": "\"\(etag)\"", "Content-Length": String(file.count)]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
            return
        }

        let start = rangeStart(from: request)
        let slice = start > 0 ? Data(file[start...]) : file
        var headers = ["ETag": "\"\(etag)\"", "Content-Length": String(slice.count)]
        let status: Int
        if start > 0 {
            status = 206
            headers["Content-Range"] = "bytes \(start)-\(file.count - 1)/\(file.count)"
        } else {
            status = 200
        }
        let response = HTTPURLResponse(
            url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)

        if let hangAfter {
            awaitingCancel = true
            client?.urlProtocol(self, didLoad: Data(slice.prefix(hangAfter)))
            return
        }
        client?.urlProtocol(self, didLoad: slice)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {
        guard awaitingCancel else { return }
        awaitingCancel = false
        client?.urlProtocol(self, didFailWithError: URLError(.cancelled))
    }

    private func rangeStart(from request: URLRequest) -> Int {
        guard let header = request.value(forHTTPHeaderField: "Range"),
              header.hasPrefix("bytes="), header.hasSuffix("-"),
              let start = Int(header.dropFirst(6).dropLast()) else { return 0 }
        return start
    }
}
