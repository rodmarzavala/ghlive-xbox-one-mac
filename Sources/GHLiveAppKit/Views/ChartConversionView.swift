import ChartConversion
import SwiftUI

/// The "Add 6-fret tracks to songs" window: confirmation, progress, then the result.
public struct ChartConversionView: View {
    public static let width: CGFloat = 560

    @ObservedObject private var model: ChartConversionModel
    private let scrollsSongList: Bool

    private static let songListMaxHeight: CGFloat = 260
    private static let pathLineLimit = 1

    /// `scrollsSongList` is off for screenshots: `ImageRenderer` cannot draw a scroll view.
    public init(model: ChartConversionModel, scrollsSongList: Bool = true) {
        self.model = model
        self.scrollsSongList = scrollsSongList
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            GlassGroup { content }
        }
        .padding(ScreenFit.contentPadding)
        .frame(width: Self.width)
        .onDisappear { model.dismiss() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Add 6-fret tracks to songs").font(.title2.weight(.semibold))
            Text("Play your 5-fret Clone Hero songs with the Guitar Hero Live guitar.")
                .font(.callout)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .idle: idle
        case .confirming(let folder): confirmation(folder)
        case .converting(let folder): converting(folder)
        case .finished(let report): result(report)
        case .failed(let message): failure(message)
        }
    }

    // MARK: States

    private var idle: some View {
        Button("Choose songs folder\u{2026}") { model.chooseFolder() }
            .ghButtonStyle(prominent: true)
    }

    private func confirmation(_ folder: URL) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    Label(folder.lastPathComponent, systemImage: "folder.fill").font(.headline)
                    Text(folder.path).font(.caption).foregroundColor(.secondary).lineLimit(Self.pathLineLimit)
                        .truncationMode(.middle)
                    bullet(
                        "Adds a 6-fret guitar track next to each 5-fret one, in this folder and the folders inside it. Nothing is ever removed."
                    )
                    bullet(
                        "Before changing a song, a copy of its files goes to \(ChartConversionCopy.backupLocation(for: folder))."
                    )
                    bullet("Songs that already have a 6-fret track are left alone. Songs packed as .sng are skipped.")
                }
            }
            HStack {
                Spacer()
                Button("Cancel", action: model.cancel).ghButtonStyle(prominent: false)
                Button("Add 6-fret tracks") { Task { await model.confirm() } }.ghButtonStyle(prominent: true)
            }
        }
    }

    private func converting(_ folder: URL) -> some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text("Converting the songs in \(folder.lastPathComponent)\u{2026} Keep GHLive open until this finishes.")
                .font(.callout)
        }
        .ghCard()
    }

    private func result(_ report: ConversionReport) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            summaryBanner(report)
            if report.convertedCount > 0 {
                Card {
                    NoticeLabel(
                        text: ConversionReport.rescanReminder, symbol: "arrow.clockwise.circle.fill", color: .blue)
                }
            }
            if let backup = report.backupFolder { backupCard(backup) }
            songList(report)
            HStack {
                Spacer()
                Button("Done", action: model.dismiss).ghButtonStyle(prominent: true)
            }
        }
    }

    private func summaryBanner(_ report: ConversionReport) -> some View {
        let tint: Color = report.hasFailures ? .red : .green
        let symbol = report.hasFailures ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
        return NoticeLabel(text: report.summary, symbol: symbol, color: tint)
            .font(.headline)
            .ghBanner(tint: tint)
    }

    private func backupCard(_ backup: URL) -> some View {
        Card {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Originals backed up to").font(.caption).foregroundColor(.secondary)
                    Text(backup.path).font(.callout).lineLimit(Self.pathLineLimit).truncationMode(.middle)
                }
                Spacer(minLength: 0)
                Button("Show in Finder", action: model.revealBackup).ghButtonStyle(prominent: false)
            }
        }
    }

    @ViewBuilder
    private func songList(_ report: ConversionReport) -> some View {
        let rows = LazyVStack(alignment: .leading, spacing: 6) {
            ForEach(Array(report.results.enumerated()), id: \.offset) { _, song in
                SongRow(result: song, dryRun: report.isDryRun)
            }
        }
        if scrollsSongList {
            ScrollView(.vertical) { rows }.frame(maxHeight: Self.songListMaxHeight)
        } else {
            rows
        }
    }

    private func failure(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Card(emphasis: .red) {
                NoticeLabel(text: message, symbol: "xmark.octagon.fill", color: .red).font(.callout)
            }
            HStack {
                Spacer()
                Button("Close", action: model.dismiss).ghButtonStyle(prominent: true)
            }
        }
    }

    private func bullet(_ text: String) -> some View {
        Text(text).font(.callout).fixedSize(horizontal: false, vertical: true)
    }
}

private struct SongRow: View {
    let result: SongResult
    let dryRun: Bool

    private static let symbolWidth: CGFloat = 18

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol).foregroundColor(color).frame(width: Self.symbolWidth)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(result.path).font(.callout).lineLimit(1).truncationMode(.middle)
                if let detail = result.detailText {
                    Text(detail).font(.caption).foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(result.line(dryRun: dryRun))
    }

    private var symbol: String {
        switch result.outcome {
        case .converted where result.isFailure, .failed: "xmark.octagon.fill"
        case .converted: "checkmark.circle.fill"
        case .alreadyHasSixFret, .noFiveFretTrack, .unsupportedFormat: "minus.circle"
        }
    }

    private var color: Color {
        switch result.outcome {
        case .converted where result.isFailure, .failed: .red
        case .converted: .green
        case .alreadyHasSixFret, .noFiveFretTrack, .unsupportedFormat: .secondary
        }
    }
}
