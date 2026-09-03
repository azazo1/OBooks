import AppKit
import SwiftUI
import WebKit

final class ReaderController: ObservableObject {
    @Published private(set) var command: ReaderCommand?

    func send(_ action: ReaderAction) {
        command = ReaderCommand(action: action)
    }
}

final class BookSchemeHandler: NSObject, WKURLSchemeHandler {
    private let rootURL: URL
    private let fileManager = FileManager.default

    init(rootURL: URL) {
        self.rootURL = rootURL.standardizedFileURL
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        let requestURL = urlSchemeTask.request.url
        DispatchQueue.global(qos: .userInitiated).async { [rootURL, fileManager] in
            do {
                guard let requestURL else { throw EPUBImportError.invalidPackage("资源地址为空") }
                let path = requestURL.path.removingPercentEncoding ?? requestURL.path
                let relativePath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                guard !relativePath.isEmpty else { throw EPUBImportError.invalidPackage("资源路径为空") }
                let fileURL = rootURL.appendingPathComponent(relativePath).standardizedFileURL
                guard fileURL.path.hasPrefix(rootURL.path + "/"), fileManager.fileExists(atPath: fileURL.path) else {
                    throw EPUBImportError.invalidPackage("找不到章节资源")
                }
                var data = try Data(contentsOf: fileURL)
                let mimeType = Self.mimeType(for: fileURL.pathExtension)
                if mimeType == "text/html" || mimeType == "application/xhtml+xml" {
                    let html = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
                    data = Data(Self.injectStyle(into: html).utf8)
                }
                let response = URLResponse(url: requestURL, mimeType: mimeType, expectedContentLength: data.count, textEncodingName: mimeType.contains("html") ? "utf-8" : nil)
                DispatchQueue.main.async {
                    urlSchemeTask.didReceive(response)
                    urlSchemeTask.didReceive(data)
                    urlSchemeTask.didFinish()
                }
            } catch {
                DispatchQueue.main.async { urlSchemeTask.didFailWithError(error) }
            }
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}

    private static func injectStyle(into html: String) -> String {
        let style = "<style id=\"obooks-reader-style\">\(ReaderBridge.stylesheet)</style>"
        if let range = html.range(of: "</head>", options: [.caseInsensitive]) {
            var result = html
            result.insert(contentsOf: style, at: range.lowerBound)
            return result
        }
        return style + html
    }

    private static func mimeType(for fileExtension: String) -> String {
        switch fileExtension.lowercased() {
        case "xhtml", "html", "htm": return "text/html"
        case "css": return "text/css"
        case "js": return "text/javascript"
        case "svg": return "image/svg+xml"
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "woff": return "font/woff"
        case "woff2": return "font/woff2"
        case "ttf": return "font/ttf"
        case "otf": return "font/otf"
        default: return "application/octet-stream"
        }
    }
}

struct ReaderWebView: NSViewRepresentable {
    let book: BookSummary
    @Binding var sectionIndex: Int
    let flow: ReadingFlow
    let theme: ReadingTheme
    let fontSize: Double
    let lineHeight: Double
    let margin: Double
    @ObservedObject var controller: ReaderController
    let onProgress: (Double) -> Void
    let onBoundary: (Int) -> Void
    let onSpeakingChanged: (Bool) -> Void
    let onAnnotation: (String, String) -> Void
    let onNoteRequest: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.setURLSchemeHandler(BookSchemeHandler(rootURL: book.folderURL), forURLScheme: "obook")
        configuration.userContentController.add(context.coordinator, name: "reader")
        configuration.userContentController.addUserScript(WKUserScript(source: ReaderBridge.script, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        context.coordinator.update(book: book, flow: flow, theme: theme, fontSize: fontSize, lineHeight: lineHeight, margin: margin, onProgress: onProgress, onBoundary: onBoundary, onSpeakingChanged: onSpeakingChanged, onAnnotation: onAnnotation, onNoteRequest: onNoteRequest)
        context.coordinator.loadSection(in: webView, index: sectionIndex)
        return webView
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.teardown(webView: webView)
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let coordinator = context.coordinator
        coordinator.update(book: book, flow: flow, theme: theme, fontSize: fontSize, lineHeight: lineHeight, margin: margin, onProgress: onProgress, onBoundary: onBoundary, onSpeakingChanged: onSpeakingChanged, onAnnotation: onAnnotation, onNoteRequest: onNoteRequest)
        if coordinator.currentSectionIndex != sectionIndex { coordinator.loadSection(in: webView, index: sectionIndex) }
        if coordinator.lastCommandID != controller.command?.id, let command = controller.command {
            coordinator.execute(command.action, in: webView)
            coordinator.lastCommandID = command.id
        }
        coordinator.applySettingsIfNeeded(in: webView)
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        private(set) var currentSectionIndex = -1
        var lastCommandID: UUID?
        private var lastSettings: Settings?
        private var currentBook: BookSummary?
        private var flow: ReadingFlow = .paginated
        private var theme: ReadingTheme = .paper
        private var fontSize = 18.0
        private var lineHeight = 1.7
        private var margin = 56.0
        private let speech = SpeechService()
        private var onProgress: (Double) -> Void = { _ in }
        private var onBoundary: (Int) -> Void = { _ in }
        private var onSpeakingChanged: (Bool) -> Void = { _ in }
        private var onAnnotation: (String, String) -> Void = { _, _ in }
        private var onNoteRequest: (String) -> Void = { _ in }

        struct Settings: Equatable {
            let flow: ReadingFlow
            let theme: ReadingTheme
            let fontSize: Double
            let lineHeight: Double
            let margin: Double
        }

        func update(book: BookSummary, flow: ReadingFlow, theme: ReadingTheme, fontSize: Double, lineHeight: Double, margin: Double, onProgress: @escaping (Double) -> Void, onBoundary: @escaping (Int) -> Void, onSpeakingChanged: @escaping (Bool) -> Void, onAnnotation: @escaping (String, String) -> Void, onNoteRequest: @escaping (String) -> Void) {
            currentBook = book
            self.flow = flow
            self.theme = theme
            self.fontSize = fontSize
            self.lineHeight = lineHeight
            self.margin = margin
            self.onProgress = onProgress
            self.onBoundary = onBoundary
            self.onSpeakingChanged = onSpeakingChanged
            self.onAnnotation = onAnnotation
            self.onNoteRequest = onNoteRequest
        }

        func teardown(webView: WKWebView) {
            speech.onRange = nil
            speech.onFinished = nil
            speech.onStateChanged = nil
            speech.stop()
            webView.navigationDelegate = nil
            webView.configuration.userContentController.removeScriptMessageHandler(forName: "reader")
        }

        func loadSection(in webView: WKWebView, index: Int) {
            guard let book = currentBook, book.spine.indices.contains(index), let url = Self.makeBookURL(book.spine[index].href) else { return }
            speech.stop()
            currentSectionIndex = index
            lastSettings = nil
            webView.load(URLRequest(url: url))
        }

        func execute(_ action: ReaderAction, in webView: WKWebView) {
            switch action {
            case .nextPage: webView.evaluateJavaScript("window.obooksReader?.nextPage();")
            case .previousPage: webView.evaluateJavaScript("window.obooksReader?.previousPage();")
            case .toggleSpeech: toggleSpeech(in: webView)
            case .stopSpeech:
                speech.stop()
                webView.evaluateJavaScript("window.obooksReader?.clearHighlight();")
            case .speakText(let text):
                speech.stop()
                speech.onStateChanged = { [weak self] speaking in
                    self?.onSpeakingChanged(speaking)
                }
                speech.speak(text: text)
            }
        }

        func applySettingsIfNeeded(in webView: WKWebView) {
            let settings = Settings(flow: flow, theme: theme, fontSize: fontSize, lineHeight: lineHeight, margin: margin)
            guard settings != lastSettings, let json = ReaderBridge.settingsJSON(flow: flow, theme: theme, fontSize: fontSize, lineHeight: lineHeight, margin: margin) else { return }
            lastSettings = settings
            webView.evaluateJavaScript("window.obooksReader?.setSettings(\(json));")
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
            switch type {
            case "progress": onProgress((body["fraction"] as? NSNumber)?.doubleValue ?? 0)
            case "boundary": onBoundary((body["direction"] as? NSNumber)?.intValue ?? 0)
            case "ready": if let webView = message.webView { applySettingsIfNeeded(in: webView) }
            case "annotation":
                onAnnotation(body["text"] as? String ?? "", body["kind"] as? String ?? "highlight")
            case "noteRequest":
                onNoteRequest(body["text"] as? String ?? "")
            default: break
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            applySettingsIfNeeded(in: webView)
        }

        private func toggleSpeech(in webView: WKWebView) {
            if speech.isSpeaking {
                speech.stop()
                webView.evaluateJavaScript("window.obooksReader?.clearHighlight();")
                return
            }
            webView.evaluateJavaScript("window.obooksReader?.readableText();") { [weak self, weak webView] value, _ in
                guard let self, let text = value as? String else { return }
                self.speech.onRange = { [weak webView] range in
                    guard range.location != NSNotFound else { return }
                    DispatchQueue.main.async {
                        webView?.evaluateJavaScript("window.obooksReader?.highlight(\(range.location), \(range.length));")
                    }
                }
                self.speech.onStateChanged = { [weak self] speaking in
                    self?.onSpeakingChanged(speaking)
                }
                self.speech.speak(text: text)
            }
        }

        private static func makeBookURL(_ path: String) -> URL? {
            let encoded = path.split(separator: "/").map { component in
                String(component).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))) ?? String(component)
            }.joined(separator: "/")
            return URL(string: "obook://book/\(encoded)")
        }
    }
}
