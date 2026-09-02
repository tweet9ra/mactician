import Foundation

/// Repairs a Chromium compositor artifact in Riot's login WebView.
///
/// The login page leaves its two field wrappers in finished, fill-forwards CSS
/// animations. With the guest ANGLE renderer those finished animation layers
/// can disappear even though the DOM remains visible and interactive. This
/// service connects to the app's local WebView DevTools socket and removes only
/// those two presentation animations. It never focuses a field, opens the
/// keyboard, or reads/writes form values.
final class RiotLoginAnimationRepairService {
    private static let loginActivity = "com.riotgames.platformui.mobilefre.MobileFREWebViewActivity"
    private static let adbServerPort = "5038"

    private let queue = DispatchQueue(label: "dev.sergeinaumov.mactician.riot-login-animation-repair")
    private let generationLock = NSLock()
    private var generation = 0

    func start(
        adb: URL,
        package: String,
        serial: String = "emulator-5582",
        log: URL
    ) {
        let token = nextGeneration()
        queue.async { [weak self] in
            self?.watch(
                adb: adb,
                package: package,
                serial: serial,
                log: log,
                generation: token
            )
        }
    }

    func stop() {
        _ = nextGeneration()
    }

    private func watch(
        adb: URL,
        package: String,
        serial: String,
        log: URL,
        generation token: Int
    ) {
        var repairedPID: Int?
        var lastFailureLog = Date.distantPast

        while isCurrent(token) {
            autoreleasepool {
                guard deviceIsReady(adb: adb, serial: serial),
                      loginIsTopActivity(adb: adb, package: package, serial: serial) else {
                    repairedPID = nil
                    return
                }

                guard let pid = applicationPID(adb: adb, package: package, serial: serial) else {
                    return
                }
                guard repairedPID != pid else { return }

                do {
                    let result = try repair(adb: adb, serial: serial, pid: pid)
                    guard result.fields == 2, result.wrappers == 2, result.remainingAnimations == 0 else {
                        throw RepairError.incomplete(
                            "fields=\(result.fields), wrappers=\(result.wrappers), animations=\(result.remainingAnimations)"
                        )
                    }
                    repairedPID = pid
                    SystemServices.appendLog(
                        "Riot login WebView: removed finished field animations; focus, keyboard, and form data were unchanged.",
                        to: log
                    )
                } catch {
                    // The activity becomes top-resumed before Chromium exposes
                    // its page and DevTools socket. Retry quietly during that
                    // normal startup window, but leave a bounded diagnostic.
                    if Date().timeIntervalSince(lastFailureLog) >= 10 {
                        SystemServices.appendLog(
                            "Riot login WebView repair is waiting for Chromium: \(error.localizedDescription)",
                            to: log
                        )
                        lastFailureLog = Date()
                    }
                }
            }
            Thread.sleep(forTimeInterval: 0.4)
        }
    }

    private func deviceIsReady(adb: URL, serial: String) -> Bool {
        guard let state = try? runADB(adb, serial: serial, arguments: ["get-state"]) else { return false }
        return state.trimmingCharacters(in: .whitespacesAndNewlines) == "device"
    }

    private func loginIsTopActivity(adb: URL, package: String, serial: String) -> Bool {
        guard let activities = try? runADB(
            adb,
            serial: serial,
            arguments: ["shell", "dumpsys", "activity", "activities"]
        ) else { return false }
        guard let topLine = activities.split(separator: "\n").first(where: {
            $0.contains("topResumedActivity=ActivityRecord")
        }) else { return false }
        return topLine.contains("\(package)/\(Self.loginActivity)")
    }

    private func applicationPID(adb: URL, package: String, serial: String) -> Int? {
        guard let output = try? runADB(
            adb,
            serial: serial,
            arguments: ["shell", "pidof", package]
        ) else { return nil }
        return output.split(whereSeparator: { $0.isWhitespace }).compactMap { Int($0) }.first
    }

