import SwiftUI

struct OBooksIconButtonStyle: ButtonStyle {
    let size: CGFloat
    let cornerRadius: CGFloat
    let normalBackgroundOpacity: Double

    init(size: CGFloat = 34, cornerRadius: CGFloat = 9, normalBackgroundOpacity: Double = 0) {
        self.size = size
        self.cornerRadius = cornerRadius
        self.normalBackgroundOpacity = normalBackgroundOpacity
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: size, height: size)
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius))
            .background {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.white.opacity(normalBackgroundOpacity))
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.14 : 0))
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.white.opacity(configuration.isPressed ? 0.08 : 0), lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct OBooksSidebarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.08 : 0))
                    .padding(.horizontal, 5)
            }
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
