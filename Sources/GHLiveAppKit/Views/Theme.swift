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
    static let emphasisBorder: CGFloat = 1.5
}

struct Card<Content: View>: View {
    private let border: Color
    private let borderWidth: CGFloat
    private let content: Content

    /// `border` replaces the neutral outline, for cards that must stand out.
    init(border: Color? = nil, @ViewBuilder content: () -> Content) {
        self.border = border ?? Color.primary.opacity(Metrics.strokeOpacity)
        borderWidth = border == nil ? Metrics.hairline : Metrics.emphasisBorder
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
                    .stroke(border, lineWidth: borderWidth)
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

/// A quieter button next to a primary one.
struct SecondaryButtonStyle: ButtonStyle {
    private static let pressedOpacity = 0.6

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.medium))
            .foregroundColor(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.primary.opacity(Metrics.cardFillOpacity)))
            .overlay(Capsule().stroke(Color.primary.opacity(Metrics.strokeOpacity * 2), lineWidth: Metrics.hairline))
            .opacity(configuration.isPressed ? Self.pressedOpacity : 1)
    }
}

/// Coloured icon, primary text: coloured text does not reach AA contrast in light mode.
struct NoticeLabel: View {
    let text: String
    let symbol: String
    let color: Color

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: symbol).foregroundColor(color).accessibilityHidden(true)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }
}
