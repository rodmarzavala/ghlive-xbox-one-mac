import Foundation
import GHLiveCore
import GuitarInput
import KeyMapping
import Testing

@testable import GHLiveCLI

@Suite("Command line parsing")
struct ArgumentsTests {
    @Test("run without options")
    func plainRun() throws {
        #expect(try parseArguments(["run"]) == .run(RunOptions()))
    }

    @Test("run with every option")
    func runWithOptions() throws {
        let command = try parseArguments(["run", "--dry-run", "--verbose", "--keymap", "/tmp/map.json"])
        #expect(command == .run(RunOptions(dryRun: true, verbose: true, keymapPath: "/tmp/map.json")))
    }

    @Test("options may come in any order")
    func optionOrder() throws {
        let command = try parseArguments(["run", "--keymap", "k.json", "--verbose"])
        #expect(command == .run(RunOptions(dryRun: false, verbose: true, keymapPath: "k.json")))
    }

    @Test("--keymap needs a value")
    func keymapNeedsValue() {
        #expect(throws: ArgumentError.missingValue("--keymap")) { try parseArguments(["run", "--keymap"]) }
        #expect(throws: ArgumentError.missingValue("--keymap")) {
            try parseArguments(["run", "--keymap", "--verbose"])
        }
    }

    @Test("an unknown option is named")
    func unknownOption() {
        #expect(throws: ArgumentError.unknownOption("--turbo", command: "run")) {
            try parseArguments(["run", "--turbo"])
        }
    }

    @Test("sniff takes no options")
    func sniff() throws {
        #expect(try parseArguments(["sniff"]) == .sniff)
        #expect(throws: ArgumentError.unknownOption("--dry-run", command: "sniff")) {
            try parseArguments(["sniff", "--dry-run"])
        }
    }

    @Test("keymap --print-preset takes a preset name", arguments: KeymapPreset.allCases)
    func keymapPrintPreset(preset: KeymapPreset) throws {
        #expect(try parseArguments(["keymap", "--print-preset", preset.rawValue]) == .printKeymap(preset))
    }

    @Test("keymap --print-preset rejects a missing or unknown name")
    func keymapPrintPresetErrors() {
        #expect(throws: ArgumentError.missingValue("--print-preset")) {
            try parseArguments(["keymap", "--print-preset"])
        }
        #expect(throws: ArgumentError.missingValue("--print-preset")) {
            try parseArguments(["keymap", "--print-preset", "--verbose"])
        }
        #expect(throws: ArgumentError.invalidValue("seven-fret", option: "--print-preset")) {
            try parseArguments(["keymap", "--print-preset", "seven-fret"])
        }
        #expect(throws: ArgumentError.unknownOption("extra", command: "keymap")) {
            try parseArguments(["keymap", "--print-preset", "five-fret", "extra"])
        }
    }

    @Test("keymap --print-preset prints the keymap of that preset", arguments: KeymapPreset.allCases)
    func printedJSONRoundTripsToThePreset(preset: KeymapPreset) throws {
        let json = try keymapJSON(for: preset)
        #expect(try Keymap.parse(json: Data(json.utf8)) == preset.keymap)
    }

    @Test("the usage text lists every preset")
    func usageListsPresets() {
        for preset in KeymapPreset.allCases { #expect(usage.contains(preset.rawValue)) }
    }

    @Test("keymap --print-default")
    func keymapPrintDefault() throws {
        #expect(try parseArguments(["keymap", "--print-default"]) == .printKeymap(.sixFret))
        #expect(throws: ArgumentError.self) { try parseArguments(["keymap"]) }
        #expect(throws: ArgumentError.unknownOption("--bogus", command: "keymap")) {
            try parseArguments(["keymap", "--bogus"])
        }
    }

    @Test("charts add-ghl takes a folder and an optional --dry-run")
    func chartsAddGHL() throws {
        #expect(
            try parseArguments(["charts", "add-ghl", "/songs"])
                == .addGHLTracks(AddGHLOptions(folder: "/songs", dryRun: false)))
        #expect(
            try parseArguments(["charts", "add-ghl", "/songs", "--dry-run"])
                == .addGHLTracks(AddGHLOptions(folder: "/songs", dryRun: true)))
        #expect(
            try parseArguments(["charts", "add-ghl", "--dry-run", "My Songs"])
                == .addGHLTracks(AddGHLOptions(folder: "My Songs", dryRun: true)))
    }

    @Test("charts add-ghl rejects a missing folder, extra folders, unknown options and unknown subcommands")
    func chartsAddGHLErrors() {
        #expect(throws: ArgumentError.missingValue("charts add-ghl <folder>")) {
            try parseArguments(["charts", "add-ghl"])
        }
        #expect(throws: ArgumentError.missingValue("charts add-ghl <folder>")) {
            try parseArguments(["charts", "add-ghl", "--dry-run"])
        }
        #expect(throws: ArgumentError.unknownOption("--turbo", command: "charts add-ghl")) {
            try parseArguments(["charts", "add-ghl", "/songs", "--turbo"])
        }
        #expect(throws: ArgumentError.unknownOption("/other", command: "charts add-ghl")) {
            try parseArguments(["charts", "add-ghl", "/songs", "/other"])
        }
        #expect(throws: ArgumentError.unknownCommand("charts remove")) {
            try parseArguments(["charts", "remove"])
        }
        #expect(throws: ArgumentError.missingValue("charts add-ghl")) { try parseArguments(["charts"]) }
    }

    @Test("the usage text documents charts add-ghl")
    func usageMentionsCharts() {
        #expect(usage.contains("charts add-ghl <folder> [--dry-run]"))
    }

    @Test("version and help")
    func versionAndHelp() throws {
        #expect(try parseArguments(["--version"]) == .version)
        #expect(try parseArguments(["--help"]) == .help)
    }

    @Test("no command and unknown commands are errors")
    func badCommands() {
        #expect(throws: ArgumentError.missingCommand) { try parseArguments([]) }
        #expect(throws: ArgumentError.unknownCommand("dance")) { try parseArguments(["dance"]) }
    }
}

@Suite("Verbose reporter")
struct VerboseReporterTests {
    private func snapshot(_ controls: Set<Control>, tilt: UInt8) -> GuitarSnapshot {
        GuitarSnapshot(
            state: GuitarState(pressedButtons: [], dpad: [], whammy: 0, tilt: tilt),
            controls: controls
        )
    }

    @Test("reports a change of controls with the raw tilt")
    func reportsChanges() {
        var reporter = VerboseReporter()
        #expect(reporter.line(for: snapshot([], tilt: 100)) == "none | tilt=100")
        #expect(reporter.line(for: snapshot([.white1, .black1], tilt: 100)) == "black_1, white_1 | tilt=100")
    }

    @Test("stays quiet while nothing changes, including idle tilt jitter")
    func staysQuiet() {
        var reporter = VerboseReporter()
        _ = reporter.line(for: snapshot([], tilt: 100))
        #expect(reporter.line(for: snapshot([], tilt: 112)) == nil)
        #expect(reporter.line(for: snapshot([], tilt: 95)) == nil)
    }

    @Test("reports a large tilt move even when no control changes")
    func reportsTiltMove() {
        var reporter = VerboseReporter()
        _ = reporter.line(for: snapshot([], tilt: 100))
        #expect(reporter.line(for: snapshot([], tilt: 100 + UInt8(VerboseReporter.tiltReportStep))) != nil)
    }
}
