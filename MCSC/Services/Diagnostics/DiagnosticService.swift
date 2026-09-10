import Cocoa
import OSLog

/// Protocol defining diagnostic operations.
protocol DiagnosticServiceProtocol: AnyObject {
    func start()
    func stop()
    func dumpRecentDiagnostics(to destination: URL?, timeInterval: TimeInterval) -> URL?
    func recordDiagnosticEvent(category: String, message: String)
}

extension DiagnosticServiceProtocol {
    func dumpRecentDiagnostics(to destination: URL? = nil) -> URL? {
        dumpRecentDiagnostics(to: destination, timeInterval: 600)
    }
}

/// Headless background diagnostic service adhering to Apple Unified Logging standards.
///
/// Responsibilities:
/// - Hooks uncaught exceptions and fatal signals to preserve crash context.
/// - Queries `OSLogStore` on demand or during faults to write structured `.jsonl` diagnostics.
/// - Stores reports at `~/Library/Logs/MCSC/` for automated AI agent inspection.
/// - Operates with zero memory footprint during normal execution (kernel-backed log buffer).
final class DiagnosticService: DiagnosticServiceProtocol {
    static let shared = DiagnosticService()

    private let logDirectory: URL
    private let reportURL: URL
    private let crashURL: URL
    private var isStarted = false
    private var terminateObserver: NSObjectProtocol?

    private static var previousUncaughtExceptionHandler: (@convention(c) (NSException) -> Void)?
    private static var crashLogFilePathCString: [CChar]?

    init() {
        let fileManager = FileManager.default
        let libraryLogs = fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let mcscLogs = libraryLogs.appendingPathComponent("Logs/MCSC", isDirectory: true)

        self.logDirectory = mcscLogs
        self.reportURL = mcscLogs.appendingPathComponent("diagnostic_report.jsonl")
        self.crashURL = mcscLogs.appendingPathComponent("crash.log")

        try? fileManager.createDirectory(at: mcscLogs, withIntermediateDirectories: true)

        if let cString = crashURL.path.cString(using: .utf8) {
            DiagnosticService.crashLogFilePathCString = cString
        }
    }

    /// Boots the diagnostic service: records environment details and arms exception/signal hooks.
    func start() {
        guard !isStarted else { return }
        isStarted = true

        setupCrashAndExceptionHandlers()
        setupTerminationObserver()
        logSystemEnvironment()
    }

    /// Cleans up observers and restores original exception and signal handlers.
    func stop() {
        guard isStarted else { return }
        isStarted = false

        if let terminateObserver {
            NotificationCenter.default.removeObserver(terminateObserver)
            self.terminateObserver = nil
        }

        NSSetUncaughtExceptionHandler(DiagnosticService.previousUncaughtExceptionHandler)
        DiagnosticService.previousUncaughtExceptionHandler = nil

        signal(SIGSEGV, SIG_DFL)
        signal(SIGABRT, SIG_DFL)
        signal(SIGBUS, SIG_DFL)
        signal(SIGILL, SIG_DFL)
    }

    /// Logs initial environment context (PID, OS, AX permissions) for AI auditability.
    private func logSystemEnvironment() {
        let pid = ProcessInfo.processInfo.processIdentifier
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        let isTrusted = AXIsProcessTrusted()

        AppLogger.diagnostics.info(
            "Diagnostic service started. PID: \(pid, privacy: .public), OS: \(osVersion, privacy: .public), AXTrusted: \(isTrusted, privacy: .public)"
        )
    }

