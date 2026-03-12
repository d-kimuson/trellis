import Foundation

// MARK: - File-based debug logger
//
// Active only when compiled with -D DEBUG_LOGGING (via `make debug`).
// Log file: ~/Library/Logs/Trellis/debug-YYYY-MM-DD-HH-mm-ss.log
//
// Usage:
//   debugLog("[KEY] keyCode=\(code) text=\(text)")
//   debugLog("[OSC] desktop notification title=\(title)")

#if DEBUG_LOGGING
private let _debugLogQueue = DispatchQueue(label: "trellis.debuglogger", qos: .utility)

private let _debugLogFile: FileHandle? = {
    let logsDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/Trellis")
    try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
    let name = "debug-\(formatter.string(from: Date())).log"
    let url = logsDir.appendingPathComponent(name)
    FileManager.default.createFile(atPath: url.path, contents: nil)
    guard let handle = try? FileHandle(forWritingTo: url) else { return nil }
    // Print log path to stderr so it appears when running from terminal
    fputs("[Trellis] Debug log: \(url.path)\n", stderr)
    return handle
}()

private let _debugDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "HH:mm:ss.SSS"
    return f
}()
#endif

/// Write a debug log line. No-op in non-debug builds (zero overhead via #if).
@inline(__always)
public func debugLog(
    _ message: @autoclosure () -> String,
    file: String = #file,
    line: Int = #line
) {
    #if DEBUG_LOGGING
    let msg = message()
    let fname = (file as NSString).lastPathComponent
    let lineNum = line
    _debugLogQueue.async {
        let ts = _debugDateFormatter.string(from: Date())
        let entry = "[\(ts)] [\(fname):\(lineNum)] \(msg)\n"
        _debugLogFile?.write(Data(entry.utf8))
    }
    #endif
}