    private func repair(adb: URL, serial: String, pid: Int) throws -> RepairResult {
        let socket = "localabstract:webview_devtools_remote_\(pid)"
        let output = try runADB(
            adb,
            serial: serial,
            arguments: ["forward", "tcp:0", socket]
        )
        guard let port = Int(output.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw RepairError.invalidForward(output)
        }
        defer {
            _ = try? runADB(
                adb,
                serial: serial,
                arguments: ["forward", "--remove", "tcp:\(port)"]
            )
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.connectionProxyDictionary = [:]
        configuration.timeoutIntervalForRequest = 3
        configuration.timeoutIntervalForResource = 4
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        let target = try webViewTarget(port: port, session: session)
        let connection = CDPConnection(url: target, session: session)
        defer { connection.close() }
        try connection.connect()
        _ = try connection.call(method: "Runtime.enable")
        let response = try connection.call(
            method: "Runtime.evaluate",
            parameters: [
                "expression": Self.repairExpression,
                "returnByValue": true,
                "awaitPromise": true
            ]
        )
        return try RepairResult(response: response)
    }

    private func webViewTarget(port: Int, session: URLSession) throws -> URL {
        guard let url = URL(string: "http://127.0.0.1:\(port)/json/list") else {
            throw RepairError.invalidForward("tcp:\(port)")
        }
        let data = try session.synchronousData(from: url, timeout: 4)
        let targets = try JSONDecoder().decode([DevToolsTarget].self, from: data)
        let target = targets.first(where: { $0.type == "page" && $0.webSocketDebuggerUrl != nil })
            ?? targets.first(where: { $0.webSocketDebuggerUrl != nil })
        guard let rawURL = target?.webSocketDebuggerUrl, let socketURL = URL(string: rawURL) else {
            throw RepairError.missingTarget
        }
        return socketURL
    }

    private func runADB(_ adb: URL, serial: String, arguments: [String]) throws -> String {
        try SystemServices.run(
            adb,
            ["-s", serial] + arguments,
            environment: [
                "ANDROID_ADB_SERVER_PORT": Self.adbServerPort,
                "ADB_MDNS_AUTO_CONNECT": ""
            ]
        )
    }

    private func nextGeneration() -> Int {
        generationLock.lock()
        defer { generationLock.unlock() }
        generation += 1
        return generation
    }

    private func isCurrent(_ token: Int) -> Bool {
        generationLock.lock()
        defer { generationLock.unlock() }
        return generation == token
    }

    private static let repairExpression = #"""
    (() => {
      const fields = Array.from(document.querySelectorAll(
        'input[name="username"], input[name="password"]'
      ));
      const wrappers = Array.from(new Set(fields
        .map((field) => field.closest('.field__input.field__input--animate'))
        .filter(Boolean)));
      if (fields.length !== 2 || wrappers.length !== 2) {
        return { fields: fields.length, wrappers: wrappers.length, remainingAnimations: -1 };
      }

      const styleId = 'tft-stable-login-fields';
      let style = document.getElementById(styleId);
      if (!style) {
        style = document.createElement('style');
        style.id = styleId;
        style.textContent =
          '.field__input--animate {' +
          'animation: none !important;' +
          'opacity: 1 !important;' +
          'transform: none !important;' +
          '}';
        document.head.appendChild(style);
      }

      wrappers.forEach((wrapper) => {
        wrapper.getAnimations().forEach((animation) => animation.cancel());
        wrapper.style.animation = 'none';
        wrapper.style.opacity = '1';
        wrapper.style.transform = 'none';
      });
      document.documentElement.getBoundingClientRect();
      const remainingAnimations = wrappers.reduce(
        (count, wrapper) => count + wrapper.getAnimations().length,
        0
      );
      return { fields: fields.length, wrappers: wrappers.length, remainingAnimations };
    })()
    """#
}

private struct DevToolsTarget: Decodable {
    let type: String?
    let webSocketDebuggerUrl: String?
}

private struct RepairResult {
    let fields: Int
    let wrappers: Int
    let remainingAnimations: Int

    init(response: [String: Any]) throws {
        guard let result = response["result"] as? [String: Any],
              let remoteObject = result["result"] as? [String: Any],
              let value = remoteObject["value"] as? [String: Any],
              let fields = value["fields"] as? Int,
              let wrappers = value["wrappers"] as? Int,
              let remainingAnimations = value["remainingAnimations"] as? Int else {
            throw RepairError.invalidResponse
        }
        self.fields = fields
        self.wrappers = wrappers
        self.remainingAnimations = remainingAnimations
    }
}

private final class CDPConnection {
    private let task: URLSessionWebSocketTask
    private var nextID = 1

    init(url: URL, session: URLSession) {
        task = session.webSocketTask(with: url)
    }

    func connect() throws {
        task.resume()
    }

    func close() {
        task.cancel(with: .normalClosure, reason: nil)
    }

    func call(method: String, parameters: [String: Any] = [:]) throws -> [String: Any] {
        let id = nextID
        nextID += 1
        let request: [String: Any] = ["id": id, "method": method, "params": parameters]
        let data = try JSONSerialization.data(withJSONObject: request)
        guard let string = String(data: data, encoding: .utf8) else {
            throw RepairError.invalidResponse
        }
        try task.synchronousSend(.string(string), timeout: 4)

        for _ in 0 ..< 20 {
            let message = try task.synchronousReceive(timeout: 4)
            let responseData: Data
            switch message {
            case let .string(value): responseData = Data(value.utf8)
            case let .data(value): responseData = value
            @unknown default: throw RepairError.invalidResponse
            }
            guard let response = try JSONSerialization.jsonObject(with: responseData) as? [String: Any] else {
                continue
            }
            guard response["id"] as? Int == id else { continue }
            if let error = response["error"] as? [String: Any] {
                throw RepairError.protocolError(error["message"] as? String ?? "unknown CDP error")
            }
            return response
        }
        throw RepairError.timeout
    }
}

private extension URLSession {
    func synchronousData(from url: URL, timeout: TimeInterval) throws -> Data {
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<Data, Error>?
        let task = dataTask(with: url) { data, _, error in
            if let error {
                result = .failure(error)
            } else if let data {
                result = .success(data)
            } else {
                result = .failure(RepairError.invalidResponse)
            }
            semaphore.signal()
        }
        task.resume()
        guard semaphore.wait(timeout: .now() + timeout) == .success else {
            task.cancel()
            throw RepairError.timeout
        }
        return try result?.get() ?? { throw RepairError.invalidResponse }()
    }
}

private extension URLSessionWebSocketTask {
    func synchronousSend(_ message: Message, timeout: TimeInterval) throws {
        let semaphore = DispatchSemaphore(value: 0)
        var sendError: Error?
        send(message) { error in
            sendError = error
            semaphore.signal()
        }
        guard semaphore.wait(timeout: .now() + timeout) == .success else {
            throw RepairError.timeout
        }
        if let sendError { throw sendError }
    }

    func synchronousReceive(timeout: TimeInterval) throws -> Message {
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<Message, Error>?
        receive { value in
            result = value
            semaphore.signal()
        }
        guard semaphore.wait(timeout: .now() + timeout) == .success else {
            throw RepairError.timeout
        }
        return try result?.get() ?? { throw RepairError.invalidResponse }()
    }
}

private enum RepairError: LocalizedError {
    case invalidForward(String)
    case missingTarget
    case invalidResponse
    case incomplete(String)
    case protocolError(String)
    case timeout

    var errorDescription: String? {
        switch self {
        case let .invalidForward(value): return "invalid ADB forward: \(value)"
        case .missingTarget: return "WebView DevTools target is not ready"
        case .invalidResponse: return "invalid WebView DevTools response"
        case let .incomplete(value): return "login fields are not ready (\(value))"
        case let .protocolError(value): return value
        case .timeout: return "WebView DevTools request timed out"
        }
    }
}
