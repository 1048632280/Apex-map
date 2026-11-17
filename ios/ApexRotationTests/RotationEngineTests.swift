import XCTest
@testable import ApexRotation

final class RotationEngineTests: XCTestCase {
    private let maps = [
        MapEntry(slug: "a", name: "A", art: "", thumb: ""),
        MapEntry(slug: "b", name: "B", art: "", thumb: ""),
        MapEntry(slug: "c", name: "C", art: "", thumb: "")
    ]

    private func config(anchor: Date, seconds: Int = 3600) -> RotationConfig {
        RotationConfig(maps: maps, secondsPerMap: seconds, anchor: anchor, calibrated: true, updatedAt: anchor)
    }

    func testSlotAtAnchorStartsFirstMap() {
        let anchor = Date(timeIntervalSince1970: 1_800_000_000)
        let slot = RotationEngine.slot(at: anchor, config: config(anchor: anchor))

        XCTAssertEqual(slot?.map.slug, "a")
        XCTAssertEqual(slot?.start, anchor)
        XCTAssertEqual(slot?.end, anchor.addingTimeInterval(3600))
    }

    func testSecondSlot() {
        let anchor = Date(timeIntervalSince1970: 1_800_000_000)
        let now = anchor.addingTimeInterval(3600 + 600)
        let slot = RotationEngine.slot(at: now, config: config(anchor: anchor))

        XCTAssertEqual(slot?.map.slug, "b")
        XCTAssertEqual(slot?.start, anchor.addingTimeInterval(3600))
    }

    func testRotationWrapsAround() {
        let anchor = Date(timeIntervalSince1970: 1_800_000_000)
        let now = anchor.addingTimeInterval(3 * 3600 + 60)
        let slot = RotationEngine.slot(at: now, config: config(anchor: anchor))

        XCTAssertEqual(slot?.map.slug, "a")
        XCTAssertEqual(slot?.start, anchor.addingTimeInterval(3 * 3600))
    }

    func testBeforeAnchorUsesPreviousCycle() {
        let anchor = Date(timeIntervalSince1970: 1_800_000_000)
        let now = anchor.addingTimeInterval(-60)
        let slot = RotationEngine.slot(at: now, config: config(anchor: anchor))

        XCTAssertEqual(slot?.map.slug, "c")
        XCTAssertEqual(slot?.start, anchor.addingTimeInterval(-3600))
    }

    func testUpcomingOrderAndSpacing() {
        let anchor = Date(timeIntervalSince1970: 1_800_000_000)
        let slots = RotationEngine.upcoming(at: anchor, config: config(anchor: anchor), count: 6)

        XCTAssertEqual(slots.map { $0.map.slug }, ["a", "b", "c", "a", "b", "c"])
        for index in 1..<slots.count {
            XCTAssertEqual(slots[index].start, slots[index - 1].end)
        }
    }

    func testCalibrationRoundTrip() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let switchAt = now.addingTimeInterval(25 * 60)
        let anchor = RotationEngine.anchor(currentMapIndex: 1, nextSwitchAt: switchAt, secondsPerMap: 3600)

        let slot = RotationEngine.slot(at: now, config: config(anchor: anchor))

        XCTAssertEqual(slot?.map.slug, "b")
        XCTAssertEqual(slot?.end, switchAt)
    }

    func testPlausibility() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        XCTAssertTrue(
            RotationEngine.isPlausible(nextSwitchAt: now.addingTimeInterval(600), now: now, secondsPerMap: 3600)
        )
        XCTAssertFalse(
            RotationEngine.isPlausible(nextSwitchAt: now.addingTimeInterval(7200), now: now, secondsPerMap: 3600)
        )
        XCTAssertFalse(
            RotationEngine.isPlausible(nextSwitchAt: now.addingTimeInterval(-600), now: now, secondsPerMap: 3600)
        )
    }

    func testFloorDivHandlesNegatives() {
        XCTAssertEqual(RotationEngine.floorDiv(-1, 3600), -1)
        XCTAssertEqual(RotationEngine.floorDiv(-3600, 3600), -1)
        XCTAssertEqual(RotationEngine.floorDiv(-3601, 3600), -2)
        XCTAssertEqual(RotationEngine.floorDiv(0, 3600), 0)
        XCTAssertEqual(RotationEngine.floorDiv(3599, 3600), 0)
        XCTAssertEqual(RotationEngine.floorDiv(3600, 3600), 1)
    }

    func testProgressAndRemaining() {
        let anchor = Date(timeIntervalSince1970: 1_800_000_000)
        let slot = RotationEngine.slot(at: anchor.addingTimeInterval(1800), config: config(anchor: anchor))!

        XCTAssertEqual(slot.remaining(at: anchor.addingTimeInterval(1800)), 1800, accuracy: 0.001)
        XCTAssertEqual(slot.progress(at: anchor.addingTimeInterval(1800)), 0.5, accuracy: 0.001)
    }

    func testAgoFormatting() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertEqual(TimeFormat.ago(from: now, to: now.addingTimeInterval(-30)), "刚刚")
        XCTAssertEqual(TimeFormat.ago(from: now, to: now.addingTimeInterval(-180)), "3 分钟前")
        XCTAssertEqual(TimeFormat.ago(from: now, to: now.addingTimeInterval(-3 * 3600)), "3 小时前")
        XCTAssertEqual(TimeFormat.ago(from: now, to: now.addingTimeInterval(-50 * 3600)), "2 天前")
    }

    func testRelativeFormatting() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertEqual(TimeFormat.relative(from: now, to: now.addingTimeInterval(43 * 60)), "43 分钟后")
        XCTAssertEqual(TimeFormat.relative(from: now, to: now.addingTimeInterval(3600)), "1 小时后")
        XCTAssertEqual(TimeFormat.relative(from: now, to: now.addingTimeInterval(3600 + 43 * 60)), "1 小时 43 分后")
    }
}
