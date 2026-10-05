import SwiftUI

extension StatusTone {
    var color: Color {
        switch self {
        case .waiting: .gray
        case .ready: .orange
        case .active: .green
        case .paused: .blue
        case .error: .red
        }
    }
}

enum Metrics {
    static let cornerRadius: CGFloat = 10
    static let cardPadding: CGFloat = 12
    static let cardFillOpacity = 0.06
    static let strokeOpacity = 0.15
    static let hairline: CGFloat = 1
}

struct Card<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(Metrics.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous)
                    .fill(Color.primary.opacity(Metrics.cardFillOpacity))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous)
                    .stroke(Color.primary.opacity(Metrics.strokeOpacity), lineWidth: Metrics.hairline)
            )
    }
}

struct StatusBadge: View {
    let status: StatusPresentation
    var size: CGFloat = 34

    private static let fillOpacity = 0.18
    private static let symbolScale = 0.5

    var body: some View {
        ZStack {
            Circle().fill(status.tone.color.opacity(Self.fillOpacity))
            Image(systemName: status.symbolName)
                .font(.system(size: size * Self.symbolScale, weight: .medium))
                .foregroundColor(status.tone.color)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Drawn in SwiftUI only: AppKit-backed controls render as placeholders in `ImageRenderer` screenshots.
struct PillButtonStyle: ButtonStyle {
    private static let pressedOpacity = 0.75

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.medium))
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.accentColor))
            .opacity(configuration.isPressed ? Self.pressedOpacity : 1)
    }
}
