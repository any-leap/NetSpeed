import AppKit
import IOKit

/// A short-lived privileged watchdog owns the global setting for this session.
/// No password is stored and no permanent privileged helper/sudoers rule is installed.
final class LidSleepMonitor {
    enum Phase { case idle, authorizing, active, stopping, recovering }
    private(set) var phase: Phase = .idle
    private(set) var systemSleepDisabled: Bool?
    var onUpdate: (() -> Void)?
    var onError: ((String) -> Void)?
    private var process: Process?
    private var marker: URL?
    private var token: String?
    private var timer: Timer?
    private var terminationObserver: NSObjectProtocol?
    private let paths = LidSleepSessionScript.Paths()

    var recoveryNeeded: Bool {
        phase == .idle && (systemSleepDisabled == true || FileManager.default.fileExists(atPath: paths.lock))
    }

    init() {
        update()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.update() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.stop() }
    }

    static func readSystemSleepDisabled() -> Bool? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        return IORegistryEntryCreateCFProperty(service, "SleepDisabled" as CFString,
                                               kCFAllocatorDefault, 0)?.takeRetainedValue() as? Bool
    }

    func update() {
        systemSleepDisabled = Self.readSystemSleepDisabled()
        if phase == .authorizing, let token,
           FileManager.default.fileExists(atPath: paths.lock + "/" + token),
           systemSleepDisabled == true {
            phase = .active
        }
        onUpdate?()
    }

    func start() {
        update()
        guard phase == .idle, systemSleepDisabled == false, !recoveryNeeded else { return }
        let token = UUID().uuidString
        let marker = FileManager.default.temporaryDirectory.appendingPathComponent("netspeed-lid-" + token)
        do {
            try Data().write(to: marker, options: .withoutOverwriting)
            self.marker = marker
            self.token = token
            phase = .authorizing
            run(LidSleepSessionScript.watchdog(marker: marker.path, token: token,
                                               pid: getpid(), uid: getuid()))
        } catch { onError?(error.localizedDescription) }
        onUpdate?()
    }

    func stop() {
        guard phase == .active || phase == .authorizing else { return }
        // Do not kill osascript: the root watcher must finish and verify restoration.
        if let marker {
            do { try FileManager.default.removeItem(at: marker) }
            catch { onError?(error.localizedDescription); return }
            self.marker = nil
        }
        phase = .stopping
        onUpdate?()
    }

    func recover() {
        guard phase == .idle else { return }
        phase = .recovering
        run(LidSleepSessionScript.recovery())
        onUpdate?()
    }

    private func run(_ shell: String) {
        let process = Process()
        let errors = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", LidSleepSessionScript.appleScript(shell)]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errors
        self.process = process
        // Authorization and the session can last hours; keep them off the main thread.
        DispatchQueue.global(qos: .utility).async { [weak self] in
            var launchError: String?
            do { try process.run() } catch { launchError = error.localizedDescription }
            let output: String
            if launchError == nil {
                output = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                process.waitUntilExit()
            } else { output = "" }
            let failure = launchError ?? (process.terminationStatus == 0 ? nil : output)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if let marker = self.marker {
                    do { try FileManager.default.removeItem(at: marker) }
                    catch { NSLog("NetSpeed lid marker cleanup failed: %@", error.localizedDescription) }
                }
                self.marker = nil
                self.token = nil
                self.process = nil
                self.phase = .idle
                self.update()
                // macOS error -128 means the user cancelled the authorization dialog.
                if let failure, !failure.contains("(-128)") { self.onError?(failure) }
            }
        }
    }

    deinit {
        timer?.invalidate()
        if let terminationObserver { NotificationCenter.default.removeObserver(terminationObserver) }
        if let marker {
            do { try FileManager.default.removeItem(at: marker) }
            catch { NSLog("NetSpeed lid marker cleanup failed: %@", error.localizedDescription) }
        }
    }
}
