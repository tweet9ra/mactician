import Foundation

// Development-only frontend for the exact release parser. No raw log output.
@main
struct GameLogProbe {
    static func main() throws {
        if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--command",
           let command = GameLogObservation.command(package: CommandLine.arguments[2]) {
            print(command)
            return
        }
        guard CommandLine.arguments.count == 2, ["--decode", "--context", "--bracket"].contains(CommandLine.arguments[1]) else {
            fputs("Usage: tft-game-log-probe --command PACKAGE | --decode/--context < snapshot | --bracket < base64-pair-json\n", stderr)
            exit(2)
        }
        let bracket = CommandLine.arguments[1] == "--bracket"
        let maximum = bracket ? GameLogObservation.maximumResponseBytes * 3 : GameLogObservation.maximumResponseBytes
        var data = Data()
        while data.count <= maximum,
              let chunk = try FileHandle.standardInput.read(upToCount: min(8192, maximum + 1 - data.count)), !chunk.isEmpty {
            data.append(chunk)
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        if bracket {
            guard data.count <= maximum, let pair = try? JSONDecoder().decode([Data].self, from: data), pair.count == 2 else { exit(2) }
            let result = GameLogObservation.bracket(GameLogObservation.decode(pair[0]), GameLogObservation.decode(pair[1]))
            print(String(decoding: try encoder.encode(["context": result.scene, "reason": result.reason]), as: UTF8.self))
        } else {
            let observation = GameLogObservation.decode(data)
            if CommandLine.arguments[1] == "--context" {
                print(String(decoding: try encoder.encode(["context": observation.context, "read": observation.outcome,
                    "lifecycle": observation.lifecycle, "lifecycle_age": observation.lifecycleAge,
                    "phase_event": observation.phaseEvent, "phase_age": observation.phaseAge]), as: UTF8.self))
            } else { print(String(decoding: try encoder.encode(observation), as: UTF8.self)) }
        }
    }
}
