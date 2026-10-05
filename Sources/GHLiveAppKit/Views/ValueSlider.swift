import SwiftUI

/// A slider drawn in SwiftUI (a native `Slider` cannot be rendered into a screenshot). `onCommit` fires when
/// the drag ends or after a VoiceOver adjustment.
struct ValueSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let accessibilityName: String
    let formatted: (Double) -> String
    let onCommit: () -> Void

    private static let trackHeight: CGFloat = 6
    private static let thumbSize: CGFloat = 18
    private static let trackOpacity = 0.18

    var body: some View {
        GeometryReader { proxy in
            let usable = max(proxy.size.width - Self.thumbSize, 1)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(Self.trackOpacity)).frame(height: Self.trackHeight)
                Capsule().fill(Color.accentColor)
                    .frame(width: usable * fraction + Self.thumbSize / 2, height: Self.trackHeight)
                Circle()
                    .fill(Color.white)
                    .overlay(Circle().stroke(Color.primary.opacity(Metrics.strokeOpacity * 2), lineWidth: 1))
                    .shadow(color: .black.opacity(0.25), radius: 1.5, y: 1)
                    .frame(width: Self.thumbSize, height: Self.thumbSize)
                    .offset(x: usable * fraction)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let position = (drag.location.x - Self.thumbSize / 2) / usable
                        value = snapped(range.lowerBound + min(max(position, 0), 1) * span)
                    }
                    .onEnded { _ in onCommit() }
            )
        }
        .frame(height: Self.thumbSize + 6)
        .accessibilityElement()
        .accessibilityLabel(accessibilityName)
        .accessibilityValue(formatted(value))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = snapped(min(value + step, range.upperBound))
            case .decrement: value = snapped(max(value - step, range.lowerBound))
            @unknown default: return
            }
            onCommit()
        }
    }

    private var span: Double { range.upperBound - range.lowerBound }

    private var fraction: Double { min(max((value - range.lowerBound) / span, 0), 1) }

    private func snapped(_ raw: Double) -> Double {
        SliderSnapping.snapped(raw, in: range, step: step)
    }
}

enum SliderSnapping {
    private static let decimalNoise = 1e9

    /// Steps count from the lower bound (0.05 steps from 0.05 land on 0.35, not on multiples of 0.05 off by
    /// a binary fraction), and float noise such as 0.35000000000000003 is rounded away.
    static func snapped(_ raw: Double, in range: ClosedRange<Double>, step: Double) -> Double {
        let steps = ((raw - range.lowerBound) / step).rounded()
        let value = ((range.lowerBound + steps * step) * decimalNoise).rounded() / decimalNoise
        return min(max(value, range.lowerBound), range.upperBound)
    }
}
