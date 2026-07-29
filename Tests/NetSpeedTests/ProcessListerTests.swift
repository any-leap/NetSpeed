import XCTest
@testable import NetSpeed

final class ProcessListerTests: XCTestCase {
    /// Apple Silicon 的 mach timebase：125/3 ≈ 41.667 ns/tick。
    private let appleSiliconNsPerTick = 125.0 / 3.0
    /// Intel 的 mach timebase：1/1，tick 即纳秒。
    private let intelNsPerTick = 1.0

    /// 回归：pti_total_* 是 mach tick 而非纳秒。在 Apple Silicon 上把 tick 当纳秒
    /// 会把 8 核满载（800%）报成 19.2%，正是活动监视器 1200% 却只显示「30%几」的成因。
    func testEightCoresSaturatedReportsEightHundredPercentOnAppleSilicon() {
        // 8 核跑满 2 秒 = 16 秒 CPU 时间，换算成 tick
        let ticks = UInt64(16.0 * 1_000_000_000.0 / appleSiliconNsPerTick)

        let pct = ProcessLister.cpuPercent(
            deltaTicks: ticks,
            deltaWallSeconds: 2.0,
            nsPerTick: appleSiliconNsPerTick
        )

        XCTAssertEqual(pct, 800.0, accuracy: 0.01)
    }

    func testSingleCoreSaturatedReportsOneHundredPercentOnAppleSilicon() {
        let ticks = UInt64(2.0 * 1_000_000_000.0 / appleSiliconNsPerTick)

        let pct = ProcessLister.cpuPercent(
            deltaTicks: ticks,
            deltaWallSeconds: 2.0,
            nsPerTick: appleSiliconNsPerTick
        )

        XCTAssertEqual(pct, 100.0, accuracy: 0.01)
    }

    /// Intel 上 tick == 纳秒，同样的口径必须仍然成立（旧代码在这里碰巧是对的）。
    func testIntelTimebaseIsUnaffected() {
        let ticks = UInt64(2.0 * 1_000_000_000.0) // 1 核满载 2 秒

        let pct = ProcessLister.cpuPercent(
            deltaTicks: ticks,
            deltaWallSeconds: 2.0,
            nsPerTick: intelNsPerTick
        )

        XCTAssertEqual(pct, 100.0, accuracy: 0.01)
    }

    /// 跑满的进程必须越过 CPUGuard 的 50% 阈值——修复前它要到 2083% 才可能触发，
    /// 也就是超过 14 核机器 1400% 的物理上限，等于告警永久失效。
    func testSaturatedProcessCrossesCPUGuardThreshold() {
        let ticks = UInt64(2.0 * 1_000_000_000.0 / appleSiliconNsPerTick)

        let pct = ProcessLister.cpuPercent(
            deltaTicks: ticks,
            deltaWallSeconds: 2.0,
            nsPerTick: appleSiliconNsPerTick
        )

        XCTAssertGreaterThanOrEqual(pct, CPUMonitor().cpuThreshold)
    }

    func testIdleProcessReportsZero() {
        let pct = ProcessLister.cpuPercent(
            deltaTicks: 0,
            deltaWallSeconds: 2.0,
            nsPerTick: appleSiliconNsPerTick
        )

        XCTAssertEqual(pct, 0.0, accuracy: 0.0001)
    }

    /// 两次采样撞在同一时刻（多个调用点同时命中）不得产生 Inf/NaN。
    func testZeroWallIntervalReturnsZeroInsteadOfInfinity() {
        let pct = ProcessLister.cpuPercent(
            deltaTicks: 12_345,
            deltaWallSeconds: 0,
            nsPerTick: appleSiliconNsPerTick
        )

        XCTAssertEqual(pct, 0.0)
    }

    /// 节流窗口内的重复调用复用上次结果，不会把 baseline 冲掉。
    func testRapidSuccessiveCallsReuseCachedSample() {
        let lister = ProcessLister()
        _ = lister.topProcesses(limit: 5)      // 建立 baseline，此时全为 0
        Thread.sleep(forTimeInterval: 1.2)     // 越过 minSampleInterval，真实采样
        let sampled = lister.topProcesses(limit: 5)
        let immediate = lister.topProcesses(limit: 5)  // 窗口内 → 应命中缓存

        XCTAssertEqual(sampled.map(\.pid), immediate.map(\.pid))
        XCTAssertEqual(sampled.map(\.cpu), immediate.map(\.cpu))
    }

    /// 缓存的是完整排序结果，不同 limit 切片必须自洽（调用点用 5 / 200 / 500）。
    func testCachedResultsSliceConsistentlyAcrossLimits() {
        let lister = ProcessLister()
        _ = lister.topProcesses(limit: 500)
        Thread.sleep(forTimeInterval: 1.2)
        let many = lister.topProcesses(limit: 500)
        let few = lister.topProcesses(limit: 5)

        XCTAssertEqual(few.map(\.pid), Array(many.prefix(5)).map(\.pid))
    }
}
