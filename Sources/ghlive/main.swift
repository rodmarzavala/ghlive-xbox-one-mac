import Foundation

private let arguments = Array(CommandLine.arguments.dropFirst())

do {
    exit(await execute(try parseArguments(arguments)))
} catch {
    FileHandle.standardError.write(Data("ghlive: \(error)\n\n\(usage)\n".utf8))
    exit(ExitCode.usage)
}
