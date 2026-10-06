import Foundation
import KeyMapping

struct RunOptions: Equatable {
    var dryRun = false
    var verbose = false
    var keymapPath: String?
}

struct AddGHLOptions: Equatable {
    var folder: String
    var dryRun = false
}

enum Command: Equatable {
    case run(RunOptions)
    case sniff
    case printKeymap(KeymapPreset)
    case addGHLTracks(AddGHLOptions)
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

      charts add-ghl <folder> [--dry-run]
                      Add 6-fret (GHL) guitar tracks to the 5-fret charts in a songs folder, so the
                      songs can be played with the guitar. Originals are copied to a backup folder
                      next to <folder> first; existing tracks are never removed. --dry-run only
                      reports what would change.

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
    case "charts": return try parseChartsOptions(rest)
    default: throw ArgumentError.unknownCommand(first)
    }
}

private let addGHLSubcommand = "add-ghl"

private func parseChartsOptions(_ arguments: [String]) throws -> Command {
    guard let subcommand = arguments.first else { throw ArgumentError.missingValue("charts \(addGHLSubcommand)") }
    guard subcommand == addGHLSubcommand else { throw ArgumentError.unknownCommand("charts \(subcommand)") }
    let command = "charts \(addGHLSubcommand)"
    var folder: String?
    var dryRun = false
    for argument in arguments.dropFirst() {
        if argument == "--dry-run" {
            dryRun = true
        } else if argument.hasPrefix("--") || folder != nil {
            throw ArgumentError.unknownOption(argument, command: command)
        } else {
            folder = argument
        }
    }
    guard let folder else { throw ArgumentError.missingValue("\(command) <folder>") }
    return .addGHLTracks(AddGHLOptions(folder: folder, dryRun: dryRun))
}

private let printDefaultOption = "--print-default"
private let printPresetOption = "--print-preset"

private func parseKeymapOptions(_ arguments: [String]) throws -> Command {
    guard arguments.first == printPresetOption else {
        return try requireOnlyOption(
            printDefaultOption, in: arguments, command: "keymap", result: .printKeymap(.sixFret))
    }
    var remaining = arguments.dropFirst()
    let name = try takeValue(from: &remaining, for: printPresetOption)
    guard let preset = KeymapPreset(rawValue: name) else {
        throw ArgumentError.invalidValue(name, option: printPresetOption)
    }
    return try requireNoOptions(Array(remaining), command: "keymap", result: .printKeymap(preset))
}

private func parseRunOptions(_ arguments: [String]) throws -> RunOptions {
    var options = RunOptions()
    var remaining = arguments[...]
    while let argument = remaining.popFirst() {
        switch argument {
        case "--dry-run": options.dryRun = true
        case "--verbose": options.verbose = true
        case "--keymap":
            options.keymapPath = try takeValue(from: &remaining, for: argument)
        default: throw ArgumentError.unknownOption(argument, command: "run")
        }
    }
    return options
}

/// The value after an option; another option in its place means the value was left out.
private func takeValue(from remaining: inout ArraySlice<String>, for option: String) throws -> String {
    guard let value = remaining.popFirst(), !value.hasPrefix("--") else { throw ArgumentError.missingValue(option) }
    return value
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
