import XCTest
import Foundation
import Darwin
@testable import NetSpeed

/// Executes the actual generated watchdog, substituting only pmset and its private
/// lock directory. No administrator prompt or real power-setting write is involved.
final class LidSleepSessionScriptTests: XCTestCase {
    func testElevatedScriptsCompileWithoutExecuting() {
        let shell = LidSleepSessionScript.watchdog(marker: "/tmp/NetSpeed shell's marker", token: "test-token", pid: getpid(), uid: getuid())
        for source in [shell, LidSleepSessionScript.recovery()] {
            let script = NSAppleScript(source: LidSleepSessionScript.appleScript(source))
            var error: NSDictionary?
            XCTAssertNotNil(script)
            XCTAssertEqual(script?.compileAndReturnError(&error), true, "\(String(describing: error))")
        }
    }

    private final class Session {
        let directory: URL
        let marker: URL
        let lock: URL
        let state: URL
        let commands: URL
        let battery: URL
        let failedRestore: URL
        var paths: LidSleepSessionScript.Paths
        var processes: [Process] = []

        init(initialState: String = "0", batteryLevel: String = "AC") throws {
            directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("NetSpeed shell's test \(UUID().uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            marker = directory.appendingPathComponent("enabled marker")
            lock = directory.appendingPathComponent("session lock")
            state = directory.appendingPathComponent("state")
            commands = directory.appendingPathComponent("commands")
            battery = directory.appendingPathComponent("battery")
            failedRestore = directory.appendingPathComponent("fail-restore")
            let executable = directory.appendingPathComponent("fake pmset")
            paths = LidSleepSessionScript.Paths()
            paths.pmset = executable.path
            paths.lock = lock.path
            paths.interval = "0.05"
            paths.duration = 10
            try write(initialState, to: state)
            try write(batteryLevel, to: battery)
            try write("", to: marker)
            let script = """
            #!/bin/sh
            directory=\(LidSleepSessionScript.quote(directory.path))
            if [ "$1" = -g ]; then
                if [ "$2" = batt ]; then
                    value=$(/bin/cat "$directory/battery")
                    if [ "$value" = AC ]; then echo "Now drawing from 'AC Power'";
                    else echo "Now drawing from 'Battery Power'"; echo " -InternalBattery-0 $value%; discharging;"; fi
                else echo "SleepDisabled $(/bin/cat "$directory/state")"; fi
                exit 0
            fi
            [ "$1" = -a ] && [ "$2" = disablesleep ] || exit 90
            if [ "$3" = 0 ] && [ -f "$directory/pause-restore" ]; then
                /usr/bin/touch "$directory/restore-entered"
                while [ -f "$directory/pause-restore" ]; do /bin/sleep 0.02; done
            fi
            echo "$3" >> "$directory/commands"
            if [ "$3" = 0 ] && [ -f "$directory/fail-restore" ]; then exit 1; fi
            echo "$3" > "$directory/state"
            """
            try write(script, to: executable)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        }

        deinit {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent("pause-restore"))
            for process in processes where process.isRunning {
                process.terminate()
                let deadline = Date().addingTimeInterval(1)
                while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                process.waitUntilExit()
            }
            try? FileManager.default.removeItem(at: directory)
        }

        func write(_ value: String, to file: URL) throws {
            try value.write(to: file, atomically: true, encoding: .utf8)
        }

