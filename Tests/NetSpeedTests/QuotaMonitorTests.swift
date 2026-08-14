import XCTest
@testable import NetSpeed

final class QuotaMonitorTests: XCTestCase {
    private func sample(updatedAt: String) -> Data {
        """
        {
          "version": 1,
          "updatedAt": "\(updatedAt)",
          "subscriptions": [
            {"name": "subA", "todayBytes": 1073741824, "usedBytes": 10737418240,
             "totalBytes": 107374182400, "remainingPct": 90.0, "resetsMonthly": true,
             "expireAt": "2027-05-21"},
            {"name": "direct", "todayBytes": 12345}
          ]
        }
        """.data(using: .utf8)!
    }

    func testParseFreshStatus() {
        let now = ISO8601DateFormatter().date(from: "2026-08-14T12:00:00Z")!
        let status = QuotaMonitor.parse(sample(updatedAt: "2026-08-14T11:59:30.123Z"), now: now)
        XCTAssertEqual(status?.subscriptions.count, 2)
        XCTAssertEqual(status?.subscriptions[0].name, "subA")
        XCTAssertEqual(status?.subscriptions[0].remainingPct, 90.0)
        // 可选字段缺失（无配额订阅）也能解析
        XCTAssertNil(status?.subscriptions[1].totalBytes)
    }

    func testStaleStatusHidden() {
        let now = ISO8601DateFormatter().date(from: "2026-08-14T12:00:00Z")!
        XCTAssertNil(QuotaMonitor.parse(sample(updatedAt: "2026-08-14T11:00:00.000Z"), now: now))
    }

    func testUnknownVersionRejected() {
        let data = #"{"version": 2, "updatedAt": "2026-08-14T12:00:00Z", "subscriptions": []}"#
            .data(using: .utf8)!
        XCTAssertNil(QuotaMonitor.parse(data, now: Date()))
    }

    func testFormatGB() {
        XCTAssertEqual(QuotaMonitor.formatGB(139_660_886_016), "130G")
        XCTAssertEqual(QuotaMonitor.formatGB(1_610_612_736), "1.5G")
        XCTAssertEqual(QuotaMonitor.formatGB(52_428_800), "50M")
    }
}
