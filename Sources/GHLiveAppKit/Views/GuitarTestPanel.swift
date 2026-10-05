import GuitarInput
import SwiftUI

/// The "Test my guitar" checklist: one row per control, grouped like Settings, with the progress on top.
struct GuitarTestPanel: View {
    let session: GuitarTestSession
    let onStartOver: () -> Void

    private static let wideColumnCount = 3
    private static let narrowColumnCount = 2
    private static let columnSpacing: CGFloat = 12
    private static let rowSpacing: CGFloat = 4

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            progressHeader
            if session.isComplete { successBanner }
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(ControlGroup.all) { group in
                        groupSection(group)
                    }
                }
            }
        }
    }

    private var progressHeader: some View {
        HStack {
            Text(session.progressText).font(.headline).accessibilityAddTraits(.updatesFrequently)
            Spacer()
            Button("Start over", action: onStartOver).ghButtonStyle(prominent: false)
        }
    }

    private var successBanner: some View {
        NoticeLabel(text: GuitarTestSession.completionMessage, symbol: "checkmark.seal.fill", color: .green)
            .font(.callout.weight(.semibold))
            .ghBanner(tint: .green)
            .accessibilityElement(children: .combine)
    }

    private func groupSection(_ group: ControlGroup) -> some View {
        VStack(alignment: .leading, spacing: Self.rowSpacing) {
            Text(group.title.uppercased()).font(.caption.weight(.semibold)).foregroundColor(.secondary)
            ForEach(rows(of: group), id: \.first) { row in
                HStack(spacing: Self.columnSpacing) {
                    ForEach(row, id: \.self) { control in
                        ChecklistRow(
                            name: control.friendlyName, isVerified: session.isVerified(control),
                            status: session.statusText(for: control), detail: session.rangeText(for: control))
                    }
                    if row.count < columnCount(of: group) { Spacer(minLength: 0).frame(maxWidth: .infinity) }
                }
            }
        }
    }

    /// Controls that show a range need the full width. Otherwise groups of three or six keep the fret rows
    /// (Black 1-3, White 1-3) lined up, and the rest pair up.
    private func columnCount(of group: ControlGroup) -> Int {
        if group.controls.contains(where: { session.rangeText(for: $0) != nil }) { return 1 }
        return group.controls.count % Self.wideColumnCount == 0 ? Self.wideColumnCount : Self.narrowColumnCount
    }

    private func rows(of group: ControlGroup) -> [[Control]] {
        let size = columnCount(of: group)
        return stride(from: 0, to: group.controls.count, by: size).map {
            Array(group.controls[$0..<min($0 + size, group.controls.count)])
        }
    }
}

private struct ChecklistRow: View {
    let name: String
    let isVerified: Bool
    let status: String
    let detail: String?

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: isVerified ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isVerified ? .green : .secondary)
                .accessibilityHidden(true)
            Text(name)
            if let detail {
                Spacer(minLength: 8)
                Text(detail).font(.caption).foregroundColor(.secondary).monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
        .accessibilityValue(detail.map { "\(status), \($0)" } ?? status)
    }
}
