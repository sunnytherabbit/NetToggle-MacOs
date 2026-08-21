import Foundation

final class HelperRunner {
    static let `default` = HelperRunner()

    var helperPath: String {
        if let envPath = ProcessInfo.processInfo.environment["NETTOGGLE_HELPER"] {
            return envPath
        }
        let candidates = [
            "/usr/local/bin/NetToggleHelper",
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".local/bin/NetToggleHelper").path
        ]
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return candidates[0]
    }

    func run(
        command: String,
        inDelayMs: Int = 0,
        inPacketLoss: Double = 0.0,
        outDelayMs: Int = 0,
        outPacketLoss: Double = 0.0,
        completion: @escaping (Bool, String) -> Void
    ) {
        let path = helperPath

        guard FileManager.default.isExecutableFile(atPath: path) else {
            completion(false, "Helper not found or not executable at \(path)")
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)

        if command == "on" {
            process.arguments = [
                "on",
                "\(inDelayMs)",
                "\(inPacketLoss)",
                "\(outDelayMs)",
                "\(outPacketLoss)"
            ]
        } else {
            process.arguments = ["off"]
        }

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        process.terminationHandler = { proc in
            let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: outData, encoding: .utf8) ?? ""
            let error = String(data: errData, encoding: .utf8) ?? ""

            DispatchQueue.main.async {
                if proc.terminationStatus == 0 {
                    completion(true, output)
                } else {
                    let msg = error.isEmpty ? output : error
                    completion(false, "NetToggleHelper failed (exit \(proc.terminationStatus)): \(msg)")
                }
            }
        }

        do {
            try process.run()
        } catch {
            completion(false, "Failed to start helper: \(error.localizedDescription)")
        }
    }
}
