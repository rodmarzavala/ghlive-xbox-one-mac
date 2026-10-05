import Foundation
import GHLiveAppKit

switch LaunchOptions.parse(Array(CommandLine.arguments.dropFirst())) {
case .runApp:
    GHLiveApplication.main()
case .exportScreenshots(let directory):
    do {
        for file in try ScreenshotExporter.export(to: directory) {
            print(file.path)
        }
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("GHLiveApp: \(error)\n".utf8))
        exit(1)
    }
case .invalid(let reason):
    FileHandle.standardError.write(Data("GHLiveApp: \(reason)\n".utf8))
    exit(2)
}
