import Foundation

// MARK: - 地图

struct MapEntry: Codable, Identifiable, Hashable {
    let slug: String
    var name: String
    /// 官图资源名（不含扩展名）
    var art: String
    /// 缩略图资源名（不含扩展名）
    var thumb: String

    var id: String { slug }
}

// MARK: - 配置

struct RotationConfig: Codable, Equatable {
    /// 顺序即轮换顺序
    var maps: [MapEntry]
    /// 每张图时长（秒）
    var secondsPerMap: Int
    /// 锚点：某个槽位的开始时刻（绝对时间）
    var anchor: Date
    /// 是否校准过
    var calibrated: Bool
    var updatedAt: Date

    static let defaultSecondsPerMap = 3600

    static var fallback: RotationConfig {
        RotationConfig(
            maps: SeedMaps.entries,
            secondsPerMap: defaultSecondsPerMap,
            anchor: Date(timeIntervalSince1970: 1_767_225_600), // 2026-01-01T00:00:00Z
            calibrated: false,
            updatedAt: .now
        )
    }
}

// MARK: - 种子地图（与 public/image 下的素材对应）

enum SeedMaps {
    static let entries: [MapEntry] = [
        MapEntry(slug: "broken-moon", name: "Broken Moon", art: "broken-moon-official", thumb: "broken-moon-thumb"),
        MapEntry(slug: "e-district", name: "E-District", art: "e-district-official", thumb: "e-district-thumb"),
        MapEntry(slug: "kings-canyon", name: "Kings Canyon", art: "kings-canyon-official", thumb: "kings-canyon-thumb"),
        MapEntry(slug: "olympus", name: "Olympus", art: "olympus-official", thumb: "olympus-thumb"),
        MapEntry(slug: "storm-point", name: "Storm Point", art: "storm-point-official", thumb: "storm-point-thumb"),
        MapEntry(slug: "worlds-edge", name: "World's Edge", art: "worlds-edge-official", thumb: "worlds-edge-thumb")
    ]
}

// MARK: - 槽位

struct RotationSlot: Identifiable, Equatable {
    let map: MapEntry
    let start: Date
    let end: Date

    var id: Date { start }
    var duration: TimeInterval { end.timeIntervalSince(start) }

    func remaining(at now: Date) -> TimeInterval {
        max(0, end.timeIntervalSince(now))
    }

    func progress(at now: Date) -> Double {
        guard duration > 0 else { return 0 }
        return min(1, max(0, now.timeIntervalSince(start) / duration))
    }
}

// MARK: - 纯计算

enum RotationEngine {
    /// 向下取整的整数除法，负数也要正确
    static func floorDiv(_ value: Int64, _ divisor: Int64) -> Int64 {
        precondition(divisor > 0)
        let quotient = value / divisor
        return value % divisor != 0 && value < 0 ? quotient - 1 : quotient
    }

    static func slotNumber(at now: Date, config: RotationConfig) -> Int64 {
        let step = Int64(max(1, config.secondsPerMap))
        let seconds = Int64(now.timeIntervalSince(config.anchor).rounded(.down))
        return floorDiv(seconds, step)
    }

    static func index(for slotNumber: Int64, mapCount: Int) -> Int {
        guard mapCount > 0 else { return 0 }
        let count = Int64(mapCount)
        return Int(((slotNumber % count) + count) % count)
    }

    static func upcoming(at now: Date, config: RotationConfig, count: Int) -> [RotationSlot] {
        guard !config.maps.isEmpty, count > 0, config.secondsPerMap > 0 else { return [] }

        let step = Int64(config.secondsPerMap)
        let number = slotNumber(at: now, config: config)
        let start = config.anchor.addingTimeInterval(Double(number * step))
        let startIndex = index(for: number, mapCount: config.maps.count)

        return (0..<count).map { offset in
            let slotStart = start.addingTimeInterval(Double(Int64(offset) * step))
            return RotationSlot(
                map: config.maps[(startIndex + offset) % config.maps.count],
                start: slotStart,
                end: slotStart.addingTimeInterval(Double(step))
            )
        }
    }

    static func slot(at now: Date, config: RotationConfig) -> RotationSlot? {
        upcoming(at: now, config: config, count: 1).first
    }

    /// 用户给出「当前是第 i 张，它将在 nextSwitchAt 结束」后反推锚点
    static func anchor(currentMapIndex: Int, nextSwitchAt: Date, secondsPerMap: Int) -> Date {
        let offset = Double((currentMapIndex + 1) * max(1, secondsPerMap))
        return nextSwitchAt.addingTimeInterval(-offset)
    }

    /// 结束时间是否落在当前槽位之内
    static func isPlausible(nextSwitchAt: Date, now: Date, secondsPerMap: Int) -> Bool {
        let step = Double(max(1, secondsPerMap))
        let start = nextSwitchAt.addingTimeInterval(-step)
        return now >= start.addingTimeInterval(-1) && now < nextSwitchAt
    }
}

// MARK: - 格式化

enum TimeFormat {
    static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    static func range(_ start: Date, _ end: Date) -> String {
        "\(clock.string(from: start)) – \(clock.string(from: end))"
    }

    /// 42 分钟后 / 1 小时 43 分
    static func relative(from now: Date, to date: Date) -> String {
        let seconds = max(0, Int(date.timeIntervalSince(now)))
        let minutes = seconds / 60
        if minutes < 60 {
            return "\(max(1, minutes)) 分钟后"
        }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours) 小时后" : "\(hours) 小时 \(rest) 分后"
    }

    static func countdown(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded(.down)))
        return String(format: "%02d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }

    /// 刚刚 / 3 分钟前 / 3 小时前 / 2 天前
    static func ago(from now: Date, to date: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 60 { return "刚刚" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes) 分钟前" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours) 小时前" }
        return "\(hours / 24) 天前"
    }
}
