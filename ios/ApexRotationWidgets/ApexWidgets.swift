import SwiftUI
import WidgetKit

// MARK: - 数据

struct RotationEntry: TimelineEntry {
    let date: Date
    let current: RotationSlot
    let upcoming: [RotationSlot]
    let calibrated: Bool
}

extension RotationEntry {
    static var placeholder: RotationEntry {
        let config = RotationConfig.fallback
        let now = Date()
        let slot = RotationEngine.slot(at: now, config: config)
            ?? RotationSlot(map: SeedMaps.entries[0], start: now, end: now.addingTimeInterval(3600))
        let upcoming = Array(RotationEngine.upcoming(at: now, config: config, count: 4).dropFirst())
        return RotationEntry(date: now, current: slot, upcoming: upcoming, calibrated: true)
    }
}

struct RotationProvider: TimelineProvider {
    func placeholder(in context: Context) -> RotationEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (RotationEntry) -> Void) {
        completion(.placeholder)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RotationEntry>) -> Void) {
        let config = SharedConfig.load()
        completion(Timeline(entries: Self.makeEntries(config: config, now: .now), policy: .atEnd))
    }

    /// 进度环需要足够细的取样，倒计时本身由系统托管。
    static func makeEntries(config: RotationConfig, now: Date) -> [RotationEntry] {
        var dates: [Date] = [now]
        for step in 1...6 {
            dates.append(now.addingTimeInterval(Double(step) * 600))
        }
        for step in 1...6 {
            dates.append(now.addingTimeInterval(3600 + Double(step) * 1800))
        }
        for step in 1...10 {
            dates.append(now.addingTimeInterval(4 * 3600 + Double(step) * 3600))
        }

        return Array(Set(dates)).sorted().compactMap { date in
            guard let slot = RotationEngine.slot(at: date, config: config) else { return nil }
            let upcoming = RotationEngine.upcoming(at: date, config: config, count: 4).dropFirst()
            return RotationEntry(
                date: date,
                current: slot,
                upcoming: Array(upcoming),
                calibrated: config.calibrated
            )
        }
    }
}

// MARK: - 小组件

struct SmallCurrentWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "small_current", provider: RotationProvider()) { entry in
            if entry.calibrated {
                SmallCurrentView(entry: entry)
            } else {
                UncalibratedWidgetView()
            }
        }
        .configurationDisplayName("当前地图")
        .description("地图大图、名称和剩余时间。")
        .supportedFamilies([.systemSmall])
    }
}

struct SmallCountdownWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "small_countdown", provider: RotationProvider()) { entry in
            if entry.calibrated {
                SmallCountdownView(entry: entry)
            } else {
                UncalibratedWidgetView()
            }
        }
        .configurationDisplayName("只看倒计时")
        .description("超大数字，一眼看到还剩多久。")
        .supportedFamilies([.systemSmall])
    }
}

struct SmallRingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "small_ring", provider: RotationProvider()) { entry in
            if entry.calibrated {
                SmallRingView(entry: entry)
            } else {
                UncalibratedWidgetView()
            }
        }
        .configurationDisplayName("进度环")
        .description("大圆环显示当前这一小时的进度。")
        .supportedFamilies([.systemSmall])
    }
}

struct SmallRingNameWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "small_ring_name", provider: RotationProvider()) { entry in
            if entry.calibrated {
                SmallRingNameView(entry: entry)
            } else {
                UncalibratedWidgetView()
            }
        }
        .configurationDisplayName("圆环 + 地图名")
        .description("地图名放在圆环中央，下面是剩余时间。")
        .supportedFamilies([.systemSmall])
    }
}

struct MediumSplitWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "medium_split", provider: RotationProvider()) { entry in
            if entry.calibrated {
                MediumSplitView(entry: entry)
            } else {
                UncalibratedWidgetView()
            }
        }
        .configurationDisplayName("当前 + 下一张（分栏）")
        .description("左边当前地图大图，右边下一张。")
        .supportedFamilies([.systemMedium])
    }
}

struct MediumDualWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "medium_dual", provider: RotationProvider()) { entry in
            if entry.calibrated {
                MediumDualView(entry: entry)
            } else {
                UncalibratedWidgetView()
            }
        }
        .configurationDisplayName("当前 + 下一张（整图）")
        .description("一整张地图大图，左右分栏。")
        .supportedFamilies([.systemMedium])
    }
}

struct LargeListWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "large_list", provider: RotationProvider()) { entry in
            if entry.calibrated {
                LargeListView(entry: entry)
            } else {
                UncalibratedWidgetView()
            }
        }
        .configurationDisplayName("大图 + 排程")
        .description("上方当前地图大图，下方接下来三张。")
        .supportedFamilies([.systemLarge])
    }
}

struct LargeOverlayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "large_overlay", provider: RotationProvider()) { entry in
            if entry.calibrated {
                LargeOverlayView(entry: entry)
            } else {
                UncalibratedWidgetView()
            }
        }
        .configurationDisplayName("沉浸大图")
        .description("整张大图，信息压在底部。")
        .supportedFamilies([.systemLarge])
    }
}

@main
struct ApexWidgetsBundle: WidgetBundle {
    var body: some Widget {
        SmallCurrentWidget()
        SmallCountdownWidget()
        SmallRingWidget()
        SmallRingNameWidget()
        MediumSplitWidget()
        MediumDualWidget()
        LargeListWidget()
        LargeOverlayWidget()
    }
}