    private func setupTerminationObserver() {
        terminateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            AppLogger.diagnostics.info("Application will terminate cleanly.")
            _ = self?.dumpRecentDiagnostics(to: nil)
        }
    }

    /// Installs handlers to record fatal exceptions and signals without UI interaction.
    private func setupCrashAndExceptionHandlers() {
        DiagnosticService.previousUncaughtExceptionHandler = NSGetUncaughtExceptionHandler()

        NSSetUncaughtExceptionHandler { exception in
            let symbols = exception.callStackSymbols.joined(separator: "\n")
            let reason = exception.reason ?? "Unknown reason"
            let name = exception.name.rawValue

            AppLogger.diagnostics.fault("Uncaught NSException: \(name, privacy: .public) - \(reason, privacy: .public)")

            let crashText = """
            === MCSC CRASH REPORT ===
            Date: \(ISO8601DateFormatter().string(from: Date()))
            Exception: \(name)
            Reason: \(reason)
            PID: \(ProcessInfo.processInfo.processIdentifier)
            CallStack:
            \(symbols)
            =========================
            """

            let shared = DiagnosticService.shared
            try? crashText.write(to: shared.crashURL, atomically: true, encoding: .utf8)
            _ = shared.dumpRecentDiagnostics(to: nil)

            DiagnosticService.previousUncaughtExceptionHandler?(exception)
        }

        signal(SIGSEGV) { sig in
            DiagnosticService.handleFatalSignal(sig, name: "SIGSEGV")
        }
        signal(SIGABRT) { sig in
            DiagnosticService.handleFatalSignal(sig, name: "SIGABRT")
        }
        signal(SIGBUS) { sig in
            DiagnosticService.handleFatalSignal(sig, name: "SIGBUS")
        }
        signal(SIGILL) { sig in
            DiagnosticService.handleFatalSignal(sig, name: "SIGILL")
        }
    }

    /// C-convention signal handler for critical memory/execution faults.
    /// Uses POSIX async-signal-safe primitives to avoid deadlocks in corrupt heap state.
    private static func handleFatalSignal(_ sig: Int32, name: StaticString) {
        let stderrPrefix: StaticString = "\n[FATAL] MCSC received signal "
        stderrPrefix.withUTF8Buffer { _ = write(STDERR_FILENO, $0.baseAddress, $0.count) }
        name.withUTF8Buffer { _ = write(STDERR_FILENO, $0.baseAddress, $0.count) }
        let stderrSuffix: StaticString = "\n"
        stderrSuffix.withUTF8Buffer { _ = write(STDERR_FILENO, $0.baseAddress, $0.count) }

        if let path = crashLogFilePathCString {
            let fd = open(path, O_WRONLY | O_CREAT | O_APPEND, 0o644)
            if fd >= 0 {
                let header: StaticString = "\n=== MCSC FATAL SIGNAL ===\nSignal: "
                header.withUTF8Buffer { _ = write(fd, $0.baseAddress, $0.count) }
                name.withUTF8Buffer { _ = write(fd, $0.baseAddress, $0.count) }
                let footer: StaticString = "\n=========================\n"
                footer.withUTF8Buffer { _ = write(fd, $0.baseAddress, $0.count) }
                close(fd)
            }
        }

        signal(sig, SIG_DFL)
        raise(sig)
    }

    /// Query Apple `OSLogStore` for recent logs and write them to a JSONL file.
    ///
    /// - Parameters:
    ///   - destination: Optional destination URL; defaults to `~/Library/Logs/MCSC/diagnostic_report.jsonl`.
    ///   - timeInterval: Number of seconds of past history to query (default: 600s / 10min).
    /// - Returns: Destination file URL if successful, nil otherwise.
    @discardableResult
    func dumpRecentDiagnostics(to destination: URL? = nil, timeInterval: TimeInterval = 600) -> URL? {
        let target = destination ?? reportURL

        do {
            let store = try OSLogStore(scope: .currentProcessIdentifier)
            let date = Date().addingTimeInterval(-timeInterval)
            let position = store.position(date: date)
            let entries = try store.getEntries(with: [], at: position, matching: nil)

            var jsonLines: [String] = []
            let isoFormatter = ISO8601DateFormatter()

            for entry in entries {
                guard let log = entry as? OSLogEntryLog else { continue }
                guard log.subsystem == AppLogger.subsystem else { continue }

                let record: [String: Any] = [
                    "timestamp": isoFormatter.string(from: log.date),
                    "subsystem": log.subsystem,
                    "category": log.category,
                    "level": logLevelString(log.level),
                    "message": log.composedMessage
                ]

                if let jsonData = try? JSONSerialization.data(withJSONObject: record, options: []),
                   let line = String(data: jsonData, encoding: .utf8) {
                    jsonLines.append(line)
                }
            }

            let output = jsonLines.joined(separator: "\n") + "\n"
            try output.write(to: target, atomically: true, encoding: .utf8)
            return target
        } catch {
            AppLogger.diagnostics.error(
                "Failed to dump OSLogStore diagnostics: \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
    }

    /// Helper to record explicit diagnostic events from services.
    func recordDiagnosticEvent(category: String, message: String) {
        AppLogger.diagnostics.info("[\(category, privacy: .public)] \(message, privacy: .public)")
    }

    private func logLevelString(_ level: OSLogEntryLog.Level) -> String {
        switch level {
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .notice: return "NOTICE"
        case .error: return "ERROR"
        case .fault: return "FAULT"
        case .undefined: return "UNDEFINED"
        @unknown default: return "UNKNOWN"
        }
    }

    deinit {
        stop()
    }
}
