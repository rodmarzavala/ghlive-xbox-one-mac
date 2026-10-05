import Foundation
import KeyMapping

struct RunOptions: Equatable {
    var dryRun = false
    var verbose = false
    var keymapPath: String?
}

enum Command: Equatable {
    case run(RunOptions)
    case sniff
    case printKeymap(KeymapPreset)
    case version
    case help
}

enum ArgumentError: Error, Equatable, CustomStringConvertible {
    case missingCommand
    case unknownCommand(String)
    case unknownOption(String, command: String)
    case missingValue(String)
    case invalidValue(String, option: String)

    var description: String {
        switch self {
        case .missingCommand: "missing command"
        case .unknownCommand(let name): "unknown command '\(name)'"
        case .unknownOption(let option, let command): "unknown option '\(option)' for '\(command)'"
        case .missingValue(let option): "option '\(option)' needs a value"
        case .invalidValue(let value, let option):
            "'\(value)' is not a valid value for '\(option)' (use \(KeymapPreset.names))"
        }
    }
}

extension KeymapPreset {
    static var names: String { allCases.map(\.rawValue).joined(separator: "|") }
}

let usage = """
    usage: ghlive <command> [options]

    commands:
      run [--dry-run] [--verbose] [--keymap PATH]
                      Wait for the dongle and turn guitar input into key presses.
                      --dry-run prints the key events instead of posting them.
      sniff           Print the raw GIP packets of the dongle.
      keymap --print-default
                      Print the default (6-fret) keymap as JSON.
      keymap --print-preset \(KeymapPreset.names)
                      Print a keymap preset as JSON: six-fret for Guitar Hero Live charts,
                      five-fret for classic 5-lane charts (keys 1-5).

    options:
      --version       Print the version.
      --help          Print this help.
    """

func parseArguments(_ arguments: [String]) throws -> Command {
    guard let first = arguments.first else { throw ArgumentError.missingCommand }
    let rest = Array(arguments.dropFirst())
    switch first {
    case "--version", "-v": return .version
    case "--help", "-h", "help": return .help
    case "run": return .run(try parseRunOptions(rest))
    case "sniff": return try requireNoOptions(rest, command: first, result: .sniff)
    case "keymap": return try parseKeymapOptions(rest)
    default: throw ArgumentError.unknownCommand(first)
    }
}

private let printDefaultOption = "--print-default"
private let printPresetOption = "--print-preset"

private func parseKeymapOptions(_ arguments: [String]) throws -> Command {
    guard arguments.first == printPresetOption else {
        return try requireOnlyOption(
            printDefaultOption, in: arguments, command: "keymap", result: .printKeymap(.sixFret))
    }
    guard let name = arguments.dropFirst().first else { throw ArgumentError.missingValue(printPresetOption) }
    guard let preset = KeymapPreset(rawValue: name) else {
        throw ArgumentError.invalidValue(name, option: printPresetOption)
    }
    return try requireNoOptions(Array(arguments.dropFirst(2)), command: "keymap", result: .printKeymap(preset))
}

private func parseRunOptions(_ arguments: [String]) throws -> RunOptions {
    var options = RunOptions()
    var remaining = arguments[...]
    while let argument = remaining.popFirst() {
        switch argument {
        case "--dry-run": options.dryRun = true
        case "--verbose": options.verbose = true
        case "--keymap":
            guard let path = remaining.popFirst(), !path.hasPrefix("--") else {
                throw ArgumentError.missingValue(argument)
            }
            options.keymapPath = path
        default: throw ArgumentError.unknownOption(argument, command: "run")
        }
    }
    return options
}

private func requireNoOptions(_ arguments: [String], command: String, result: Command) throws -> Command {
    if let option = arguments.first { throw ArgumentError.unknownOption(option, command: command) }
    return result
}

private func requireOnlyOption(
    _ expected: String,
    in arguments: [String],
    command: String,
    result: Command
) throws -> Command {
    guard !arguments.isEmpty else { throw ArgumentError.missingValue("\(command) \(expected)") }
    if let unexpected = arguments.first(where: { $0 != expected }) {
        throw ArgumentError.unknownOption(unexpected, command: command)
    }
    return result
}
