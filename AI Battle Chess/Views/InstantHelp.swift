import SwiftUI

// MARK: - Instant Help Modifier

/// A tooltip that appears instantly on hover, replacing the slow system `.help()` delay.
private struct InstantHelpModifier: ViewModifier {
    let text: String
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                isHovering = hovering
            }
            .overlay(alignment: .top) {
                if isHovering {
                    Text(text)
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(.windowBackgroundColor))
                                .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
                        )
                        .fixedSize()
                        .offset(y: -28)
                        .allowsHitTesting(false)
                        .transition(.opacity.animation(.easeIn(duration: 0.1)))
                        .zIndex(1000)
                }
            }
    }
}

extension View {
    /// Shows a tooltip instantly on hover (no system delay).
    /// Drop-in replacement for `.help()`.
    func instantHelp(_ text: String) -> some View {
        modifier(InstantHelpModifier(text: text))
    }
}
