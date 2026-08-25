import Foundation

final class RobloxTrafficFinder {
    static let `default` = RobloxTrafficFinder()

    private let processNames = ["RobloxPlayer", "Roblox"]

    /// Returns the unique remote IP addresses currently used by Roblox processes.
    /// The IP strings are in a format the setuid helper can parse (inet_pton).
    func findRemoteIPs(timeout: TimeInterval = 5.0, completion: @escaping ([String], String) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let (pids, pidError) = self.findPIDs()
            guard !pids.isEmpty else {
                completion([], pidError.isEmpty ? "Roblox is not running." : pidError)
                return
            }

            var ips = Set<String>()
            for pid in pids {
                let (lines, err) = self.runLsof(pid: pid)
                if !err.isEmpty {
                    DispatchQueue.main.async {
                        completion([], err)
                    }
                    return
                }
                for ip in self.parseRemoteIPs(lines: lines) {
                    ips.insert(ip)
                }
            }

            DispatchQueue.main.async {
                if ips.isEmpty {
                    completion([], "Roblox is running but has no active network connections.")
                } else {
                    completion(Array(ips), "")
                }
            }
        }
    }

    // MARK: - Process discovery

    private func findPIDs() -> ([Int], String) {
        var pids = Set<Int>()

        for name in processNames {
            let (output, err) = runAndRead(["/usr/bin/pgrep", "-i", "-x", name])
            if !err.isEmpty {
                return ([], err)
            }
            for line in output.components(separatedBy: .newlines) {
                if let pid = Int(line.trimmingCharacters(in: .whitespacesAndNewlines)), pid > 0 {
                    pids.insert(pid)
                }
            }
        }

        // Fallback: accept any process whose command line contains the app bundle.
        if pids.isEmpty {
            let (output, err) = runAndRead(["/usr/bin/pgrep", "-i", "-f", "Roblox.app"])
            if !err.isEmpty {
                return ([], err)
            }
            for line in output.components(separatedBy: .newlines) {
                if let pid = Int(line.trimmingCharacters(in: .whitespacesAndNewlines)), pid > 0 {
                    pids.insert(pid)
                }
            }
        }

        return (Array(pids), "")
    }

    // MARK: - lsof

    private func runLsof(pid: Int) -> ([String], String) {
        return runAndReadLines(["/usr/sbin/lsof", "-a", "-p", "\(pid)", "-i", "-n", "-P", "-Fpcn"])
    }

    // MARK: - Parsing

    private func parseRemoteIPs(lines: [String]) -> [String] {
        var ips = [String]()

        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.hasPrefix("n") else { continue }

            let name = String(line.dropFirst())
            guard let remotePart = name.components(separatedBy: "->").last else { continue }
            guard remotePart != "*" && !remotePart.hasPrefix("*:") else { continue }

            let remote = remotePart.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let ip = extractIP(remote) else { continue }

            if isRoutableIP(ip) {
                ips.append(ip)
            }
        }

        return ips
    }

    /// Convert "128.116.51.3:443" or "[fe80::...]:1024" to a bare IP.
    private func extractIP(_ address: String) -> String? {
        if address.hasPrefix("[") {
            // IPv6: [addr]:port
            guard let bracketEnd = address.firstIndex(of: "]") else { return nil }
            var ip = String(address[address.index(after: address.startIndex)..<bracketEnd])
            // Drop scope (e.g. %en0)
            if let percent = ip.firstIndex(of: "%") {
                ip = String(ip[ip.startIndex..<percent])
            }
            return ip.isEmpty ? nil : ip
        } else {
            // IPv4: a.b.c.d:port, possibly a.b.c.d:port (status)
            // Strip any trailing status in parentheses.
            var s = address
            if let paren = s.firstIndex(of: "(") {
                s = String(s[s.startIndex..<paren])
            }
            // The port is the last colon-delimited field.
            let parts = s.split(separator: ":", omittingEmptySubsequences: false)
            if parts.count < 2 { return nil }
            let ipParts = parts.dropLast()
            let ip = ipParts.joined(separator: ":")
            return ip.isEmpty ? nil : ip
        }
    }

    /// Exclude loopback, link-local, multicast, and wildcard addresses.
    /// Note: 10.x/172.16-31/192.168 can still be a valid remote game server
    /// over a VPN or local network, so we keep those.
    private func isRoutableIP(_ ip: String) -> Bool {
        if ip == "*" || ip.isEmpty { return false }

        // IPv4 loopback / multicast / link-local
        if let _ = IPv4Pattern.firstMatch(in: ip, range: NSRange(ip.startIndex..., in: ip)) {
            return false
        }

        // IPv6 loopback / link-local / multicast
        if ip == "::1" || ip == "0:0:0:0:0:0:0:1" { return false }
        if ip.lowercased().hasPrefix("fe80:") || ip.lowercased().hasPrefix("ff") { return false }

        return true
    }

    private lazy var IPv4Pattern: NSRegularExpression = {
        // 127.*, 0.0.0.0, 169.254.*, 224-239.*
        let pattern = "^(127\\.|0\\.0\\.0\\.0$|169\\.254\\.|22[4-9]\\.|23[0-9]\\.)"
        return try! NSRegularExpression(pattern: pattern)
    }()

    // MARK: - Process runner

    private func runAndReadLines(_ args: [String]) -> ([String], String) {
        let (output, err) = runAndRead(args)
        return (output.components(separatedBy: .newlines), err)
    }

    private func runAndRead(_ args: [String]) -> (String, String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: args[0])
        process.arguments = Array(args.dropFirst())

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
            process.waitUntilExit()

            let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: outData, encoding: .utf8) ?? ""
            let error = String(data: errData, encoding: .utf8) ?? ""

            if process.terminationStatus != 0 && !error.isEmpty {
                return (output, error)
            }
            return (output, error)
        } catch {
            return ("", error.localizedDescription)
        }
    }
}
