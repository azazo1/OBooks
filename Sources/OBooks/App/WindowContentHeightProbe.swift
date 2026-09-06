import AppKit
import SwiftUI

struct ViewHeightPreference: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// 把宿主窗口高度跟到 SwiftUI 内容高度, 变化时顶边不动.
struct WindowContentHeightProbe: NSViewRepresentable {
    var height: CGFloat

    func makeNSView(context: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard height > 1, let window = nsView.window else { return }
        AppWindowConfiguration.setContentHeight(height, in: window)
    }
}

extension View {
    func tracksWindowContentHeight() -> some View {
        modifier(WindowContentHeightTracker())
    }
}

private struct WindowContentHeightTracker: ViewModifier {
    @State private var height: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .fixedSize(horizontal: false, vertical: true)
            .background(
                GeometryReader { geo in
                    Color.clear.preference(key: ViewHeightPreference.self, value: geo.size.height)
                }
            )
            .onPreferenceChange(ViewHeightPreference.self) { height = $0 }
            .background(WindowContentHeightProbe(height: height))
    }
}
