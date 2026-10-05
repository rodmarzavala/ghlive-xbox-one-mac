import Foundation

public enum LaunchOptions: Equatable, Sendable {
    case runApp
    case exportScreenshots(directory: URL)
    case invalid(String)

    public static let exportScreenshotsFlag = "--export-screenshots"

    /// `arguments` excludes the program name.
    public static func parse(_ arguments: [String]) -> LaunchOptions {
        guard let flagIndex = arguments.firstIndex(of: exportScreenshotsFlag) else { return .runApp }
        let valueIndex = arguments.index(after: flagIndex)
        guard valueIndex < arguments.endIndex else {
            return .invalid("\(exportScreenshotsFlag) needs a directory")
        }
        return .exportScreenshots(directory: URL(fileURLWithPath: arguments[valueIndex], isDirectory: true))
    }
}
