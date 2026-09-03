import Foundation

private struct ReaderSettingsPayload: Encodable {
    let flow: String
    let theme: String
    let fontSize: Double
    let lineHeight: Double
    let margin: Double
}

enum ReaderBridge {
    static let script = resource(named: "reader", extension: "js") ?? fallbackScript
    static let stylesheet = resource(named: "reader", extension: "css") ?? fallbackStylesheet

    private static func resource(named name: String, extension fileExtension: String) -> String? {
        let url = Bundle.module.url(forResource: name, withExtension: fileExtension, subdirectory: "Reader")
            ?? Bundle.module.url(forResource: name, withExtension: fileExtension)
        guard let url else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    static func settingsJSON(flow: ReadingFlow, theme: ReadingTheme, fontSize: Double, lineHeight: Double, margin: Double) -> String? {
        let payload = ReaderSettingsPayload(flow: flow.rawValue, theme: theme.rawValue, fontSize: fontSize, lineHeight: lineHeight, margin: margin)
        guard let data = try? JSONEncoder().encode(payload) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static let fallbackScript = #"""
    (() => {
        const post = (body) => window.webkit?.messageHandlers?.reader?.postMessage(body);
        const root = () => document.documentElement;
        const report = () => post({ type: "progress", fraction: 0 });
        const page = (direction) => {
            const flow = root().dataset.flow || "paginated";
            const amount = Math.max(320, (flow === "paginated" ? window.innerWidth : window.innerHeight) * 0.86);
            if (flow === "paginated") window.scrollBy({ left: direction * amount, behavior: "smooth" });
            else window.scrollBy({ top: direction * amount, behavior: "smooth" });
        };
        window.obooksReader = {
            setSettings(settings) {
                root().dataset.flow = settings.flow;
                root().dataset.theme = settings.theme;
                root().style.setProperty("--obooks-font-size", settings.fontSize + "px");
                root().style.setProperty("--obooks-line-height", settings.lineHeight);
                root().style.setProperty("--obooks-margin", settings.margin + "px");
                report();
            },
            nextPage: () => page(1),
            previousPage: () => page(-1),
            readableText: () => document.body.innerText || document.body.textContent || "",
            highlight: () => {},
            clearHighlight: () => {}
        };
        post({ type: "ready" });
    })();
    """#

    private static let fallbackStylesheet = #"""
    :root {
        --obooks-font-size: 18px;
        --obooks-line-height: 1.72;
        --obooks-margin: 56px;
        --obooks-background: #fbfbfa;
        --obooks-foreground: #202124;
        --obooks-accent: #2d6cdf;
    }
    html, body { background: var(--obooks-background) !important; color: var(--obooks-foreground) !important; }
    html { min-height: 100%; overflow-x: auto; }
    body {
        box-sizing: border-box;
        margin: 0 auto !important;
        max-width: 880px;
        padding: var(--obooks-margin) max(24px, 6vw) 96px !important;
        font-size: var(--obooks-font-size) !important;
        line-height: var(--obooks-line-height) !important;
    }
    body img, body svg, body video { max-width: 100%; height: auto; }
    html[data-flow="paginated"] { height: 100%; overflow-x: auto; overflow-y: hidden; }
    html[data-flow="paginated"] body {
        width: auto;
        max-width: none;
        height: 100vh;
        padding: var(--obooks-margin) max(36px, 7vw) !important;
        column-width: calc(100vw - max(72px, 14vw));
        column-gap: max(72px, 14vw);
        column-fill: auto;
        overflow: visible;
    }
    html[data-flow="scrolled"] { overflow-x: hidden; overflow-y: auto; }
    html[data-theme="ivory"] { --obooks-background: #f4efdf; --obooks-foreground: #3d372f; }
    html[data-theme="dark"] { --obooks-background: #1c1c1e; --obooks-foreground: #e7e7e9; }
    a { color: var(--obooks-accent); }
    pre { white-space: pre-wrap; overflow-wrap: anywhere; }
    .obooks-speech-highlight { background: rgba(255, 204, 64, 0.55) !important; color: inherit !important; border-radius: 3px; }
    """#
}
