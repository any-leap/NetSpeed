import XCTest
@testable import NetSpeed

final class PreferencesTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var prefs: Preferences!

    override func setUp() {
        suiteName = "PreferencesTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        prefs = Preferences(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testDefaultsMatchFormerHardcodedValues() {
        XCTAssertEqual(prefs.cpuThreshold, 50)
        XCTAssertEqual(prefs.sustainedSeconds, 30)
        XCTAssertEqual(prefs.watchedProcesses, ["bird"])
        XCTAssertTrue(prefs.ignoredProcesses.contains("WindowServer"))
        XCTAssertEqual(prefs.latencyTargetsCN.count, 3)
        XCTAssertEqual(prefs.latencyTargetsIntl.first, "https://www.gstatic.com/generate_204")
        XCTAssertNil(prefs.openVPNConfigPath)
    }

    func testValuesPersistAcrossInstances() {
        prefs.cpuThreshold = 80
        prefs.watchedProcesses = ["bird", "sshd"]
        let again = Preferences(defaults: defaults)
        XCTAssertEqual(again.cpuThreshold, 80)
        XCTAssertEqual(again.watchedProcesses, ["bird", "sshd"])
    }

    func testThresholdAndSustainedAreClamped() {
        prefs.cpuThreshold = 1
        XCTAssertEqual(prefs.cpuThreshold, 10)
        prefs.cpuThreshold = 9999
        XCTAssertEqual(prefs.cpuThreshold, 400)
        // 采样间隔 10 秒，小于 10 会在第一次采样就告警
        prefs.sustainedSeconds = 3
        XCTAssertEqual(prefs.sustainedSeconds, 10)
        prefs.sustainedSeconds = 44
        XCTAssertEqual(prefs.sustainedSeconds, 40)
    }

    func testParseListSplitsTrimsAndDedupes() {
        XCTAssertEqual(Preferences.parseList(" a\n\nb , a\nc "), ["a", "b", "c"])
        XCTAssertEqual(Preferences.parseList("  \n "), [])
    }

    func testEmptyWatchedListIsAllowed() {
        prefs.watchedProcesses = []
        XCTAssertEqual(prefs.watchedProcesses, [])
    }

    func testLatencyTargetsRejectNonHTTPSAndEmpty() {
        let before = prefs.latencyTargetsCN
        prefs.latencyTargetsCN = ["http://example.com"]
        XCTAssertEqual(prefs.latencyTargetsCN, before)
        prefs.latencyTargetsCN = []
        XCTAssertEqual(prefs.latencyTargetsCN, before)
        prefs.latencyTargetsCN = ["https://example.com/x", "https://example.com/x"]
        XCTAssertEqual(prefs.latencyTargetsCN, ["https://example.com/x"])
        XCTAssertEqual(Preferences.invalidLatencyTargets(["https://ok.com", "ftp://x", "nonsense"]),
                       ["ftp://x", "nonsense"])
    }

    func testCorruptStoredTargetsFallBackToDefaults() {
        defaults.set(["not a url"], forKey: Preferences.Key.latencyTargetsIntl)
        XCTAssertEqual(prefs.latencyTargetsIntl, Preferences.defaultLatencyTargetsIntl)
    }

    func testResetKeepsOpenVPNPaths() {
        prefs.cpuThreshold = 90
        prefs.openVPNConfigPath = "/tmp/a.ovpn"
        prefs.resetMonitoringDefaults()
        XCTAssertEqual(prefs.cpuThreshold, 50)
        XCTAssertEqual(prefs.openVPNConfigPath, "/tmp/a.ovpn")
        prefs.openVPNConfigPath = nil
        XCTAssertNil(defaults.object(forKey: Preferences.Key.openVPNConfigPath))
    }

    func testWritesPostChangeNotification() {
        let exp = expectation(forNotification: Preferences.didChange, object: prefs)
        prefs.watchedProcesses = ["x"]
        wait(for: [exp], timeout: 1)
    }
}
