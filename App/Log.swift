import Foundation

// A simple log file in Documents (visible in the Files app) so problems
// on the phone can be reported without a Mac.
enum Log {
    static let url: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("HungryPumpkin-log.txt")
    }()

    private static let queue = DispatchQueue(label: "log")

    static func write(_ msg: String) {
        let line = "\(Date()) \(msg)\n"
        queue.sync {
            if let h = try? FileHandle(forWritingTo: url) {
                h.seekToEndOfFile()
                h.write(line.data(using: .utf8)!)
                try? h.close()
            } else {
                try? line.data(using: .utf8)!.write(to: url)
            }
        }
    }
}

enum CrashReporter {
    static func install() {
        NSSetUncaughtExceptionHandler { e in
            let stack = e.callStackSymbols.joined(separator: "\n")
            Log.write("CRASH exception \(e.name.rawValue): \(e.reason ?? "")\n\(stack)")
        }
        for sig in [SIGABRT, SIGSEGV, SIGBUS, SIGILL, SIGFPE, SIGTRAP] {
            signal(sig) { s in
                let stack = Thread.callStackSymbols.joined(separator: "\n")
                Log.write("CRASH signal \(s)\n\(stack)")
                signal(s, SIG_DFL)
                raise(s)
            }
        }
    }
}
