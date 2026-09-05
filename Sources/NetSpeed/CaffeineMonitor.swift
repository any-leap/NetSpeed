import Foundation
import IOKit.pwr_mgt

/// Own only our assertion; never terminate another app's caffeinate session.
final class CaffeineMonitor {
    private var assertionID: IOPMAssertionID?
    private(set) var systemIsAwake: Bool?
    var isEnabled: Bool { assertionID != nil }

    func update() {
        var result: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsStatus(&result) == kIOReturnSuccess,
              let levels = result?.takeRetainedValue() as? [String: NSNumber] else {
            systemIsAwake = nil
            return
        }
        systemIsAwake = [kIOPMAssertionTypePreventUserIdleSystemSleep,
                         kIOPMAssertionTypePreventSystemSleep,
                         kIOPMAssertionTypePreventUserIdleDisplaySleep]
            // Aggregate status uses 0/1, unlike the creation API's On = 255.
            .contains { (levels[$0]?.intValue ?? 0) != 0 }
    }

    /// Screen may sleep; manual sleep and lid-close retain macOS behavior.
    @discardableResult
    func setEnabled(_ enabled: Bool) -> IOReturn {
        guard enabled != isEnabled else { return kIOReturnSuccess }
        let result: IOReturn
        if enabled {
            var newID: IOPMAssertionID = 0
            result = IOPMAssertionCreateWithName(
                kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                "NetSpeed Keep Awake" as CFString, &newID)
            if result == kIOReturnSuccess { assertionID = newID }
        } else if let id = assertionID {
            result = IOPMAssertionRelease(id)
            if result == kIOReturnSuccess { assertionID = nil }
        } else {
            return kIOReturnSuccess
        }
        update()
        return result
    }

    deinit {
        if let id = assertionID { IOPMAssertionRelease(id) }
    }
}
