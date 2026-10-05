import Foundation
import GHLiveCLI

exit(await runCLI(arguments: Array(CommandLine.arguments.dropFirst())))