        func read(_ file: URL) -> String {
            (try? String(contentsOf: file, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }

        func run(_ script: String) throws -> Process {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", script]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            processes.append(process)
            return process
        }

        func start(owner: Int32 = ProcessInfo.processInfo.processIdentifier) throws -> Process {
            try run(LidSleepSessionScript.watchdog(marker: marker.path, token: "test-token",
                                                  pid: owner, uid: getuid(), paths: paths))
        }

        func stop() throws { try FileManager.default.removeItem(at: marker) }

        func awaitCondition(timeout: TimeInterval = 5, _ condition: () -> Bool) -> Bool {
            let deadline = Date().addingTimeInterval(timeout)
            while Date() < deadline {
                if condition() { return true }
                Thread.sleep(forTimeInterval: 0.025)
            }
            return condition()
        }

        func wait(_ process: Process, timeout: TimeInterval = 5,
                  file: StaticString = #filePath, line: UInt = #line) {
            XCTAssertTrue(awaitCondition(timeout: timeout) { !process.isRunning },
                          "Generated script did not exit before deadline", file: file, line: line)
        }

        var isReady: Bool { FileManager.default.fileExists(atPath: lock.appendingPathComponent("test-token").path) }
        var lockExists: Bool { FileManager.default.fileExists(atPath: lock.path) }
    }

    func testStartAndStopRestoresSleepAndRemovesLock() throws {
        let session = try Session()
        let process = try session.start()
        XCTAssertTrue(session.awaitCondition { session.isReady })
        XCTAssertEqual(session.read(session.state), "1")
        try session.stop()
        session.wait(process)
        XCTAssertEqual(process.terminationStatus, 0)
        XCTAssertEqual(session.read(session.commands), "1\n0")
        XCTAssertEqual(session.read(session.state), "0")
        XCTAssertFalse(session.lockExists)
    }

    func testAlreadyDisabledSettingIsNeverReset() throws {
        let session = try Session(initialState: "1")
        let process = try session.start()
        session.wait(process)
        XCTAssertEqual(process.terminationStatus, 65)
        XCTAssertEqual(session.read(session.state), "1")
        XCTAssertEqual(session.read(session.commands), "")
        XCTAssertFalse(session.lockExists)
    }

    func testMissingMarkerDoesNotChangePowerSettings() throws {
        let session = try Session()
        try session.stop()
        let process = try session.start()
        session.wait(process)
        XCTAssertEqual(session.read(session.commands), "")
        XCTAssertFalse(session.lockExists)
    }

    func testOwnerDeathRestoresSleep() throws {
        let session = try Session()
        let owner = try session.run("exec /bin/sleep 30")
        let watcher = try session.start(owner: owner.processIdentifier)
        XCTAssertTrue(session.awaitCondition { session.isReady })
        owner.terminate()
        session.wait(owner)
        session.wait(watcher)
        XCTAssertEqual(session.read(session.state), "0")
        XCTAssertFalse(session.lockExists)
    }

    func testHardTimeoutRestoresSleepEvenWithLiveOwnerAndMarker() throws {
        let session = try Session()
        session.paths.duration = 1
        let process = try session.start()
        session.wait(process)
        XCTAssertEqual(session.read(session.commands), "1\n0")
        XCTAssertEqual(session.read(session.state), "0")
        XCTAssertFalse(session.lockExists)
    }

    func testLowBatteryRefusesToStart() throws {
        let session = try Session(batteryLevel: "20")
        let process = try session.start()
        session.wait(process)
        XCTAssertEqual(process.terminationStatus, 65)
        XCTAssertEqual(session.read(session.commands), "")
        XCTAssertFalse(session.lockExists)
    }

    func testBatteryDroppingToThresholdRestoresSleep() throws {
        let session = try Session(batteryLevel: "75")
        let process = try session.start()
        XCTAssertTrue(session.awaitCondition { session.isReady })
        try session.write("20", to: session.battery)
        session.wait(process)
        XCTAssertEqual(session.read(session.state), "0")
        XCTAssertFalse(session.lockExists)
    }

    func testFailedRestorePreservesLockUntilExplicitRecovery() throws {
        let session = try Session()
        let process = try session.start()
        XCTAssertTrue(session.awaitCondition { session.isReady })
        try session.write("", to: session.failedRestore)
        try session.stop()
        session.wait(process, timeout: 7)
        XCTAssertEqual(process.terminationStatus, 74)
        XCTAssertEqual(session.read(session.state), "1")
        XCTAssertEqual(session.read(session.commands), "1\n0\n0\n0")
        XCTAssertTrue(session.lockExists)
        try FileManager.default.removeItem(at: session.failedRestore)
        let recovery = try session.run(LidSleepSessionScript.recovery(paths: session.paths))
        session.wait(recovery)
        XCTAssertEqual(recovery.terminationStatus, 0)
        XCTAssertEqual(session.read(session.state), "0")
        XCTAssertFalse(session.lockExists)
    }

    func testRecoveryRefusesLiveWatchdog() throws {
        let session = try Session()
        let watcher = try session.start()
        XCTAssertTrue(session.awaitCondition { session.isReady })
        let recovery = try session.run(LidSleepSessionScript.recovery(paths: session.paths))
        session.wait(recovery)
        XCTAssertEqual(recovery.terminationStatus, 73)
        XCTAssertEqual(session.read(session.state), "1")
        try session.stop()
        session.wait(watcher)
        XCTAssertEqual(session.read(session.state), "0")
    }

    func testTerminationSignalRestoresSleep() throws {
        let session = try Session()
        let watcher = try session.start()
        XCTAssertTrue(session.awaitCondition { session.isReady })
        watcher.terminate()
        session.wait(watcher)
        XCTAssertEqual(session.read(session.state), "0")
        XCTAssertFalse(session.lockExists)
    }

    func testRecoveryExcludesConcurrentRecoveryAndStartThenReleasesGuard() throws {
        let session = try Session()
        let pause = session.directory.appendingPathComponent("pause-restore")
        let entered = session.directory.appendingPathComponent("restore-entered")
        try session.write("", to: pause)
        let firstRecovery = try session.run(LidSleepSessionScript.recovery(paths: session.paths))
        XCTAssertTrue(session.awaitCondition { FileManager.default.fileExists(atPath: entered.path) })

        let competingRecovery = try session.run(LidSleepSessionScript.recovery(paths: session.paths))
        let competingStart = try session.start()
        session.wait(competingRecovery)
        session.wait(competingStart)
        XCTAssertEqual(competingRecovery.terminationStatus, 73)
        XCTAssertEqual(competingStart.terminationStatus, 73)
        XCTAssertFalse(session.lockExists)
        XCTAssertEqual(session.read(session.commands), "")

        try FileManager.default.removeItem(at: pause)
        session.wait(firstRecovery)
        XCTAssertEqual(firstRecovery.terminationStatus, 0)
        let newSession = try session.start()
        XCTAssertTrue(session.awaitCondition { session.isReady })
        let lateRecovery = try session.run(LidSleepSessionScript.recovery(paths: session.paths))
        session.wait(lateRecovery)
        XCTAssertEqual(lateRecovery.terminationStatus, 73)
        XCTAssertEqual(session.read(session.state), "1")
        XCTAssertTrue(session.isReady)
        XCTAssertEqual(session.read(session.commands), "0\n1")
        try session.stop()
        session.wait(newSession)
        XCTAssertEqual(session.read(session.commands), "0\n1\n0")
        XCTAssertFalse(session.lockExists)
    }

    func testIncompleteStaleLockCanBeRecoveredUnderExclusiveGuard() throws {
        let session = try Session(initialState: "1")
        try FileManager.default.createDirectory(at: session.lock, withIntermediateDirectories: false)
        let recovery = try session.run(LidSleepSessionScript.recovery(paths: session.paths))
        session.wait(recovery)
        XCTAssertEqual(recovery.terminationStatus, 0)
        XCTAssertEqual(session.read(session.state), "0")
        XCTAssertFalse(session.lockExists)
    }

}
