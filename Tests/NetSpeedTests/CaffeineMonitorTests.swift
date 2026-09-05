import XCTest
import IOKit.pwr_mgt
@testable import NetSpeed

final class CaffeineMonitorTests: XCTestCase {
    func testToggleLeavesOtherOwnersAssertionIntact() throws {
        var external: IOPMAssertionID = 0
        XCTAssertEqual(IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "NetSpeed test external owner" as CFString, &external), kIOReturnSuccess)
        defer { IOPMAssertionRelease(external) }
        let monitor = CaffeineMonitor()
        defer { monitor.setEnabled(false) }
        monitor.update()
        XCTAssertEqual(monitor.systemIsAwake, true)
        XCTAssertFalse(monitor.isEnabled)
        XCTAssertEqual(monitor.setEnabled(true), kIOReturnSuccess)
        XCTAssertTrue(monitor.isEnabled)
        XCTAssertEqual(monitor.setEnabled(true), kIOReturnSuccess)
        XCTAssertEqual(monitor.setEnabled(false), kIOReturnSuccess)
        XCTAssertFalse(monitor.isEnabled)
        XCTAssertEqual(monitor.systemIsAwake, true)
        XCTAssertNotNil(IOPMAssertionCopyProperties(external)?.takeRetainedValue())
    }
}
