import Foundation

/// 诊断日志：App 和小组件扩展都往 App Group 里的同一个文件追加事件，
/// 在「我的 › 诊断信息」里可以看到系统到底有没有调用控制中心按钮、动作有没有执行。
enum DiagLog {
    private static let maxLines = 300

    static var processName: String {
        Bundle.main.bundleURL.pathExtension == "appex" ? "扩展" : "App"
    }

    static var fileURL: URL {
        let dir = AppGroup.containerURL.appendingPathComponent("Pupudiary", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("diagnostics.log")
    }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MM-dd HH:mm:ss"
        return f
    }()

    static func log(_ event: String) {
        let line = "\(formatter.string(from: Date())) [\(processName)] \(event)"
        var coordError: NSError?
        NSFileCoordinator().coordinate(writingItemAt: fileURL, options: [], error: &coordError) { url in
            var lines = ((try? String(contentsOf: url, encoding: .utf8)) ?? "")
                .split(separator: "\n", omittingEmptySubsequences: true)
                .map(String.init)
            lines.append(line)
            if lines.count > maxLines { lines.removeFirst(lines.count - maxLines) }
            try? (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
        }
    }

    static func read() -> [String] {
        let text = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
        return text.split(separator: "\n").map(String.init)
    }

    static func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    /// 本进程看到的签名 / App Group 情况，扩展启动时写一条
    static var environmentSummary: String {
        let bid = Bundle.main.bundleIdentifier ?? "?"
        return "bundle=\(bid) group=\(AppGroup.identifier) shared=\(AppGroup.isShared)"
    }
}

/// 扩展崩溃时往诊断日志里写一行（只用于排查问题）
enum CrashCatcher {
    private static var path: UnsafeMutablePointer<CChar>?
    private static var messages = [UnsafeMutablePointer<CChar>?](repeating: nil, count: 32)
    private static var installed = false

    static func install() {
        guard !installed else { return }
        installed = true
        path = strdup(DiagLog.fileURL.path)
        let process = DiagLog.processName
        let signals: [Int32] = [SIGABRT, SIGTRAP, SIGSEGV, SIGBUS, SIGILL, SIGFPE]
        for s in signals {
            messages[Int(s)] = strdup("--:-- [\(process)] ‼️ 崩溃 signal=\(s)\n")
            signal(s) { sig in
                if let p = CrashCatcher.path, let m = CrashCatcher.messages[Int(sig)] {
                    let fd = open(p, O_WRONLY | O_APPEND | O_CREAT, 0o644)
                    if fd >= 0 {
                        _ = write(fd, m, strlen(m))
                        close(fd)
                    }
                }
                signal(sig, SIG_DFL)
                raise(sig)
            }
        }
        NSSetUncaughtExceptionHandler { e in
            DiagLog.log("‼️ 异常 \(e.name.rawValue): \(e.reason ?? "")")
        }
    }
}
